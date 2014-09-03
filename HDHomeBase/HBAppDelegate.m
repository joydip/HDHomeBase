//
//  HBAppDelegate.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBAppDelegate.h"
#import "HDHRDeviceManager.h"
#import "HBRecording.h"
#import "HBRecordingsController.h"
#import "HBScheduler.h"
#import "NSFileManager+DirectoryLocations.h"

@implementation HBAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self startDeviceDiscovery];
}

- (void)startDeviceDiscovery
{
    [self.deviceManager startDiscoveryAndError:NULL];
    [NSTimer scheduledTimerWithTimeInterval:3.0f
                                     target:self
                                   selector:@selector(stopDeviceDiscovery)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)stopDeviceDiscovery
{
    [self.deviceManager stopDiscovery];
    [self importExistingTVPISchedules];
}

- (void)importExistingTVPISchedules
{
    NSString *applicationSupportDirectory = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSArray *applicationSupportDirectoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:applicationSupportDirectory
                                                                                                       error:NULL];
    for (NSString *file in applicationSupportDirectoryContents)
        [self.scheduler importTVPIFile:[applicationSupportDirectory stringByAppendingPathComponent:file]];
    
    [self.recordingsController refresh:self];
}

- (void)importTVPIFile:(NSString *)filename
{
    NSString *tvpiFileTemplateString = [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"tvpi-XXXXXX"];
    const char *tvpiFileTemplateCString = [tvpiFileTemplateString fileSystemRepresentation];
    char *tvpiFileCString = (char *)malloc(strlen(tvpiFileTemplateCString)+1);
    strcpy(tvpiFileCString, tvpiFileTemplateCString);
    NSString *destinationTVPIFile = @(mktemp(tvpiFileCString));
    
    [[NSFileManager defaultManager] moveItemAtPath:filename toPath:destinationTVPIFile error:NULL];

    [self.scheduler importTVPIFile:destinationTVPIFile];

    [self.recordingsController refresh:self];
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    NSLog(@"processing %@ using openFile:", filename);
    [self importTVPIFile:filename];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    for (NSString *filename in filenames) {
        NSLog(@"processing %@ using openFile:", filename);
        [self importTVPIFile:filename];
    }
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
