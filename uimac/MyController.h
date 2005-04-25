/* MyController */
/* Copyright (c) 2003, see file COPYING for details. */

#import <Cocoa/Cocoa.h>
#include <caml/mlvalues.h>
#import "ProfileController.h"
#import "PreferencesController.h"
#import "ReconTableView.h"

@interface MyController : NSObject
{
    IBOutlet NSWindow *mainWindow;

    IBOutlet ProfileController *profileController;
    IBOutlet NSView *chooseProfileView;
    NSSize chooseProfileSize;

    IBOutlet PreferencesController *preferencesController;
    IBOutlet NSView *preferencesView;
    NSSize preferencesSize;

    IBOutlet NSView *updatesView;
    NSSize updatesSize;

    IBOutlet ReconTableView *tableView;
    IBOutlet NSTextField *updatesText;

    IBOutlet NSWindow *passwordWindow;
    IBOutlet NSTextField *passwordText;
    IBOutlet NSTextView *detailsTextView;
    IBOutlet NSTextField *statusText;
    
    IBOutlet NSButton *passwordCancelButton;

    NSView *blankView;
    value caml_reconItems;
    NSMutableArray *reconItems;
    value preconn;
}
- (IBAction)createButton:(id)sender;
- (IBAction)saveProfileButton:(id)sender;
- (IBAction)cancelProfileButton:(id)sender;
- (IBAction)openButton:(id)sender;
- (IBAction)restartButton:(id)sender;
- (IBAction)syncButton:(id)sender;
- (int)numberOfRowsInTableView:(NSTableView *)aTableView;
- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
    row:(int)rowIndex;
- (void)raisePasswordWindow:(NSString *)prompt;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
- (IBAction)endPasswordWindow:(id)sender;
- (NSMutableArray *)reconItems;
- (int)updateForIgnore:(int)i;
- (void)displayDetails:(int)i;
@end