//
//  HBScheduler.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBScheduler.h"
#import "HBRecording.h"
#include "hdhomerun.h"


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
        
        recording.statusIconImage = [NSImage imageNamed:@"scheduled"];
    }
    // if it already exists, just mark it as completed
    else recording.statusIconImage = [NSImage imageNamed:@"clapperboard"];
    
    [self.scheduledRecordings addObject:recording];
}

- (void)startRecording:(HBRecording *)recording
{
    int max_device_count = 8;
    struct hdhomerun_discover_device_t device_list[max_device_count];
    int devices_found_count = hdhomerun_discover_find_devices_custom(0, // auto-detect IP address
                                                                     HDHOMERUN_DEVICE_TYPE_TUNER,
                                                                     HDHOMERUN_DEVICE_ID_WILDCARD,
                                                                     device_list,
                                                                     max_device_count);
    if (devices_found_count == -1) {
        NSLog(@"error when discovering devices");
        return;
    }
    
    for (int device_index = 0; device_index < devices_found_count; device_index++) {
        struct hdhomerun_discover_device_t *discovered_device = &device_list[device_index];
        
        NSLog(@"ip_addr: %u, device_id: %X, tuner_count: %hhu",
              discovered_device->ip_addr,
              discovered_device->device_id,
              discovered_device->tuner_count);
        
        uint8_t tuner_count = discovered_device->tuner_count;

        struct hdhomerun_device_t *tuner_device = hdhomerun_device_create(HDHOMERUN_DEVICE_ID_WILDCARD,
                                                                          discovered_device->ip_addr,
                                                                          0,
                                                                          NULL); // no debug info

        for (uint8_t tuner_index = 0; tuner_index < tuner_count; tuner_index++) {
            hdhomerun_device_set_tuner(tuner_device, tuner_index);
            char *tuner_target;
            // XXX check for error
            hdhomerun_device_get_tuner_target(tuner_device, &tuner_target);
            NSLog(@"tuner index: %hhu target: %s", tuner_index, tuner_target);
            
            if (strcmp(tuner_target, "none") == 0) {
                NSLog(@"tuner %hhu is available", tuner_index);
                // XXX check for error
                // XXX set lock
                hdhomerun_device_set_tuner_vchannel(tuner_device,
                                                    [recording.rfChannel cStringUsingEncoding:NSASCIIStringEncoding]);
                recording.tunerDevice = tuner_device;
                
                recording.fileDescriptor = open([recording.recordingFilePath fileSystemRepresentation],
                                                O_CREAT|O_WRONLY);
                
                [NSThread detachNewThreadSelector:@selector(receiveStreamForRecording:)
                                         toTarget:self
                                       withObject:recording];
                
                recording.statusIconImage = [NSImage imageNamed:@"red"];
                recording.status = @"recording";
                recording.currentlyRecording = YES;
                self.activeRecordingCount += 1;
                [self updateDockTile];
                return;
            }
        }
        
        hdhomerun_device_destroy(tuner_device);
    }
}

- (void)receiveStreamForRecording:(HBRecording *)recording
{
    size_t max_buffer_size = 1024 * 1024;
    size_t buffer_size;
    struct hdhomerun_device_t *tuner_device = recording.tunerDevice;
    int fd = recording.fileDescriptor;
    hdhomerun_device_stream_start(tuner_device);

    while (recording.currentlyRecording) {
        uint8_t *buffer = hdhomerun_device_stream_recv(tuner_device, max_buffer_size, &buffer_size);
        write(fd, buffer, buffer_size);
        usleep(15000);
    }
    
    hdhomerun_device_stream_stop(tuner_device);
    hdhomerun_device_destroy(tuner_device);
    close(fd);
}

- (void)stopRecording:(HBRecording *)recording
{
    [self cancelTimersForRecording:recording];

    recording.currentlyRecording = NO;
    recording.tunerDevice = NULL;
    
    recording.status = @"";
    recording.statusIconImage = [NSImage imageNamed:@"clapperboard"];
    
    self.activeRecordingCount -= 1;
    [self updateDockTile];
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

@end
