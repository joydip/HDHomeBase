//
//  HBRecording.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBRecording.h"

@implementation HBRecording

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

- (instancetype)initWithTVPIFile:(NSString *)tvpiFilePath
{
    if (self = [super init]) {
        NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:tvpiFilePath]
                                                                       options:0
                                                                         error:NULL];
        NSXMLElement *rootElement = [document rootElement];
        
        for (NSXMLElement *childElement in rootElement.children) {
            if ([childElement.name isEqualToString:@"program"]) {
                _tvpiFilePath = [tvpiFilePath copy];
                
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
                
                NSString *recordingFileDateString = [[[self class] recordingFileDateFormatter] stringFromDate:_startDate];
                NSMutableString *baseName = [_title mutableCopy];
                
                if (_episode.length) [baseName appendFormat:@" - %@", _episode];
                
                NSString *fileName = [NSString stringWithFormat:@"%@ (%@ %@).ts", baseName, _channelName, recordingFileDateString];
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory,
                                                                     NSUserDomainMask,
                                                                     YES);
                _recordingFilePath = [NSString pathWithComponents:@[paths[0], fileName]];;
            }
        }
    }
    
    return self;
}

- (void)markAsScheduled
{
    self.statusIconImage = [NSImage imageNamed:@"scheduled"];
}

- (void)markAsExisting
{
    self.statusIconImage = [NSImage imageNamed:@"movie"];
}

- (void)markAsStarting
{
    self.statusIconImage = [NSImage imageNamed:@"orange"];
}

- (void)markAsSuccess
{
    self.statusIconImage = [NSImage imageNamed:@"recording"];
}

@end
