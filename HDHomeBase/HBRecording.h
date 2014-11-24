//
//  HBRecording.h
//  HDHomeBase
//
//  Created by Joydip Basu on 11/22/14.
//  Copyright (c) 2014 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

@class HBProgram;
@class HBScheduler;

@interface HBRecording : NSObject

@property (readonly, weak) HBScheduler *scheduler;
@property (readonly) HBProgram *program;

@property (readonly) NSString *recordingFilePath;
@property (readonly) BOOL recordingFileExists;
@property (readonly) BOOL currentlyRecording;
@property (readonly) BOOL completed;
@property (readonly) BOOL hasEndDatePassed;

@property (readonly, copy) NSString *status;
@property (copy) NSImage *statusIconImage;

@property NSMutableSet *overlappingRecordings;
@property BOOL tooManyOverlappingRecordings;

+ (instancetype)recordingWithProgram:(HBProgram *)program
                   recordingFilePath:(NSString *)recordingFilePath
                           scheduler:(HBScheduler *)scheduler;

- (instancetype)initWithProgram:(HBProgram *)program
              recordingFilePath:(NSString *)recordingFilePath
                      scheduler:(HBScheduler *)scheduler;

- (void)scheduleTimers;
- (void)stop;

- (BOOL)startDateOverlapsWithRecording:(HBRecording *)otherRecording;

@end
