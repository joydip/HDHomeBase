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

+ (NSString *)baseNameForProgram:(HBProgram *)program
{
    return (program.episode.length) ? [NSString stringWithFormat:@"%@ - %@", program.title, program.episode] : program.title;
}

+ (NSString *)uniqueNameForProgram:(HBProgram *)program
{
    NSString *recordingFileDateString = [[self recordingFileDateFormatter] stringFromDate:program.startDate];
    NSString *baseName = [self baseNameForProgram:program];
    return [NSString stringWithFormat:@"%@ (%@ %@)", baseName, program.channelName, recordingFileDateString];
}

+ (NSString *)recordingFilenameForProgram:(HBProgram *)program
{
    return [[self uniqueNameForProgram:program] stringByAppendingString:@".ts"];
}

- (NSString *)recordingFilePathForProgram:(HBProgram *)program
{
    return [[self recordingsFolder] stringByAppendingPathComponent:[[self class] recordingFilenameForProgram:program]];
}

+ (NSString *)scheduleFilenameForProgram:(HBProgram *)program
{
    return [[self uniqueNameForProgram:program] stringByAppendingString:@".hbsched"];
}

- (NSString *)scheduleFilePathForProgram:(HBProgram *)program
{
    return [[self recordingsFolder] stringByAppendingPathComponent:[[self class] scheduleFilenameForProgram:program]];
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
    NSString *recordingFilePath = [self recordingFilePathForProgram:program];
    HBRecording *recording = [HBRecording recordingWithProgram:program
                                             recordingFilePath:recordingFilePath
                                                     scheduler:self];
    
    [[self class] trashFileAtPath:tvpiFilePath];

    if (![recording hasEndDatePassed] && ![self recordingAlreadyScheduled:recording]) {
        NSString *newPropertyListPath = [self scheduleFilePathForProgram:program];
        [program serializeAsPropertyListFileToPath:newPropertyListPath error:NULL];
        [self scheduleRecording:recording];
    }
}

- (void)importPropertyListFile:(NSString *)propertyListFilePath
{
    HBProgram *program = [HBProgram programFromPropertyListFile:propertyListFilePath];
    NSString *recordingFilePath = [self recordingFilePathForProgram:program];
    HBRecording *recording = [HBRecording recordingWithProgram:program
                                             recordingFilePath:recordingFilePath
                                                     scheduler:self];

    if ([recording hasEndDatePassed]) {
        [[self class] trashFileAtPath:propertyListFilePath];
        return;
    }
    
    if (![self recordingAlreadyScheduled:recording])
        [self scheduleRecording:recording];
}

+ (void)trashFileAtPath:(NSString *)path
{
    [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:NULL error:NULL];
}

- (void)trashRecordingFile:(HBRecording *)recording
{
    [[self class] trashFileAtPath:recording.recordingFilePath];
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
    [recording scheduleTimers];
    
    [self.scheduledRecordings addObject:recording];
    [self checkIfRecordingAlreadyRecorded:recording];
    [self calculateSchedulingConflicts];
}

- (void)checkIfRecordingAlreadyRecorded:(HBRecording *)recording
{
    NSString *prefix = [[[self class] baseNameForProgram:recording.program] stringByAppendingString:@" ("];
    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    NSArray *recordingsFolderContents = [defaultFileManager contentsOfDirectoryAtPath:self.recordingsFolder error:NULL];
    
    for (NSString *file in recordingsFolderContents)
        if ([file hasSuffix:@".ts"] && [file hasPrefix:prefix])
            recording.status = @"recording with same title exists";
}

- (void)calculateSchedulingConflicts
{
    for (HBRecording *recording in self.scheduledRecordings) recording.overlappingRecordings = nil;

    NSArray *sortedScheduledRecordings = [self.scheduledRecordings sortedArrayUsingComparator:^(HBRecording *q, HBRecording *r) {
        return [q.program.startDate compare:r.program.startDate];
    }];
    
    for (NSUInteger i = 0; i < sortedScheduledRecordings.count; i++) {
        HBRecording *recording = sortedScheduledRecordings[i];
        if (recording.completed) continue;
        
        for (NSUInteger j = i+1; j < sortedScheduledRecordings.count; j++) {
            HBRecording *otherRecording = sortedScheduledRecordings[j];
            if (otherRecording.completed) continue;
            
            if ([otherRecording startDateOverlapsWithRecording:recording]) {
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
    [recording stop];
    [self calculateSchedulingConflicts];
}

- (void)playRecording:(HBRecording *)recording
{
    [[NSWorkspace sharedWorkspace] openFile:recording.recordingFilePath];
}

- (void)deleteRecording:(HBRecording *)recording
{
    [recording stop];
    [self.scheduledRecordings removeObject:recording];
    [self calculateSchedulingConflicts];
    [self trashRecordingFile:recording];
}

- (void)recordingStarted:(HBRecording *)recording
{
    self.activeRecordingCount += 1;
    [self updateDockTile];
}

- (void)recordingCompleted:(HBRecording *)recording
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
