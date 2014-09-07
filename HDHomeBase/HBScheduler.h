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
@property (readonly) NSString *recordingsFolder;

- (void)importTVPIFile:(NSString *)tvpiFilePath;
- (void)importPropertyListFile:(NSString *)propertyListFilePath;
- (void)importExistingRecordings;

- (void)scheduleRecording:(HBRecording *)recording;
- (void)startRecording:(HBRecording *)recording;
- (void)stopRecording:(HBRecording *)recording;
- (void)playRecording:(HBRecording *)recording;
- (void)deleteRecording:(HBRecording *)recording;

@end
