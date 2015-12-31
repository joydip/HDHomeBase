//
//  HBScheduler.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HBRecording;

@interface HBScheduler : NSObject

@property (readonly) NSMutableArray *scheduledRecordings;
@property (readonly) NSArray *recordingFolders;
@property (readonly) NSUInteger totalTunerCount;
@property (readonly) NSUInteger maxAcceptableOverlappingRecordingsCount;

- (void)importTVPIFile:(NSString *)tvpiFilePath;
- (void)importPropertyListFile:(NSString *)propertyListFilePath;
- (void)scanRecordingFolders;

- (void)stopRecording:(HBRecording *)recording;
- (void)playRecording:(HBRecording *)recording;
- (void)deleteRecording:(HBRecording *)recording;

- (void)calculateSchedulingConflicts;

- (void)recordingStarted:(HBRecording *)recording;
- (void)recordingCompleted:(HBRecording *)recording;

@end
