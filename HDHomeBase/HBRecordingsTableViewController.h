//
//  HBRecordingsTableViewController.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/1/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class HBScheduler;

@interface HBRecordingsTableViewController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property NSMutableArray *recordings;

@property IBOutlet HBScheduler *scheduler;

@property IBOutlet NSTableView *tableView;
@property IBOutlet NSToolbarItem *playRecordingToolbarItem;
@property IBOutlet NSToolbarItem *stopRecordingToolbarItem;
@property IBOutlet NSToolbarItem *deleteRecordingToolbarItem;
@property IBOutlet NSToolbarItem *showFileToolbarItem;

- (IBAction)refresh:(id)sender;
- (IBAction)playRecordingAction:(id)sender;
- (IBAction)stopRecordingAction:(id)sender;
- (IBAction)deleteRecordingAction:(id)sender;
- (IBAction)showFileAction:(id)sender;

@end
