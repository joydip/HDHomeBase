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
#import "NSFileManager+DirectoryLocations.h"

@implementation HBAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self importExistingTVPISchedules];
}

- (NSString *)applicationSupportDirectory
{
    return [[NSFileManager defaultManager] applicationSupportDirectory];
}

- (void)importExistingTVPISchedules
{
    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    NSString *appSupportDirectory = [defaultFileManager applicationSupportDirectory];
    NSArray *applicationSupportDirectoryContents = [defaultFileManager contentsOfDirectoryAtPath:appSupportDirectory
                                                                                                       error:NULL];
    for (NSString *file in applicationSupportDirectoryContents)
        [self.scheduler importTVPIFile:[appSupportDirectory stringByAppendingPathComponent:file]];
    
    [self.recordingsTableViewController refresh:self];
}

- (void)importTVPIFile:(NSString *)filename
{
    NSString *tvpiFileTemplateString = [[self applicationSupportDirectory] stringByAppendingPathComponent:@"tvpi-XXXXXX"];
    const char *tvpiFileTemplateCString = [tvpiFileTemplateString fileSystemRepresentation];
    char *tvpiFileCString = (char *)malloc(strlen(tvpiFileTemplateCString)+1);
    strcpy(tvpiFileCString, tvpiFileTemplateCString);
    NSString *destinationTVPIFile = @(mktemp(tvpiFileCString));
    
    [[NSFileManager defaultManager] moveItemAtPath:filename toPath:destinationTVPIFile error:NULL];

    [self.scheduler importTVPIFile:destinationTVPIFile];
    [self.recordingsTableViewController refresh:self];
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    NSLog(@"processing %@ using openFile:", filename);
    [self importTVPIFile:filename];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    NSLog(@"processing %@ using openFiles:", filenames);

    for (NSString *filename in filenames)
        [self importTVPIFile:filename];
}

- (BOOL)application:(id)sender openFileWithoutUI:(NSString *)filename
{
    NSLog(@"processing %@ using openFileWithoutUI:", filename);
    [self importTVPIFile:filename];
    return YES;
}

- (BOOL)application:(NSApplication *)theApplication openTempFile:(NSString *)filename
{
    NSLog(@"processing %@ using openTempFile:", filename);
    [self importTVPIFile:filename];
    return YES;
}

@end
