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

- (NSUInteger)totalTunerCount
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"TotalTunerCount"];
}

- (NSUInteger)maxAcceptableOverlappingRecordingsCount
{
    return self.totalTunerCount-1;
}

- (NSString *)recordingsFolder
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"RecordingsFolder"];
}

- (void)importExistingSchedules
{
    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    NSArray *recordingsFolderContents = [defaultFileManager contentsOfDirectoryAtPath:self.recordingsFolder error:NULL];
    
    for (NSString *file in recordingsFolderContents)
        if ([file hasSuffix:@".hbsched"]) [self importPropertyListFile:[self.recordingsFolder stringByAppendingPathComponent:file]];
}

- (void)importTVPIFile:(NSString *)tvpiFilePath
{
    HBRecording *recording = [HBRecording recordingFromTVPIFile:tvpiFilePath];

    [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:tvpiFilePath]
                                  resultingItemURL:NULL
                                             error:NULL];

    if (![recording hasEndDatePassed]) {
        NSString *newPropertyListFilename = [recording.uniqueName stringByAppendingString:@".hbsched"];
        NSString *newPropertyListPath = [self.recordingsFolder stringByAppendingPathComponent:newPropertyListFilename];
        
        [recording serializeAsPropertyListFileToPath:newPropertyListPath error:NULL];
        recording.propertyListFilePath = newPropertyListPath;

        [self scheduleRecording:recording];
    }
}

- (void)importPropertyListFile:(NSString *)propertyListFilePath
{
    HBRecording *recording = [HBRecording recordingFromPropertyListFile:propertyListFilePath];

    if ([recording hasEndDatePassed]) {
        [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:propertyListFilePath]
                                      resultingItemURL:NULL
                                                 error:NULL];
        return;
    }
    
    recording.propertyListFilePath = propertyListFilePath;
    [self scheduleRecording:recording];
}

- (void)scheduleRecording:(HBRecording *)recording
{
    recording.recordingFilePath = [[self recordingsFolder] stringByAppendingPathComponent:recording.recordingFilename];
    recording.recordingFileExists = [[NSFileManager defaultManager] fileExistsAtPath:recording.recordingFilePath];

    // only schedule the timers if the file doesn't exist
    if (!recording.recordingFileExists) {
        NSTimeInterval beginningPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"BeginningPadding"];
        NSDate *paddedStartDate = [recording.startDate dateByAddingTimeInterval:-beginningPadding];
        recording.paddedStartDate = paddedStartDate;
        recording.startTimer = [[NSTimer alloc] initWithFireDate:paddedStartDate
                                                        interval:0
                                                          target:self
                                                        selector:@selector(startRecordingTimerFired:)
                                                        userInfo:recording
                                                         repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:recording.startTimer
                                  forMode:NSRunLoopCommonModes];
        
        NSTimeInterval endingPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"EndingPadding"];
        NSDate *paddedEndDate = [recording.endDate dateByAddingTimeInterval:endingPadding];
        recording.paddedEndDate = paddedEndDate;
        recording.stopTimer = [[NSTimer alloc] initWithFireDate:paddedEndDate
                                                       interval:0
                                                         target:self
                                                       selector:@selector(stopRecordingTimerFired:)
                                                       userInfo:recording
                                                        repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:recording.stopTimer
                                  forMode:NSRunLoopCommonModes];
    } else {
        recording.statusIconImage = [NSImage imageNamed:@"clapperboard"];
        recording.completed = YES;
        [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:recording.propertyListFilePath]
                                      resultingItemURL:NULL
                                                 error:NULL];
    }
    
    [self.scheduledRecordings addObject:recording];
    [self calculateSchedulingConflicts];
}

- (void)calculateSchedulingConflicts
{
    for (HBRecording *recording in self.scheduledRecordings)
        recording.overlappingRecordings = nil;

    NSArray *sortedScheduledRecordings = [self.scheduledRecordings sortedArrayUsingComparator:^(HBRecording *q, HBRecording *r) {
        return [q.startDate compare:r.startDate];
    }];
    
    for (NSUInteger i = 0; i < sortedScheduledRecordings.count; i++) {
        HBRecording *recording = sortedScheduledRecordings[i];
        if (recording.completed) continue;
        
        for (NSUInteger j = i+1; j < sortedScheduledRecordings.count; j++) {
            HBRecording *otherRecording = sortedScheduledRecordings[j];
            if (otherRecording.completed) continue;
            
            if ([otherRecording startOverlapsWithRecording:recording]) {
                if (!otherRecording.overlappingRecordings) otherRecording.overlappingRecordings = [NSMutableSet new];
                [otherRecording.overlappingRecordings addObject:recording];
            } else break;
        }
    }

    for (HBRecording *recording in self.scheduledRecordings) {
        if (recording.currentlyRecording || recording.completed) continue;

        BOOL tooManyOverlappingRecordings = (recording.overlappingRecordings.count > self.maxAcceptableOverlappingRecordingsCount);
        recording.tooManyOverlappingRecordings = tooManyOverlappingRecordings;
        recording.statusIconImage = [NSImage imageNamed:(tooManyOverlappingRecordings ? @"schedule_alert" : @"scheduled")];
    }
}

- (void)abortRecording:(HBRecording *)recording errorMessage:(NSString *)errorMessage
{
    NSLog(@"aborting recording: %@", errorMessage);
    recording.status = errorMessage;
    recording.statusIconImage = [NSImage imageNamed:@"prohibited"];
    [self cancelTimersForRecording:recording];

    if (recording.tunerDevice) {
        hdhomerun_device_destroy(recording.tunerDevice);
        recording.tunerDevice = NULL;
    }
    
    if (recording.assertionID != kIOPMNullAssertionID) {
        IOReturn success = IOPMAssertionRelease(recording.assertionID);
        
        if (success != kIOReturnSuccess)
            NSLog(@"unable to release power assertion");
    }
}

- (void)startRecording:(HBRecording *)recording
{
    recording.statusIconImage = [NSImage imageNamed:@"yellow"];
    recording.status = @"searching for devices…";

    UInt8 maxDeviceCount = 8;
    struct hdhomerun_discover_device_t deviceList[maxDeviceCount];
    int devicesFoundCount = hdhomerun_discover_find_devices_custom(0, // auto-detect IP address
                                                                   HDHOMERUN_DEVICE_TYPE_TUNER,
                                                                   HDHOMERUN_DEVICE_ID_WILDCARD,
                                                                   deviceList,
                                                                   maxDeviceCount);
    if (devicesFoundCount == -1) {
        [self abortRecording:recording errorMessage:@"unable to discover devices"];
        return;
    }

    if (devicesFoundCount == 0) {
        [self abortRecording:recording errorMessage:@"no devices found"];
        return;
    }
    
    recording.status = @"searching for available tuner…";

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
                recording.tunerDevice = device;
                [self lockTunerAndPrepareRecording:recording];
                return;
            } else
                NSLog(@"tuner %hhu in use, skipping", tunerIndex);
        }
        
        // no tuners free on this device, so destroy it
        NSLog(@"no tuners available on device, skipping");
        hdhomerun_device_destroy(device);
    }
    
    // no more devices to try, fail the recording
    [self abortRecording:recording errorMessage:@"no tuners available"];
}

- (void)lockTunerAndPrepareRecording:(HBRecording *)recording
{
    // XXX set lock here
    struct hdhomerun_device_t *device = recording.tunerDevice;

    // tune channel based off the mode
    if ([recording.mode isEqualToString:@"digital"]) {
        NSLog(@"tuning digital broadcast");
        hdhomerun_device_set_tuner_channel(device,
                                           [[@"auto:" stringByAppendingString:recording.rfChannel]
                                            cStringUsingEncoding:NSASCIIStringEncoding]);
    } else if ([recording.mode isEqualToString:@"digital_cable"]) {
        NSLog(@"tuning digital cable");
        hdhomerun_device_set_tuner_vchannel(device,
                                            [recording.rfChannel cStringUsingEncoding:NSASCIIStringEncoding]);
    } else {
        [self abortRecording:recording errorMessage:[@"unknown mode " stringByAppendingString:recording.mode]];
        return;
    }
    
    // open recording file
    FILE *filePointer = fopen([recording.recordingFilePath fileSystemRepresentation], "wb");
    if (!filePointer) {
        [self abortRecording:recording errorMessage:@"unable to create recording file"];
        return;
    }
    
    recording.filePointer = filePointer;
    recording.recordingFileExists = YES;
    
    // take power assertion
    IOPMAssertionID assertionID;
    IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep,
                                                   kIOPMAssertionLevelOn,
                                                   (__bridge CFStringRef)recording.recordingFilePath,
                                                   &assertionID);
    if (success != kIOReturnSuccess) {
        NSLog(@"unable to create power assertion");
        recording.assertionID = kIOPMNullAssertionID;
    } else recording.assertionID = assertionID;
    
    
    int result = hdhomerun_device_stream_start(device);
    if (result <= 0) {
        [self abortRecording:recording errorMessage:@"unable to start stream"];
        return;
    }
    
    recording.currentlyRecording = YES;
    [NSThread detachNewThreadSelector:@selector(receiveStreamForRecording:)
                             toTarget:self
                           withObject:recording];

    recording.status = @"recording";
    recording.statusIconImage = [NSImage imageNamed:@"red"];
    self.activeRecordingCount += 1;
    [self updateDockTile];
    return;
}

- (void)receiveStreamForRecording:(HBRecording *)recording
{
    NSLog(@"receiving stream");
    NSLog(@"recording %@", recording.title);

    FILE *filePointer = recording.filePointer;
    size_t bufferSize;
    struct hdhomerun_device_t *tuner_device = recording.tunerDevice;
    
    BOOL streamReadyForSaving = NO;
    NSString *programNamePrefix = nil;
   
    if ([recording.mode isEqualToString:@"digital"])
        programNamePrefix = [NSString stringWithFormat:@"%hu.%hu", recording.psipMajor, recording.psipMinor];
    
	while (recording.currentlyRecording) {
		uint64_t loop_start_time = getcurrenttime();
        
		uint8_t *ptr = hdhomerun_device_stream_recv(tuner_device, VIDEO_DATA_BUFFER_SIZE_1S, &bufferSize);
		if (!ptr) {
			msleep_approx(64);
			continue;
		}

        /*
         NSString *programNumber = nil;
         char *program;
         hdhomerun_device_get_tuner_program(tuner_device, &program);
         programNumber = @(program);
        */
        
        if (!streamReadyForSaving) {
            char *streamInfo;
            hdhomerun_device_get_tuner_streaminfo(tuner_device, &streamInfo);

            NSString *streamInfoString = @(streamInfo);

            NSArray *streams = [streamInfoString componentsSeparatedByString:@"\n"];

            for (NSString *stream in streams) {
                NSArray *streamFields = [stream componentsSeparatedByString:@": "];
                if (streamFields.count < 2) continue;
                
                NSString *streamProgramNumberString = streamFields[0];
                NSString *streamName = streamFields[1];
                NSLog(@"program: %@ name: %@", streamProgramNumberString, streamName);
                
                if ([streamName hasPrefix:programNamePrefix]) {
                    NSLog(@"matched desired program name %@", streamName);
                    hdhomerun_device_set_tuner_program(tuner_device, [streamProgramNumberString cStringUsingEncoding:NSASCIIStringEncoding]);
                    streamReadyForSaving = YES;
                    break;
                }
            }
            
            continue;
        }
        
		if (streamReadyForSaving && filePointer) {
			if (fwrite(ptr, 1, bufferSize, filePointer) != bufferSize) {
				fprintf(stderr, "error writing output\n");
				break;
			}
		}
        
		int32_t delay = 64 - (int32_t)(getcurrenttime() - loop_start_time);
		if (delay <= 0) continue;
		msleep_approx(delay);
	}
    
    NSLog(@"stopping receiving stream");
}

- (void)stopRecording:(HBRecording *)recording
{
    recording.currentlyRecording = NO;
    recording.completed = YES;

	if (recording.filePointer) fclose(recording.filePointer);
    recording.filePointer = NULL;
    
	hdhomerun_device_stream_stop(recording.tunerDevice);
    IOPMAssertionRelease(recording.assertionID);
    
    hdhomerun_device_destroy(recording.tunerDevice);

    [self cancelTimersForRecording:recording];

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
    [self calculateSchedulingConflicts];
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
