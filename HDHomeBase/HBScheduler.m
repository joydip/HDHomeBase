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
    }
    
    [self.scheduledRecordings addObject:recording];
    [self searchForSchedulingConflicts];
}

- (void)searchForSchedulingConflicts
{
    for (HBRecording *recording in self.scheduledRecordings)
        recording.overlappingRecordings = nil;

    NSArray *sortedScheduledRecordings = [self.scheduledRecordings sortedArrayUsingComparator:^(HBRecording *q, HBRecording *r) {
        return [q.startDate compare:r.startDate];
    }];
    
    for (NSUInteger i = 0; i < sortedScheduledRecordings.count; i++) {
        HBRecording *recording = sortedScheduledRecordings[i];
        
        for (NSUInteger j = i+1; j < sortedScheduledRecordings.count; j++) {
            HBRecording *otherRecording = sortedScheduledRecordings[j];
            
            if ([otherRecording startOverlapsWithRecording:recording]) {
                if (!otherRecording.overlappingRecordings) otherRecording.overlappingRecordings = [NSMutableSet new];
                [otherRecording.overlappingRecordings addObject:recording];
            } else break;
        }
    }

    for (HBRecording *recording in self.scheduledRecordings) {
        BOOL tooManyOverlappingRecordings = (recording.overlappingRecordings.count > self.maxAcceptableOverlappingRecordingsCount);
        recording.tooManyOverlappingRecordings = tooManyOverlappingRecordings;
        if (!recording.currentlyRecording)
            recording.statusIconImage = [NSImage imageNamed:(tooManyOverlappingRecordings ? @"schedule_alert" : @"scheduled")];
    }
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

- (int)receiveStreamForRecording:(HBRecording *)recording
{
    IOPMAssertionID assertionID;
    IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep,
                                                   kIOPMAssertionLevelOn,
                                                   (__bridge CFStringRef)recording.recordingFilePath,
                                                   &assertionID);
    
    if (success != kIOReturnSuccess)
        NSLog(@"unable to create power assertion");

    size_t buffer_size;
    struct hdhomerun_device_t *tuner_device = recording.tunerDevice;
    
	FILE *fp;
    fp = fopen([recording.recordingFilePath fileSystemRepresentation], "wb");
    if (!fp) {
        fprintf(stderr, "unable to create file\n");
        return -1;
    }
    
    recording.recordingFileExists = YES;
    
	int ret = hdhomerun_device_stream_start(tuner_device);
    
    
    

	if (ret <= 0) {
		fprintf(stderr, "unable to start stream\n");
		if (fp && fp != stdout) {
			fclose(fp);
		}
		return ret;
	}

    BOOL streamReady = NO;
    BOOL programIdentified = NO;
    NSString *programString = nil;
	while (recording.currentlyRecording) {
		uint64_t loop_start_time = getcurrenttime();
        
		uint8_t *ptr = hdhomerun_device_stream_recv(tuner_device, VIDEO_DATA_BUFFER_SIZE_1S, &buffer_size);
		if (!ptr) {
			msleep_approx(64);
			continue;
		}

        if (!programIdentified) {
            char *program;
            hdhomerun_device_get_tuner_program(tuner_device, &program);
            
            programString = @(program);
            
            if (![programString isEqualToString:@"none"]) {
                programIdentified = YES;
            }
        }

        if (programIdentified && !streamReady) {
            char *streamInfo;
            hdhomerun_device_get_tuner_streaminfo(tuner_device, &streamInfo);

            NSString *streamInfoString = @(streamInfo);

            NSArray *streams = [streamInfoString componentsSeparatedByString:@"\n"];
            for (NSString *streamInfo in streams) {
                NSLog(@"%@", streamInfoString);

                if ([streamInfo hasPrefix:programString])
                    if (![streamInfo hasSuffix:@")"]) {
                        NSLog(@"streamReady!");
                        streamReady = YES;
                    }
                
                if (streamReady)
                    break;
            }
            
            continue;
        }
        

        
        
		if (programIdentified && streamReady && fp) {
			if (fwrite(ptr, 1, buffer_size, fp) != buffer_size) {
				fprintf(stderr, "error writing output\n");
				return -1;
			}
		}
        
		int32_t delay = 64 - (int32_t)(getcurrenttime() - loop_start_time);
		if (delay <= 0) {
			continue;
		}
        
		msleep_approx(delay);
	}
    
	if (fp) fclose(fp);
    
	hdhomerun_device_stream_stop(tuner_device);
    success = IOPMAssertionRelease(assertionID);
    
    hdhomerun_device_destroy(tuner_device);
    return 0;
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
    [self searchForSchedulingConflicts];
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
