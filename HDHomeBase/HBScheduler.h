//
//  HBScheduler.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HBProgram;

@interface HBScheduler : NSObject

@property (readonly) NSMutableArray *scheduledRecordings;
@property (readonly) NSString *recordingsFolder;
@property (readonly) NSUInteger totalTunerCount;
@property (readonly) NSUInteger maxAcceptableOverlappingRecordingsCount;


- (void)importTVPIFile:(NSString *)tvpiFilePath;
- (void)importPropertyListFile:(NSString *)propertyListFilePath;
- (void)importExistingSchedules;

- (void)scheduleRecording:(HBProgram *)recording;
- (void)startRecording:(HBProgram *)recording;
- (void)stopRecording:(HBProgram *)recording;
- (void)playRecording:(HBProgram *)recording;
- (void)deleteRecording:(HBProgram *)recording;

- (void)calculateSchedulingConflicts;

@end
