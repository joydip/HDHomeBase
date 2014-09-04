//
//  HBRecording.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HDHRDeviceManager;

@interface HBRecording : NSObject

@property (strong) HDHRDeviceManager *deviceManager;


@property (copy) NSString *mode;
@property (copy) NSString *title;
@property (copy) NSString *episode;
@property (copy) NSString *summary;
@property (copy) NSDate *startDate;
@property (copy) NSDate *endDate;
@property (assign) UInt16 duration;
@property (copy) NSString *channelName;
@property (copy) NSString *rfChannel;
@property (copy) NSString *streamNumber;
@property (assign) UInt16 psipMajor;
@property (assign) UInt16 psipMinor;
@property (copy) NSString *status;
@property (copy) NSImage *statusIconImage;
@property (assign) BOOL currentlyRecording;

@property (copy) NSString *tvpiFilePath;
@property (copy) NSString *recordingPath;

- (void)startRecording:(id)sender;
- (void)stopRecording:(id)sender;

@end
