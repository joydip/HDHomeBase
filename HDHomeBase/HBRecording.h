//
//  HBRecording.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HDHRTunerReservation.h"


@interface HBRecording : NSObject

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
@property (copy) NSString *tvpiFilePath;
@property (copy) NSString *recordingFilePath;

// non-persistent state used by the scheduler
@property (strong) HDHRTunerReservation *tunerReservation;
@property (assign) UInt16 targetPort;
@property (strong) dispatch_source_t udpSource;
@property (assign) BOOL currentlyRecording;

+ (instancetype)recordingFromTVPIFile:(NSString *)tvpiFilePath;
- (instancetype)initWithTVPIFile:(NSString *)tvpiFilePath;

- (void)markAsScheduled;
- (void)markAsExisting;
- (void)markAsStarting;
- (void)markAsSuccess;

@end
