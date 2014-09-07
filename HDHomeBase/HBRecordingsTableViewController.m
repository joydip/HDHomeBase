//
//  HBRecordingsTableViewController.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/1/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBRecordingsTableViewController.h"
#import "HBRecording.h"
#import "HBAppDelegate.h"
#import "HBScheduler.h"

@implementation HBRecordingsTableViewController

- (void)awakeFromNib
{
    self.recordings = self.scheduler.scheduledRecordings;
    [self.tableView setTarget:self];
    [self.tableView setDoubleAction:@selector(doubleClickAction:)];
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
    [self.recordings sortUsingDescriptors:self.tableView.sortDescriptors];
    [self.tableView reloadData];
}

- (IBAction)playRecordingAction:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    [self.scheduler playRecording:selectedRecordings[0]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    HBRecording *recording = nil;
    NSArray *conflictingRecordings = nil;
    HBRecording *candidateRecording = nil;
    
    NSInteger selectedRowIndex = [self.tableView selectedRow];
    
    if (selectedRowIndex != -1) {
        recording = self.recordings[selectedRowIndex];
        conflictingRecordings = recording.conflictingRecordings;
    }
    
    for (NSUInteger rowIndex = 0; rowIndex < self.recordings.count; rowIndex++) {
        if (recording) candidateRecording = self.recordings[rowIndex];
        NSTableRowView *view = [self.tableView rowViewAtRow:rowIndex makeIfNecessary:NO];

        // XXX this should be driven off number of available tuners
        if (recording && (conflictingRecordings.count > 1) && [conflictingRecordings containsObject:candidateRecording])
            view.backgroundColor = [NSColor colorWithDeviceRed:1.0f green:0.0f blue:0.0f alpha:0.25f];
        else
            view.backgroundColor = (rowIndex % 2) ? [NSColor controlAlternatingRowBackgroundColors][1] : [NSColor controlAlternatingRowBackgroundColors][0];
    }
}

- (void)doubleClickAction:(id)sender
{
    if (self.tableView.numberOfSelectedRows)
        [self playRecordingAction:self];
}

- (IBAction)deleteRecordingAction:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    for (HBRecording *recording in selectedRecordings) [self.scheduler deleteRecording:recording];
    [self.tableView reloadData];
}

- (IBAction)stopRecordingAction:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    for (HBRecording *recording in selectedRecordings) [self.scheduler stopRecording:recording];
}

- (BOOL)validateToolbarItem:(id)sender
{
    if (self.tableView.numberOfSelectedRows == 0)
        return NO;
    
    if (sender == self.stopRecordingToolbarItem) {
        __block BOOL currentlyRecording = NO;
        
        NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
        [self.recordings enumerateObjectsAtIndexes:selectedRowsIndexSet
                                           options:0
                                        usingBlock:^(id object, NSUInteger index, BOOL *stop) {
                                            HBRecording *recording = (HBRecording *)object;
                                            if (recording.currentlyRecording) {
                                                currentlyRecording = YES;
                                                *stop = YES;
                                            }
                                        }];
        return currentlyRecording;
    }
    
    return YES;
}

@end
