//
//  HDHRTypes.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/28/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HDHRTypes.h"

@implementation HDHRTypes

+ (NSString *)descriptionForPacketType:(HDHRPacketType)type
{
    switch (type) {
        case HDHRPacketDiscoverRequest:
            return @"Discover Request";
            
        case HDHRPacketDiscoverReply:
            return @"Discover Reply";
            
        case HDHRPacketGetSetRequest:
            return @"Get/Set Request";
            
        case HDHRPacketGetSetReply:
            return @"Get/Set Reply";
            
        case HDHRPacketUpgradeRequest:
            return @"Upgrade Request";
            
        case HDHRPacketUpgradeReply:
            return @"Upgrade Reply";
    }
    
    return @"unknown";
}

+ (NSString *)descriptionForTag:(HDHRTag)tag
{
    switch (tag) {
        case HDHRDeviceTypeTag:
            return @"Device Type";
            
        case HDHRDeviceIDTag:
            return @"Device ID";
            
        case HDHRGetSetNameTag:
            return @"Get/Set Name";
            
        case HDHRGetSetValueTag:
            return @"Get/Set Value";
            
        case HDHRGetSetLockKeyTag:
            return @"Get/Set Lock Key";
            
        case HDHRErrorMessageTag:
            return @"Error Message";
            
        case HDHRTunerCountTag:
            return @"Tuner Count";
    }
    
    return @"unknown";
}

@end
