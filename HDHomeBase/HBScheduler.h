//
//  HBScheduler.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HBRecording;
@class HDHRDeviceManager;

@interface HBScheduler : NSObject

@property (strong) IBOutlet HDHRDeviceManager *deviceManager;
@property (strong) NSMutableArray *scheduledRecordings;

- (void)importTVPIFile:(NSString *)tvpiFilePath;

- (void)startRecording:(HBRecording *)recording;
- (void)stopRecording:(HBRecording *)recording;

@end
