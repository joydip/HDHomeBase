//
//  HBProgram.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBProgram.h"

@implementation HBProgram

+ (NSDateFormatter *)recordingFileDateFormatter
{
    static dispatch_once_t predicate;
    static NSDateFormatter *dateFormatter = nil;

    dispatch_once(&predicate, ^{
        dateFormatter = [NSDateFormatter new];
        [dateFormatter setDateFormat:@"yyyyMMddHHmm"];
    });
                  
    return dateFormatter;
}

+ (NSDateFormatter *)tvpiStartEndDateFormatter
{
    static dispatch_once_t predicate;
    static NSDateFormatter *dateFormatter = nil;
    
    dispatch_once(&predicate, ^{
        dateFormatter = [NSDateFormatter new];
        [dateFormatter setDateFormat:@"yyyyMMdd HH:mm"];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    });
    
    return dateFormatter;
}

+ (instancetype)recordingFromTVPIFile:(NSString *)tvpiFilePath
{
    return [[self alloc] initWithTVPIFile:tvpiFilePath];
}

+ (instancetype)recordingFromPropertyListFile:(NSString *)propertyListFilePath
{
    return [[self alloc] initWithPropertyListFile:propertyListFilePath];
}

- (instancetype)initWithTVPIFile:(NSString *)tvpiFilePath
{
    if (self = [super init]) {
        NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:tvpiFilePath]
                                                                       options:0
                                                                         error:NULL];
        NSXMLElement *rootElement = [document rootElement];
        
        for (NSXMLElement *childElement in rootElement.children) {
            if ([childElement.name isEqualToString:@"program"]) {
                NSXMLElement *programElement = childElement;
                
                NSString *startDateString = nil;
                NSString *startTimeString = nil;
                NSString *endDateString = nil;
                NSString *endTimeString = nil;
                
                for (NSXMLElement *childElement in programElement.children) {
                    if ([childElement.name isEqualToString:@"station"])
                        _channelName = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"tv-mode"])
                        _mode = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"program-title"])
                        _title = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"episode-title"])
                        _episode = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"program-description"])
                        _summary = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"start-date"])
                        startDateString = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"start-time"])
                        startTimeString = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"end-date"])
                        endDateString = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"end-time"])
                        endTimeString = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"duration"]) {
                        NSArray *durationComponents = [childElement.stringValue componentsSeparatedByString:@":"];
                        NSInteger hourDuration = [durationComponents[0] integerValue];
                        NSInteger minuteDuration = [durationComponents[1] integerValue];
                        _duration = hourDuration * 60 + minuteDuration;
                    }
                    
                    else if ([childElement.name isEqualToString:@"rf-channel"])
                        _rfChannel = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"stream-number"])
                        _streamNumber = childElement.stringValue;
                    
                    else if ([childElement.name isEqualToString:@"psip-major"])
                        _psipMajor = [childElement.stringValue integerValue];
                    
                    else if ([childElement.name isEqualToString:@"psip-minor"])
                        _psipMinor = [childElement.stringValue integerValue];
                }
                
                if (startDateString && startTimeString) {
                    NSString *dateString = [NSString stringWithFormat:@"%@ %@", startDateString, startTimeString];
                    _startDate = [[[self class] tvpiStartEndDateFormatter] dateFromString:dateString];
                }
                
                if (endDateString && endTimeString) {
                    NSString *dateString = [NSString stringWithFormat:@"%@ %@", endDateString, endTimeString];
                    _endDate = [[[self class] tvpiStartEndDateFormatter] dateFromString:dateString];
                }
            }
        }
    }
    
    return self;
}

- (instancetype)initWithPropertyListFile:(NSString *)propertyListFilePath
{
    if (self = [super init]) {
        NSData *propertyListData = [NSData dataWithContentsOfFile:propertyListFilePath];
        
        if (propertyListData) {
            NSDictionary *dictionary = [NSPropertyListSerialization propertyListWithData:propertyListData
                                                                                 options:NSPropertyListImmutable
                                                                                  format:NULL
                                                                                   error:NULL];
            _mode = dictionary[@"mode"];
            _title = dictionary[@"title"];
            _episode = dictionary[@"episode"];
            _summary = dictionary[@"summary"];
            _startDate = dictionary[@"startDate"];
            _endDate = dictionary[@"endDate"];
            _duration = [dictionary[@"duration"] unsignedShortValue];
            _channelName = dictionary[@"channelName"];
            _rfChannel = dictionary[@"rfChannel"];
            _streamNumber = dictionary[@"streamNumber"];
            _psipMajor = [dictionary[@"psipMajor"] unsignedShortValue];
            _psipMinor = [dictionary[@"psipMinor"] unsignedShortValue];
        }
    }
    
    return self;
}

- (NSString *)uniqueName
{
    NSString *recordingFileDateString = [[[self class] recordingFileDateFormatter] stringFromDate:self.startDate];
    NSString *baseName = (self.episode.length) ? [NSString stringWithFormat:@"%@ - %@", self.title, self.episode] : self.title;
    return [NSString stringWithFormat:@"%@ (%@ %@)", baseName, self.channelName, recordingFileDateString];
}

- (NSString *)recordingFilename
{
    return [self.uniqueName stringByAppendingString:@".ts"];
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *dict = [NSMutableDictionary new];
    NSArray *keys = @[
                      @"mode",
                      @"title",
                      @"episode",
                      @"summary",
                      @"startDate",
                      @"endDate",
                      @"duration",
                      @"channelName",
                      @"rfChannel",
                      @"streamNumber",
                      @"psipMajor",
                      @"psipMinor",
                    ];
    
    for (NSString *key in keys) {
        id value = [self valueForKey:key];
        if (value) dict[key] = value;
    }
    
    return dict;
}

- (BOOL)serializeAsPropertyListFileToPath:(NSString *)path error:(NSError **)error
{
    NSData *propertyListData = [NSPropertyListSerialization dataWithPropertyList:[self dictionaryRepresentation]
                                                                           format:NSPropertyListXMLFormat_v1_0
                                                                          options:0
                                                                            error:error];
    if (!propertyListData) return NO;
    return [propertyListData writeToFile:path atomically:YES];
}

- (BOOL)startOverlapsWithRecording:(HBProgram *)otherRecording
{
    NSDate *myStartDate = self.paddedStartDate;
    NSDate *otherEndDate = otherRecording.paddedEndDate;
    
    return ([myStartDate compare:otherEndDate] != NSOrderedDescending);
}

- (BOOL)hasEndDatePassed
{
    return ([self.endDate compare:[NSDate date]] != NSOrderedDescending);
}

-(NSString *)canonicalChannel
{
    if ([self.mode isEqualToString:@"digital"])
        return [NSString stringWithFormat:@"%hu.%hu", self.psipMajor, self.psipMinor];

    return self.rfChannel;
}

@end
