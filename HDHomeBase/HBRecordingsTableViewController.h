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

@property (strong) NSMutableArray *recordings;

@property (strong) IBOutlet HBScheduler *scheduler;

@property (strong) IBOutlet NSTableView *tableView;
@property (strong) IBOutlet NSToolbarItem *playRecordingToolbarItem;
@property (strong) IBOutlet NSToolbarItem *stopRecordingToolbarItem;
@property (strong) IBOutlet NSToolbarItem *deleteRecordingToolbarItem;

- (IBAction)refresh:(id)sender;
- (IBAction)playRecordingAction:(id)sender;
- (IBAction)stopRecordingAction:(id)sender;
- (IBAction)deleteRecordingAction:(id)sender;

@end
