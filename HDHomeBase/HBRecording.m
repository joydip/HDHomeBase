//
//  HBRecording.m
//  HDHomeBase
//
//  Created by Joydip Basu on 11/22/14.
//  Copyright (c) 2014 Joydip Basu. All rights reserved.
//

#import "HBRecording.h"
#import "HBProgram.h"
#import "HBScheduler.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
#include "hdhomerun.h"


@interface HBRecording ()

@property (readonly) NSDate *paddedStartDate;
@property (readonly) NSDate *paddedEndDate;
@property NSTimer *startTimer;
@property NSTimer *stopTimer;
@property FILE *filePointer;
@property IOPMAssertionID assertionID;
@property struct hdhomerun_device_t *tunerDevice;
@property BOOL shouldStream;


// dynamically computed properties
@property (readonly) NSString *canonicalChannel;

@end

@implementation HBRecording

+ (NSDateFormatter *)recordingFileDateFormatter
{
    static dispatch_once_t predicate;
    static NSDateFormatter *dateFormatter = nil;
    
    dispatch_once(&predicate, ^{
        dateFormatter = [NSDateFormatter new];
        [dateFormatter setDateFormat:@"yyyyMMddHHmm"];
    });
    
    return dateFormatter;
}

- (NSString *)uniqueName
{
    NSString *recordingFileDateString = [[[self class] recordingFileDateFormatter] stringFromDate:self.program.startDate];
    NSString *baseName = (self.program.episode.length) ? [NSString stringWithFormat:@"%@ - %@", self.program.title, self.program.episode] : self.program.title;
    return [NSString stringWithFormat:@"%@ (%@ %@)", baseName, self.program.channelName, recordingFileDateString];
}

- (NSString *)episodicName
{
    if (self.program.episode.length) return [NSString stringWithFormat:@"%@ - %@", self.program.title, self.program.episode];
    return nil;
}

- (NSString *)recordingFilename
{
    return [self.uniqueName stringByAppendingString:@".ts"];
}

- (BOOL)recordingFileExists
{
    return [[NSFileManager defaultManager] fileExistsAtPath:self.recordingFilePath];
}

- (void)trashFileAtPath:(NSString *)path
{
    [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:NULL error:NULL];
}

- (void)trashRecordingFile
{
    [self trashFileAtPath:self.recordingFilePath];
}

- (void)trashScheduleFile
{
    [self trashFileAtPath:self.propertyListFilePath];
}

- (NSString *)canonicalChannel
{
    if ([self.program.mode isEqualToString:@"digital"])
        return [NSString stringWithFormat:@"%hu.%hu", self.program.psipMajor, self.program.psipMinor];
    
    return self.program.rfChannel;
}

- (NSDate *)paddedStartDate
{
    NSTimeInterval beginningPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"BeginningPadding"];
    return [self.program.startDate dateByAddingTimeInterval:-beginningPadding];
}

- (NSDate *)paddedEndDate
{
    NSTimeInterval endingPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"EndingPadding"];
    return [self.program.endDate dateByAddingTimeInterval:endingPadding];
}

- (BOOL)startOverlapsWithRecording:(HBRecording *)otherRecording
{
    NSDate *myStartDate = self.paddedStartDate;
    NSDate *otherEndDate = otherRecording.paddedEndDate;
    return ([myStartDate compare:otherEndDate] != NSOrderedDescending);
}

- (BOOL)hasEndDatePassed
{
    return ([self.program.endDate compare:[NSDate date]] != NSOrderedDescending);
}

- (void)scheduleStartTimer
{
    self.startTimer = [[NSTimer alloc] initWithFireDate:self.paddedStartDate
                                               interval:0
                                                 target:self
                                               selector:@selector(startRecordingTimerFired:)
                                               userInfo:self
                                                repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.startTimer
                              forMode:NSRunLoopCommonModes];
}

- (void)cancelStartTimer
{
    [self.startTimer invalidate];
    self.startTimer = nil;
}

- (void)scheduleStopTimer
{
    self.stopTimer = [[NSTimer alloc] initWithFireDate:self.paddedEndDate
                                              interval:0
                                                target:self
                                              selector:@selector(stopRecordingTimerFired:)
                                              userInfo:self
                                               repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.stopTimer
                              forMode:NSRunLoopCommonModes];
}

- (void)cancelStopTimer
{
    [self.stopTimer invalidate];
    self.stopTimer = nil;
}

- (void)cancelTimers
{
    [self cancelStartTimer];
    [self cancelStopTimer];
}

- (void)startRecordingTimerFired:(NSTimer *)timer
{
    [self startRecording];
}

- (void)stopRecordingTimerFired:(NSTimer *)timer
{
    [self stopRecording];
}

- (void)scheduleRecording
{
    // only schedule the timers if the file doesn't exist
    if (!self.recordingFileExists) {
        [self scheduleStartTimer];
        [self scheduleStopTimer];
    } else {
        self.statusIconImage = [NSImage imageNamed:@"clapperboard"];
        self.completed = YES;
        [self trashScheduleFile];
    }
}

- (void)startRecording
{
    self.statusIconImage = [NSImage imageNamed:@"yellow"];
    self.status = @"searching for devices…";
    
    UInt8 maxDeviceCount = 8;
    struct hdhomerun_discover_device_t deviceList[maxDeviceCount];
    int devicesFoundCount = hdhomerun_discover_find_devices_custom(0, // auto-detect IP address
                                                                   HDHOMERUN_DEVICE_TYPE_TUNER,
                                                                   HDHOMERUN_DEVICE_ID_WILDCARD,
                                                                   deviceList,
                                                                   maxDeviceCount);
    if (devicesFoundCount == -1) {
        [self abortWithErrorMessage:@"unable to discover devices"];
        return;
    }
    
    if (devicesFoundCount == 0) {
        [self abortWithErrorMessage:@"no devices found"];
        return;
    }
    
    self.status = @"searching for available tuner…";
    
    for (UInt8 deviceIndex = 0; deviceIndex < devicesFoundCount; deviceIndex++) {
        struct hdhomerun_discover_device_t *discoveredDevice = &deviceList[deviceIndex];
        UInt8 tunerCount = discoveredDevice->tuner_count;
        NSLog(@"examining device %X with %hhu tuners", discoveredDevice->device_id, tunerCount);
        
        struct hdhomerun_device_t *device = hdhomerun_device_create(HDHOMERUN_DEVICE_ID_WILDCARD,
                                                                    discoveredDevice->ip_addr,
                                                                    0, // tuner index
                                                                    NULL); // no debug info
        if (device == NULL) continue;
        
        for (UInt8 tunerIndex = 0; tunerIndex < tunerCount; tunerIndex++) {
            NSLog(@"examining tuner %hhu", tunerIndex);
            
            hdhomerun_device_set_tuner(device, tunerIndex);
            char *tunerTargetBuffer;
            int result = hdhomerun_device_get_tuner_target(device, &tunerTargetBuffer);
            
            switch (result) {
                case 0:  NSLog(@"operation rejected"); continue;
                case -1: NSLog(@"communication error"); continue;
                default: break;
            }
            
            NSLog(@"tuner %hhu target is %s", tunerIndex, tunerTargetBuffer);
            
            if (strcmp(tunerTargetBuffer, "none") == 0) {
                NSLog(@"tuner %hhu is available", tunerIndex);
                self.tunerDevice = device;
                [self lockTuner];
                return;
            } else
                NSLog(@"tuner %hhu in use, skipping", tunerIndex);
        }
        
        // no tuners free on this device, so destroy it
        NSLog(@"no tuners available on device, skipping");
        hdhomerun_device_destroy(device);
    }
    
    // no more devices to try, fail the recording
    [self abortWithErrorMessage:@"no tuners available"];
}

- (void)lockTuner
{
    // XXX set lock here
    struct hdhomerun_device_t *device = self.tunerDevice;
    
    // tune channel based off the mode
    if ([self.program.mode isEqualToString:@"digital"]) {
        NSLog(@"tuning digital broadcast");
        hdhomerun_device_set_tuner_channel(device,
                                           [[@"auto:" stringByAppendingString:self.program.rfChannel]
                                            cStringUsingEncoding:NSASCIIStringEncoding]);
    } else if ([self.program.mode isEqualToString:@"digital_cable"]) {
        NSLog(@"tuning digital cable");
        hdhomerun_device_set_tuner_vchannel(device,
                                            [self.program.rfChannel cStringUsingEncoding:NSASCIIStringEncoding]);
    } else {
        [self abortWithErrorMessage:[@"unknown mode " stringByAppendingString:self.program.mode]];
        return;
    }
    
    // open recording file
    FILE *filePointer = fopen([self.recordingFilePath fileSystemRepresentation], "wb");
    if (!filePointer) {
        [self abortWithErrorMessage:@"unable to create recording file"];
        return;
    }
    
    self.filePointer = filePointer;
    
    // take power assertion
    IOPMAssertionID assertionID;
    IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep,
                                                   kIOPMAssertionLevelOn,
                                                   (__bridge CFStringRef)self.recordingFilePath,
                                                   &assertionID);
    if (success != kIOReturnSuccess) {
        NSLog(@"unable to create power assertion");
        self.assertionID = kIOPMNullAssertionID;
    } else self.assertionID = assertionID;
    
    
    int result = hdhomerun_device_stream_start(device);
    if (result <= 0) {
        [self abortWithErrorMessage:@"unable to start stream"];
        return;
    }
    
    self.shouldStream = YES;
    [NSThread detachNewThreadSelector:@selector(receiveStream)
                             toTarget:self
                           withObject:nil];
    
    self.status = @"recording";
    self.statusIconImage = [NSImage imageNamed:@"red"];
    
    [self.scheduler beganRecording:self];
}

- (void)receiveStream
{
    NSLog(@"receiving stream");
    NSLog(@"recording %@", self.program.title);
    
    FILE *filePointer = self.filePointer;
    size_t bufferSize;
    struct hdhomerun_device_t *tunerDevice = self.tunerDevice;
    
    BOOL programIdentified = NO;
    BOOL streamReadyForSaving = NO;
    NSString *programNamePrefix = nil;
    NSString *programString = nil;
    
    if ([self.program.mode isEqualToString:@"digital"])
        programNamePrefix = [NSString stringWithFormat:@"%hu.%hu", self.program.psipMajor, self.program.psipMinor];
    
    while (self.shouldStream) {
        uint64_t loopStartTime = getcurrenttime();
        
        uint8_t *videoDataBuffer = hdhomerun_device_stream_recv(tunerDevice, VIDEO_DATA_BUFFER_SIZE_1S, &bufferSize);
        if (!videoDataBuffer) {
            msleep_approx(64);
            continue;
        }
        
        if (!programIdentified) {
            char *program;
            hdhomerun_device_get_tuner_program(tunerDevice, &program);
            
            programString = @(program);
            
            if (![programString isEqualToString:@"none"])
                programIdentified = YES;
        }
        
        if (!streamReadyForSaving) {
            char *streamInfo;
            hdhomerun_device_get_tuner_streaminfo(tunerDevice, &streamInfo);
            
            NSString *streamInfoString = @(streamInfo);
            
            NSArray *streams = [streamInfoString componentsSeparatedByString:@"\n"];
            
            for (NSString *stream in streams) {
                // for digital cable (CableCARD), look for a stream that matches the program number, and wait until it is unencrypted
                if ([self.program.mode isEqualToString:@"digital_cable"]) {
                    if ([stream hasPrefix:programString])
                        if (![stream hasSuffix:@")"]) {
                            NSLog(@"unecrypted stream found!");
                            streamReadyForSaving = YES;
                        }
                    
                    if (streamReadyForSaving)
                        break;
                }
                
                // in digital (ATSC broadcast), we match the whole program name and then set a filter
                else if ([self.program.mode isEqualToString:@"digital"]) {
                    NSArray *streamFields = [stream componentsSeparatedByString:@": "];
                    if (streamFields.count < 2) continue;
                    
                    NSString *streamProgramNumberString = streamFields[0];
                    NSString *streamName = streamFields[1];
                    NSLog(@"program: %@ name: %@", streamProgramNumberString, streamName);
                    
                    if ([streamName hasPrefix:programNamePrefix]) {
                        NSLog(@"matched desired program name %@", streamName);
                        hdhomerun_device_set_tuner_program(tunerDevice, [streamProgramNumberString cStringUsingEncoding:NSASCIIStringEncoding]);
                        streamReadyForSaving = YES;
                        break;
                    }
                }
            }
            
            continue;
        }
        
        if (streamReadyForSaving && filePointer) {
            if (fwrite(videoDataBuffer, 1, bufferSize, filePointer) != bufferSize) {
                fprintf(stderr, "error writing output\n");
                break;
            }
        }
        
        int32_t delay = 64 - (int32_t)(getcurrenttime() - loopStartTime);
        if (delay <= 0) continue;
        msleep_approx(delay);
    }
    
    [self.scheduler performSelectorOnMainThread:@selector(endedRecording:) withObject:self waitUntilDone:NO];
    NSLog(@"receiving stream thread terminated");
}

- (void)stopRecording
{
    if (self.tunerDevice) hdhomerun_device_stream_stop(self.tunerDevice);
    
    self.shouldStream = NO;
    self.completed = YES;
    
    [self cleanupRecordingResources];
    [self trashScheduleFile];
    
    self.status = @"";
    self.statusIconImage = [NSImage imageNamed:@"clapperboard"];
}

- (void)cleanupRecordingResources
{
    [self cancelTimers];

    if (self.filePointer) {
        fclose(self.filePointer);
        self.filePointer = NULL;
    }
    
    if (self.tunerDevice) {
        hdhomerun_device_destroy(self.tunerDevice);
        self.tunerDevice = NULL;
    }
    
    if (self.assertionID != kIOPMNullAssertionID) {
        IOReturn success = IOPMAssertionRelease(self.assertionID);
        if (success != kIOReturnSuccess) NSLog(@"unable to release power assertion");
        self.assertionID = kIOPMNullAssertionID;
    }
}

- (void)abortWithErrorMessage:(NSString *)errorMessage
{
    NSLog(@"aborting recording: %@", errorMessage);
    self.status = errorMessage;
    self.statusIconImage = [NSImage imageNamed:@"prohibited"];
    self.completed = YES;
    
    [self cleanupRecordingResources];
}

- (void)deleteRecording
{
    [self stopRecording];
    [self trashRecordingFile];
}

- (BOOL)currentlyRecording
{
    return self.shouldStream;
}

@end
