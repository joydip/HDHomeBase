//
//  HBRecording.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HDHRDeviceManager.h"
#import "HDHRDevice.h"

@class HBScheduler;


@interface HBRecording : NSObject

@property (nonatomic, assign) NSUInteger paddingOptionsIndex;
@property (nonatomic, strong) HBScheduler *scheduler;
@property (nonatomic, strong) HDHRDeviceManager *deviceManager;

@property (atomic, strong) HDHRDevice *device;
@property (atomic, assign) UInt8 tunerIndex;
@property (nonatomic, assign) UInt16 targetPort;

@property (nonatomic, strong) NSArray *paddingOptions;

@property (nonatomic, strong) dispatch_source_t udpSource;
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *episode;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSDate *startDate;
@property (nonatomic, copy) NSDate *endDate;
@property (nonatomic, assign) UInt16 duration;
@property (nonatomic, copy) NSString *channelName;
@property (nonatomic, copy) NSString *rfChannel;
@property (nonatomic, copy) NSString *streamNumber;
@property (nonatomic, assign) UInt16 psipMajor;
@property (nonatomic, assign) UInt16 psipMinor;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSImage *statusIconImage;

@end
