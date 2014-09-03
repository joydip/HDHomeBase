//
//  HBRecordingsController.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/1/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBRecordingsController.h"
#import "HBRecording.h"
#import "HBAppDelegate.h"
#import "HBScheduler.h"

@interface HBRecordingsController ()

@end

@implementation HBRecordingsController

- (void)awakeFromNib
{
    HBScheduler *scheduler = ((HBAppDelegate *)[NSApp delegate]).scheduler;
    self.recordings = scheduler.scheduledRecordings;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.recordings.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    return (self.recordings)[row];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [self.recordings sortUsingDescriptors:[tableView sortDescriptors]];
    [tableView reloadData];
}

- (IBAction)refresh:(id)sender
{
    [self.tableView reloadData];
}

- (IBAction)deleteSchedule:(id)sender
{
    NSLog(@"delete!");
}

- (IBAction)stopRecording:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    for (HBRecording *recording in selectedRecordings) {
        if (recording.currentlyRecording)
            [recording stopRecording:sender];
    }
}

- (BOOL)validateToolbarItem:(id)sender
{
    if (sender == self.stopRecordingToolbarItem) {
        if (self.tableView.numberOfSelectedRows == 0)
            return NO;

        
        __block BOOL currentlyRecording = NO;
        
        NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
        [self.recordings enumerateObjectsAtIndexes:selectedRowsIndexSet
                                           options:0
                                        usingBlock:^(id object, NSUInteger index, BOOL *stop) {
                                            HBRecording *recording = (HBRecording *)object;
                                            if (recording.currentlyRecording)
                                                currentlyRecording = YES;
                                        }];
        return currentlyRecording;
        
    }
    
    return NO;
}

@end
