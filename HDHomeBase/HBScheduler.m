//
//  HBScheduler.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBScheduler.h"
#import "HBRecording.h"
#import "HBProgram.h"

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
    HBProgram *program = [HBProgram programFromTVPIFile:tvpiFilePath];
    
    HBRecording *recording = [HBRecording new];
    recording.program = program;
    recording.scheduler = self;

    [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:tvpiFilePath]
                                  resultingItemURL:NULL
                                             error:NULL];

    if (![recording hasEndDatePassed] && ![self recordingAlreadyScheduled:recording]) {
        NSString *newPropertyListFilename = [recording.uniqueName stringByAppendingString:@".hbsched"];
        NSString *newPropertyListPath = [self.recordingsFolder stringByAppendingPathComponent:newPropertyListFilename];
        
        [program serializeAsPropertyListFileToPath:newPropertyListPath error:NULL];
        recording.propertyListFilePath = newPropertyListPath;

        [self scheduleRecording:recording];
    }
}

- (void)importPropertyListFile:(NSString *)propertyListFilePath
{
    HBProgram *program = [HBProgram programFromPropertyListFile:propertyListFilePath];
    HBRecording *recording = [HBRecording new];
    recording.scheduler = self;
    recording.program = program;
    recording.propertyListFilePath = propertyListFilePath;

    if ([recording hasEndDatePassed]) {
        [recording trashScheduleFile];
        return;
    }
    
    [self scheduleRecording:recording];
}

- (BOOL)recordingAlreadyScheduled:(HBRecording *)recording
{
    for (HBRecording *existingRecording in self.scheduledRecordings) {
        if (([recording.program.startDate isEqualToDate:existingRecording.program.startDate]) &&
            ([recording.program.endDate isEqualToDate:existingRecording.program.endDate]) &&
            ([recording.program.rfChannel isEqualToString:existingRecording.program.rfChannel] &&
             (recording.program.psipMinor == existingRecording.program.psipMinor))) {
            NSLog(@"recording already exists, not adding");
            return YES;
        }
    }
    
    return NO;
}

- (void)scheduleRecording:(HBRecording *)recording
{
    recording.recordingFilePath = [[self recordingsFolder] stringByAppendingPathComponent:recording.recordingFilename];

    [recording scheduleRecording];
    
    [self.scheduledRecordings addObject:recording];
    [self calculateSchedulingConflicts];
}

- (void)calculateSchedulingConflicts
{
    for (HBRecording *recording in self.scheduledRecordings)
        recording.overlappingRecordings = nil;

    NSArray *sortedScheduledRecordings = [self.scheduledRecordings sortedArrayUsingComparator:^(HBRecording *q, HBRecording *r) {
        return [q.program.startDate compare:r.program.startDate];
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

- (void)stopRecording:(HBRecording *)recording
{
    [recording stopRecording];
}

- (void)playRecording:(HBRecording *)recording
{
    [[NSWorkspace sharedWorkspace] openFile:recording.recordingFilePath];
}

- (void)deleteRecording:(HBRecording *)recording
{
    [recording deleteRecording];

    [self.scheduledRecordings removeObject:recording];
    [self calculateSchedulingConflicts];
}

- (void)beganRecording:(HBRecording *)recording
{
    self.activeRecordingCount += 1;
    [self updateDockTile];
}

- (void)endedRecording:(HBRecording *)recording
{
    self.activeRecordingCount -= 1;
    [self updateDockTile];
}

- (void)updateDockTile
{
    NSDockTile *dockTile = [NSApp dockTile];
    dockTile.badgeLabel = (self.activeRecordingCount) ? [NSString stringWithFormat:@"%lu", (unsigned long)self.activeRecordingCount] : nil;
}

@end
