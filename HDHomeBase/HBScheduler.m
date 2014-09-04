//
//  HBScheduler.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBScheduler.h"
#import "HBRecording.h"

@implementation HBScheduler


- (id)init
{
    if ((self = [super init]))
        _scheduledRecordings = [NSMutableArray new];
    
    return self;
}

- (NSDateFormatter *)dateFormatter
{
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    [dateFormatter setDateFormat:@"yyyyMMddHHmm"];
    return dateFormatter;
}

- (void)importTVPIFile:(NSString *)filename
{
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:filename]
                                                                   options:0
                                                                     error:NULL];
    
    NSXMLElement *rootElement = [document rootElement];
    
    for (NSXMLElement *childElement in rootElement.children) {
        if ([childElement.name isEqualToString:@"program"]) {
            HBRecording *recording = [HBRecording new];
            recording.tvpiFilePath = filename;
            
            recording.deviceManager = self.deviceManager;
            
            NSXMLElement *programElement = childElement;
            
            NSString *startDateString = nil;
            NSString *startTimeString = nil;

            NSString *endDateString = nil;
            NSString *endTimeString = nil;

            for (NSXMLElement *childElement in programElement.children) {
                if ([childElement.name isEqualToString:@"station"])
                    recording.channelName = childElement.stringValue;
                
                else if ([childElement.name isEqualToString:@"tv-mode"])
                    recording.mode = childElement.stringValue;
                
                else if ([childElement.name isEqualToString:@"program-title"])
                    recording.title = childElement.stringValue;
                
                else if ([childElement.name isEqualToString:@"episode-title"])
                    recording.episode = childElement.stringValue;
                
                else if ([childElement.name isEqualToString:@"program-description"])
                    recording.summary = childElement.stringValue;
                
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
                    recording.duration = hourDuration * 60 + minuteDuration;
                }
                
                else if ([childElement.name isEqualToString:@"rf-channel"])
                    recording.rfChannel = childElement.stringValue;
                
                else if ([childElement.name isEqualToString:@"stream-number"])
                    recording.streamNumber = childElement.stringValue;
                
                else if ([childElement.name isEqualToString:@"psip-major"])
                    recording.psipMajor = [childElement.stringValue integerValue];
                
                else if ([childElement.name isEqualToString:@"psip-minor"])
                    recording.psipMinor = [childElement.stringValue integerValue];
            }
            
            if (startDateString && startTimeString) {
                NSDateFormatter *dateFormatter = [NSDateFormatter new];
                [dateFormatter setDateFormat:@"yyyyMMdd HH:mm"];
                [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
                NSString *dateString = [NSString stringWithFormat:@"%@ %@", startDateString, startTimeString];
                // NSLog(@"%@", dateString);
                recording.startDate = [dateFormatter dateFromString:dateString];
            }
            
            if (endDateString && endTimeString) {
                NSDateFormatter *dateFormatter = [NSDateFormatter new];
                [dateFormatter setDateFormat:@"yyyyMMdd HH:mm"];
                [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
                NSString *dateString = [NSString stringWithFormat:@"%@ %@", endDateString, endTimeString];
                // NSLog(@"%@", dateString);
                recording.endDate = [dateFormatter dateFromString:dateString];
            }

            
            NSString *formattedDateString = [self.dateFormatter stringFromDate:recording.startDate];
            NSMutableString *baseName = [recording.title mutableCopy];
            
            if (recording.episode.length) [baseName appendFormat:@" - %@", recording.episode];
            
            NSString *fileName = [NSString stringWithFormat:@"%@ (%@ %@).ts", baseName, recording.channelName, formattedDateString];
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory,
                                                                 NSUserDomainMask,
                                                                 YES);
            NSString *fullPath = [NSString pathWithComponents:@[paths[0], fileName]];
            recording.recordingPath = fullPath;
            
            
            
            [self.scheduledRecordings addObject:recording];

            // only if the end date hasn't passed are we interested
            if ([recording.endDate compare:[NSDate date]] == NSOrderedDescending) {
                NSTimer *startTimer = [[NSTimer alloc] initWithFireDate:recording.startDate
                                                               interval:0
                                                                 target:recording
                                                               selector:@selector(startRecording:)
                                                               userInfo:nil
                                                                repeats:NO];
                
                [[NSRunLoop mainRunLoop] addTimer:startTimer forMode:NSRunLoopCommonModes];
                
                NSTimer *stopTimer = [[NSTimer alloc] initWithFireDate:recording.endDate
                                                              interval:0
                                                                target:recording
                                                              selector:@selector(stopRecording:)
                                                              userInfo:nil
                                                               repeats:NO];
                
                [[NSRunLoop mainRunLoop] addTimer:stopTimer forMode:NSRunLoopCommonModes];
            } else
                recording.statusIconImage = [NSImage imageNamed:@"statusGreen"];
        }
    }    
}

@end
