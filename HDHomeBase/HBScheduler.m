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
@property NSMutableArray *previousRecordingFilenames;

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

- (NSArray *)recordingFolders
{
    return [[NSUserDefaults standardUserDefaults] arrayForKey:@"RecordingFolders"];
}

+ (NSString *)replaceForwardSlashes:(NSString *)string
{
    return [string stringByReplacingOccurrencesOfString:@"/" withString:@"--"];
}

+ (NSString *)baseNameForProgram:(HBProgram *)program
{
    NSString *title = [self replaceForwardSlashes:program.title];
    return (program.episode.length == 0) ? title
                                         : [NSString stringWithFormat:@"%@ - %@", title, [self replaceForwardSlashes:program.episode]];
}

+ (NSString *)uniqueNameForProgram:(HBProgram *)program
{
    NSString *recordingFileDateString = [[self recordingFileDateFormatter] stringFromDate:program.startDate];
    NSString *baseName = [self baseNameForProgram:program];
    return [NSString stringWithFormat:@"%@ (%@ %@)", baseName, program.channelName, recordingFileDateString];
}

+ (NSString *)recordingFilenameForProgram:(HBProgram *)program
{
    return [[self uniqueNameForProgram:program] stringByAppendingPathExtension:@"ts"];
}

- (NSString *)recordingFilePathForProgram:(HBProgram *)program
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString *recordingFilename = [[self class] recordingFilenameForProgram:program];

    NSString *title = [[self class] replaceForwardSlashes:program.title];
    
    for (NSString *recordingFolder in self.recordingFolders) {
        NSString *programRecordingFolder = [recordingFolder stringByAppendingPathComponent:title];
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:programRecordingFolder isDirectory:&isDirectory] && isDirectory)
            return [programRecordingFolder stringByAppendingPathComponent:recordingFilename];
    }
    
    return [self.recordingFolders[0] stringByAppendingPathComponent:recordingFilename];
}

+ (NSString *)scheduleFilenameForProgram:(HBProgram *)program
{
    return [[self uniqueNameForProgram:program] stringByAppendingPathExtension:@"hbsched"];
}

+ (NSString *)scheduleFilePathFromRecordingPath:(NSString *)recordingPath
{
    return [[recordingPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"hbsched"];
}

- (void)scanRecordingFolders
{
    NSMutableArray *existingScheduleFiles = [NSMutableArray new];
    NSMutableArray *previousRecordingsFiles = [NSMutableArray new];
    
    for (NSString *recordingFolder in self.recordingFolders) {
        NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:recordingFolder];
        
        NSString *file;
        while ((file = [dirEnumerator nextObject])) {
            if ([file hasSuffix:@".hbsched"]) [existingScheduleFiles addObject:[recordingFolder stringByAppendingPathComponent:file]];
            if ([file hasSuffix:@".hbprev"]) [previousRecordingsFiles addObject:[recordingFolder stringByAppendingPathComponent:file]];
        }
    }
    
    for (NSString *previousRecordingFile in previousRecordingsFiles) {
        NSString *previousRecordingsText = [NSString stringWithContentsOfURL:[NSURL fileURLWithPath:previousRecordingFile]
                                                                    encoding:NSUTF8StringEncoding
                                                                       error:NULL];
        NSCharacterSet *newlineCharacterSet = [NSCharacterSet newlineCharacterSet];
        if (self.previousRecordingFilenames == nil) self.previousRecordingFilenames = [NSMutableArray new];
        [self.previousRecordingFilenames addObjectsFromArray:[previousRecordingsText componentsSeparatedByCharactersInSet:newlineCharacterSet]];
    }
    
    for (NSString *existingScheduleFile in existingScheduleFiles)
        [self importPropertyListFile:existingScheduleFile];
}

- (BOOL)importTVPIFile:(NSString *)tvpiFilePath
{
    HBProgram *program = [HBProgram programFromTVPIFile:tvpiFilePath];
    NSString *recordingFilePath = [self recordingFilePathForProgram:program];
    HBRecording *recording = [HBRecording recordingWithProgram:program
                                             recordingFilePath:recordingFilePath
                                                     scheduler:self];
    
    [[self class] trashFileAtPath:tvpiFilePath];

    if (![recording hasEndDatePassed] && ![self recordingAlreadyScheduled:recording]) {
        NSString *newPropertyListPath = [[self class] scheduleFilePathFromRecordingPath:recordingFilePath];
        [program serializeAsPropertyListFileToPath:newPropertyListPath error:NULL];
        [self scheduleRecording:recording];
    }
    
    return YES; // XXX blindly returning YES
}

- (void)importPropertyListFile:(NSString *)propertyListFilePath
{
    HBProgram *program = [HBProgram programFromPropertyListFile:propertyListFilePath];
    NSString *recordingFilePath = [[propertyListFilePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"ts"];;
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
    NSURL *url = [NSURL fileURLWithPath:path];
    if (NSAppKitVersionNumber < NSAppKitVersionNumber10_8) [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    else [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:NULL error:NULL];
}

- (void)trashRecordingFile:(HBRecording *)recording
{
    [[self class] trashFileAtPath:recording.recordingFilePath];
}

- (void)trashScheduleFile:(HBRecording *)recording
{
    [[self class] trashFileAtPath:[[self class] scheduleFilePathFromRecordingPath:recording.recordingFilePath]];
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
    
    for (NSString *recordingFolder in self.recordingFolders) {
        NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:recordingFolder];

        NSString *file;
        while ((file = [[dirEnumerator nextObject] lastPathComponent])) {
            if ([file hasSuffix:@".ts"] && [file hasPrefix:prefix]) {
                recording.status = @"recording with same title exists";
                return;
            }
        }

        for (NSString *previousRecordingFilename in self.previousRecordingFilenames) {
            if ([previousRecordingFilename hasPrefix:prefix]) {
                recording.status = @"recording with same title was previously recorded";
                break;
            }
        }
    }
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
    [self trashScheduleFile:recording];
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
    [self trashScheduleFile:recording];
}

- (void)updateDockTile
{
    NSDockTile *dockTile = [NSApp dockTile];
    dockTile.badgeLabel = (self.activeRecordingCount) ? [NSString stringWithFormat:@"%lu", (unsigned long)self.activeRecordingCount] : nil;
}

@end
