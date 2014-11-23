//
//  HBProgram.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HBProgram : NSObject

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

+ (instancetype)programFromTVPIFile:(NSString *)tvpiFilePath;
+ (instancetype)programFromPropertyListFile:(NSString *)propertyListFilePath;

- (instancetype)initWithTVPIFile:(NSString *)tvpiFilePath;
- (instancetype)initWithPropertyListFile:(NSString *)propertyListFilePath;

- (BOOL)serializeAsPropertyListFileToPath:(NSString *)path error:(NSError **)error;

@end
