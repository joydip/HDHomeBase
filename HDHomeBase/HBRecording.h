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

@property (weak) HBScheduler *scheduler;
@property HBProgram *program;
@property BOOL completed;
@property (readonly, copy) NSImage *statusIconImage;
@property (readonly, copy) NSString *status;
@property NSMutableSet *overlappingRecordings;
@property BOOL tooManyOverlappingRecordings;
@property (copy) NSString *propertyListFilePath;
@property (copy) NSString *recordingFilePath;

// dynamically computed properties
@property (readonly) NSString *recordingFilename;
@property (readonly) NSString *uniqueName;
@property (readonly) BOOL recordingFileExists;
@property (readonly) BOOL currentlyRecording;

- (BOOL)startOverlapsWithRecording:(HBRecording *)otherRecording;
- (BOOL)hasEndDatePassed;

- (void)scheduleRecording;
- (void)stopRecording;
- (void)deleteRecording;

- (void)trashRecordingFile;
- (void)trashScheduleFile;

@end
