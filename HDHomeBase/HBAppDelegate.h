//
//  HBAppDelegate.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class HBScheduler;
@class HBRecordingsTableViewController;

@interface HBAppDelegate : NSObject <NSApplicationDelegate>

@property (strong) IBOutlet HBScheduler *scheduler;
@property (strong) IBOutlet HBRecordingsTableViewController *recordingsTableViewController;

@end
