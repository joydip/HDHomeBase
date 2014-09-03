//
//  HBRecordingsController.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/1/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface HBRecordingsController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSMutableArray *recordings;
@property (nonatomic, strong) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) IBOutlet NSToolbarItem *refreshToolbarItem;
@property (nonatomic, strong) IBOutlet NSToolbarItem *stopRecordingToolbarItem;
@property (nonatomic, strong) IBOutlet NSToolbarItem *deleteScheduleToolbarItem;


- (IBAction)refresh:(id)sender;
- (IBAction)stopRecording:(id)sender;
- (IBAction)deleteSchedule:(id)sender;

@end
