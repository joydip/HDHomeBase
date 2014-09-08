//
//  HBAppDelegate.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBAppDelegate.h"
#import "HBRecording.h"
#import "HBRecordingsTableViewController.h"
#import "HBScheduler.h"

@implementation HBAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSArray *moviesDirectories = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES);
    NSString *defaultRecordingsFolder = moviesDirectories[0];

    NSDictionary *appDefaults = @{
                                  @"RecordingsFolder": defaultRecordingsFolder,
                                  @"BeginningPadding": @30,
                                  @"EndingPadding":    @30,
                                  @"TotalTunerCount":  @3,
                                };
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];

    [self.scheduler importExistingSchedules];
    [self.recordingsTableViewController refresh:self];
}

- (void)importTVPIFile:(NSString *)filename
{
    [self.scheduler importTVPIFile:filename];
    [self.recordingsTableViewController refresh:self];
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    [self importTVPIFile:filename];
    return YES; // XXX blindly returning YES
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    for (NSString *filename in filenames) [self importTVPIFile:filename];
}

- (BOOL)application:(id)sender openFileWithoutUI:(NSString *)filename
{

    [self importTVPIFile:filename];
    return YES; // XXX blindly returning YES
}

- (BOOL)application:(NSApplication *)theApplication openTempFile:(NSString *)filename
{
    [self importTVPIFile:filename];
    return YES; // XXX blindly returning YES
}

@end
