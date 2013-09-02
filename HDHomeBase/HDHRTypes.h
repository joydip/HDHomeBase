//
//  HDHRTypes.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/28/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

// packet types
typedef NS_ENUM(UInt16, HDHRPacketType) {
    HDHRPacketDiscoverRequest = 0x0002,
    HDHRPacketDiscoverReply   = 0x0003,
    HDHRPacketGetSetRequest   = 0x0004,
    HDHRPacketGetSetReply     = 0x0005,
    HDHRPacketUpgradeRequest  = 0x0006,
    HDHRPacketUpgradeReply    = 0x0007,
};

// tags
typedef NS_ENUM(UInt8, HDHRTag) {
    HDHRDeviceTypeTag    = 0x01,
    HDHRDeviceIDTag      = 0x02,
    HDHRGetSetNameTag    = 0x03,
    HDHRGetSetValueTag   = 0x04,
    HDHRGetSetLockKeyTag = 0x15,
    HDHRErrorMessageTag  = 0x05,
    HDHRTunerCountTag    = 0x10,
};

// device types
typedef NS_ENUM(UInt32, HDHRDeviceType) {
    HDHRDeviceTypeWildcard = 0xFFFFFFFF,
    HDHRDeviceTypeTuner    = 0x00000001,
};

typedef UInt32 HDHRDeviceID;
#define HDHRDeviceIDWildcard 0xFFFFFFFF

@interface HDHRTypes : NSObject

+ (NSString *)descriptionForPacketType:(HDHRPacketType)type;
+ (NSString *)descriptionForTag:(HDHRTag)tag;

@end
