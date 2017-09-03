//
//  HBAppDelegate.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBAppDelegate.h"
#import "HBProgram.h"
#import "HBRecordingsTableViewController.h"
#import "HBScheduler.h"
#include "hdhomerun.h"

@implementation HBAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSArray *moviesDirectories = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES);
    NSString *defaultRecordingsFolder = moviesDirectories[0];

    NSDictionary *appDefaults = @{
                                  @"RecordingFolders": @[defaultRecordingsFolder],
                                  @"BeginningPadding": @60,
                                  @"EndingPadding":    @60,
                                  @"TotalTunerCount":  @3,
                                  @"DeviceID":         @(HDHOMERUN_DEVICE_ID_WILDCARD),
                                };
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];

    [self.scheduler scanRecordingFolders];
    [self.recordingsTableViewController refresh:self];
}

- (BOOL)importTVPIFile:(NSString *)filename
{
    if ([self.scheduler importTVPIFile:filename]) {
        [self.recordingsTableViewController refresh:self];
        return YES;
    }
    
    return NO;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    return [self importTVPIFile:filename]; 
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    for (NSString *filename in filenames) [self importTVPIFile:filename];
}

- (BOOL)application:(id)sender openFileWithoutUI:(NSString *)filename
{
    return [self importTVPIFile:filename];
}

- (BOOL)application:(NSApplication *)theApplication openTempFile:(NSString *)filename
{
    return [self importTVPIFile:filename];
}

@end
