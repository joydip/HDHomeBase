//
//  HBRecording.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HDHRTunerReservation;

@interface HBRecording : NSObject

// persistent properties
@property (readonly) NSString *mode;
@property (readonly) NSString *title;
@property (readonly) NSString *episode;
@property (readonly) NSString *summary;
@property (readonly) NSDate *startDate;
@property (readonly) NSDate *endDate;
@property (readonly) UInt16 duration;
@property (readonly) NSString *channelName;
@property (readonly) NSString *rfChannel;
@property (readonly) NSString *streamNumber;
@property (readonly) UInt16 psipMajor;
@property (readonly) UInt16 psipMinor;

// dynamically computed properties
@property (readonly) NSString *uniqueName;
@property (readonly) NSString *recordingFilename;

// non-persistent state used by the scheduler
@property (copy) NSString *status;
@property NSImage *statusIconImage;
@property HDHRTunerReservation *tunerReservation;
@property BOOL currentlyRecording;
@property (copy) NSString *propertyListFilePath;
@property (copy) NSString *recordingFilePath;
@property NSTimer *startTimer;
@property NSTimer *stopTimer;
@property dispatch_source_t udpSource;
@property UInt16 targetPort;

+ (instancetype)recordingFromTVPIFile:(NSString *)tvpiFilePath;
+ (instancetype)recordingFromPropertyListFile:(NSString *)propertyListFilePath;

- (instancetype)initWithTVPIFile:(NSString *)tvpiFilePath;
- (instancetype)initWithPropertyListFile:(NSString *)propertyListFilePath;

- (BOOL)serializeAsPropertyListFileToPath:(NSString *)path error:(NSError **)error;

- (void)markAsScheduled;
- (void)markAsExisting;
- (void)markAsStarting;
- (void)markAsSuccess;

@end
