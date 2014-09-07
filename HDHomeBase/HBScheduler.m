//
//  HBScheduler.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBScheduler.h"
#import "HBRecording.h"

#import "HDHRTunerReservation.h"
#import "HDHRDeviceManager.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>

#import <IOKit/pwr_mgt/IOPMLib.h>

@interface HBScheduler ()

@property NSUInteger activeRecordingCount;

@end

@implementation HBScheduler

- (instancetype)init
{
    if ((self = [super init])) {
        _scheduledRecordings = [NSMutableArray new];
        _activeRecordingCount = 0;
    }
    
    return self;
}

- (NSString *)recordingsFolder
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"RecordingsFolder"];
}

- (void)importExistingRecordings
{
    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    NSArray *recordingsFolderContents = [defaultFileManager contentsOfDirectoryAtPath:self.recordingsFolder error:NULL];
    
    for (NSString *file in recordingsFolderContents)
        if ([file hasSuffix:@".plist"]) [self importPropertyListFile:[self.recordingsFolder stringByAppendingPathComponent:file]];
}

- (void)importTVPIFile:(NSString *)tvpiFilePath
{
    HBRecording *recording = [HBRecording recordingFromTVPIFile:tvpiFilePath];
    
    NSString *newPropertyListFilename = [recording.uniqueName stringByAppendingString:@".plist"];
    NSString *newPropertyListPath = [self.recordingsFolder stringByAppendingPathComponent:newPropertyListFilename];
    
    [recording serializeAsPropertyListFileToPath:newPropertyListPath error:NULL];
    recording.propertyListFilePath = newPropertyListPath;
    [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:tvpiFilePath]
                                  resultingItemURL:NULL
                                             error:NULL];
    [self scheduleRecording:recording];
}

- (void)importPropertyListFile:(NSString *)propertyListFilePath
{
    HBRecording *recording = [HBRecording recordingFromPropertyListFile:propertyListFilePath];
    recording.propertyListFilePath = propertyListFilePath;
    [self scheduleRecording:recording];
}

- (void)scheduleRecording:(HBRecording *)recording
{
    recording.recordingFilePath = [[self recordingsFolder] stringByAppendingPathComponent:recording.recordingFilename];
    BOOL endDateHasPassed = ([recording.endDate compare:[NSDate date]] == NSOrderedAscending);
    BOOL recordingFileExists = [[NSFileManager defaultManager] fileExistsAtPath:recording.recordingFilePath];
    
    // only if the end date hasn't passed, and the file doesn't already exist, are we interested
    if (!endDateHasPassed && !recordingFileExists) {
        NSTimeInterval beginningPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"BeginningPadding"];
        recording.startTimer = [[NSTimer alloc] initWithFireDate:[recording.startDate dateByAddingTimeInterval:-beginningPadding]
                                                        interval:0
                                                          target:self
                                                        selector:@selector(startRecordingTimerFired:)
                                                        userInfo:recording
                                                         repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:recording.startTimer
                                  forMode:NSRunLoopCommonModes];
        
        NSTimeInterval endingPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"EndingPadding"];
        recording.stopTimer = [[NSTimer alloc] initWithFireDate:[recording.endDate dateByAddingTimeInterval:endingPadding]
                                                       interval:0
                                                         target:self
                                                       selector:@selector(stopRecordingTimerFired:)
                                                       userInfo:recording
                                                        repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:recording.stopTimer
                                  forMode:NSRunLoopCommonModes];
        
        [recording markAsScheduled];
    }
    // if it already exists, just mark it as completed
    else [recording markAsSuccess];
    
    [self.scheduledRecordings addObject:recording];
}

- (void)updateStatusForRecording:(HBRecording *)recording
                          string:(NSString *)statusString
                       imageName:(NSString *)statusImageName
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusString) recording.status = statusString;
        if (statusImageName) recording.statusIconImage = [NSImage imageNamed:statusImageName];
    });
}

- (void)startRecording:(HBRecording *)recording
{
    recording.status = @"searching for available tuner…";
    
    void (^reservationBlock)(HDHRTunerReservation *, dispatch_semaphore_t) = ^(HDHRTunerReservation *tunerReservation, dispatch_semaphore_t sema) {
        if (tunerReservation == nil) {
            [self updateStatusForRecording:recording string:nil imageName:@"scheduled_fail"];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cancelTimersForRecording:recording];
            });
            dispatch_semaphore_signal(sema);
            return;
        }
                           
        recording.tunerReservation = tunerReservation;

        [self updateStatusForRecording:recording
                                string:[NSString stringWithFormat:@"tuning to channel %@…", recording.rfChannel]
                             imageName:nil];

        [tunerReservation tuneToChannel:recording.rfChannel tuningCompletedBlock:^(BOOL success) {
            if (!success) {
                [self updateStatusForRecording:recording string:nil imageName:@"scheduled_fail"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self cancelTimersForRecording:recording];
                });
                dispatch_semaphore_signal(sema);
                return;
            }
            
            [self updateStatusForRecording:recording string:@"starting stream…" imageName:nil];

            [self recordUDPStreamForRecording:recording];
            [tunerReservation startStreamingToIPAddress:tunerReservation.targetIPAddress port:recording.targetPort];
            dispatch_semaphore_signal(sema);
            
            [self updateStatusForRecording:recording string:@"recording" imageName:@"red"];
            recording.currentlyRecording = YES;
            self.activeRecordingCount += 1;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateDockTile];
            });
        }];
    };
    
    void (^statusBlock)(NSString *) = ^(NSString *status) {
        [self updateStatusForRecording:recording string:status imageName:nil];
    };
    
    [self.deviceManager requestTunerReservationBlock:reservationBlock statusBlock:statusBlock];
}

- (void)cancelTimersForRecording:(HBRecording *)recording
{
    if (recording.startTimer) {
        [recording.startTimer invalidate];
        recording.startTimer = nil;
    }
    
    if (recording.stopTimer) {
        [recording.stopTimer invalidate];
        recording.stopTimer = nil;
    }
}

- (void)stopRecording:(HBRecording *)recording
{
    [self updateStatusForRecording:recording string:@"" imageName:nil];
    
    if (recording.udpSource) dispatch_source_cancel(recording.udpSource);

    [self cancelTimersForRecording:recording];

    recording.udpSource = nil;
    recording.currentlyRecording = NO;

    self.activeRecordingCount -= 1;
    [self updateDockTile];
    [recording markAsSuccess];
}

- (void)playRecording:(HBRecording *)recording
{
    [[NSWorkspace sharedWorkspace] openFile:recording.recordingFilePath];
}

- (void)deleteRecording:(HBRecording *)recording
{
    if (recording.currentlyRecording) [self stopRecording:recording];

    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    [defaultFileManager trashItemAtURL:[NSURL fileURLWithPath:recording.recordingFilePath]
                      resultingItemURL:NULL
                                 error:NULL];
    [defaultFileManager trashItemAtURL:[NSURL fileURLWithPath:recording.propertyListFilePath]
                      resultingItemURL:NULL
                                 error:NULL];

    [self.scheduledRecordings removeObject:recording];
}

- (void)startRecordingTimerFired:(NSTimer *)timer
{
    HBRecording *recording = [timer userInfo];
    [self startRecording:recording];
}

- (void)stopRecordingTimerFired:(NSTimer *)timer
{
    HBRecording *recording = [timer userInfo];
    [self stopRecording:recording];
}

- (void)updateDockTile
{
    NSDockTile *dockTile = [NSApp dockTile];
    dockTile.badgeLabel = (self.activeRecordingCount) ? [NSString stringWithFormat:@"%lu", (unsigned long)self.activeRecordingCount] : nil;
}

- (BOOL)recordUDPStreamForRecording:(HBRecording *)recording
{
    NSLog(@"saving UDP stream to %@", recording.recordingFilePath);
    
    [[NSFileManager defaultManager] createFileAtPath:recording.recordingFilePath contents:nil attributes:nil];
    
    dispatch_io_t outputChannel = dispatch_io_create_with_path(DISPATCH_IO_STREAM,
                                                               [recording.recordingFilePath cStringUsingEncoding:NSASCIIStringEncoding],
                                                               O_CREAT|O_WRONLY,
                                                               S_IWUSR|S_IRUSR,
                                                               dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                                               ^(int error) {
                                                                   if (error)
                                                                       NSLog(@"There was a problem opening the recording file. %d (%s)\n",
                                                                               error,
                                                                               strerror(error));
                                                                   });
    
    NSLog(@"opening UDP socket");
    int socketfd = socket(PF_INET, SOCK_DGRAM, 0);
    
    if (socketfd == -1) {
        NSLog(@"a");
        return NO;
    }
    
    NSLog(@"setting UDP socket to non-blocking");
    if (fcntl(socketfd, F_SETFL, O_NONBLOCK) == -1) {
        close(socketfd);
        NSLog(@"b");
        return NO;
    }
    
    struct sockaddr_in sockAddrIn;
    sockAddrIn.sin_family = AF_INET;
    sockAddrIn.sin_port = htons(0);
    sockAddrIn.sin_addr.s_addr = inet_addr([recording.tunerReservation.targetIPAddress cStringUsingEncoding:NSASCIIStringEncoding]);
    memset(sockAddrIn.sin_zero, '\0', sizeof(sockAddrIn.sin_zero));
    
    if (bind(socketfd, (struct sockaddr *)&sockAddrIn, sizeof(sockAddrIn)) != 0) {
        NSLog(@"c");
        return NO;
    }
    
    socklen_t addressLength = sizeof(sockAddrIn);
    if (getsockname(socketfd, (struct sockaddr *)&sockAddrIn, &addressLength) != 0) {
        NSLog(@"d");
        return NO;
    }
    
    recording.targetPort = ntohs(sockAddrIn.sin_port);
    NSLog(@"bound UDP socket to %hu", recording.targetPort);
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t socketReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socketfd, 0, queue);
    
    recording.udpSource = socketReadSource;
    
    dispatch_source_set_event_handler(socketReadSource, ^{
        size_t estimatedReadLength = dispatch_source_get_data(socketReadSource);
        UInt8 *bytes = (UInt8 *)malloc(estimatedReadLength);
        
        if (bytes) {
            struct sockaddr_in theirAddress;
            socklen_t addressLength = sizeof(theirAddress);
            
            ssize_t receivedByteCount = recvfrom(socketfd,
                                                 bytes,
                                                 estimatedReadLength,
                                                 0,
                                                 (struct sockaddr *)&theirAddress,
                                                 &addressLength);

            dispatch_data_t data = dispatch_data_create(bytes, receivedByteCount, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
            dispatch_io_write(outputChannel,
                              0,
                              data,
                              dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(bool done, dispatch_data_t data, int error) {
                              });
        }
    });
    
    dispatch_source_set_cancel_handler(socketReadSource, ^{
        NSLog(@"close UDP socket");
        close(socketfd);
        dispatch_io_close(outputChannel, 0);
        NSLog(@"closed everything!");
    });
    
    IOPMAssertionID assertionID;
    IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep,
                                                   kIOPMAssertionLevelOn,
                                                   (__bridge CFStringRef)recording.recordingFilePath,
                                                   &assertionID);
    
    if (success != kIOReturnSuccess)
        NSLog(@"unable to create power assertion");
    
    dispatch_resume(socketReadSource);
    
    success = IOPMAssertionRelease(assertionID);
    
    return YES;
}

@end
