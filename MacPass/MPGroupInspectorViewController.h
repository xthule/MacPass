//
//  MPGroupInspectorViewController.h
//  MacPass
//
//  Created by Michael Starke on 27.07.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import "MPViewController.h"
@class MPDocument;
@class HNHRoundedTextField;

@interface MPGroupInspectorViewController : MPViewController

@property (strong) IBOutlet NSView *contentView;
@property (weak) IBOutlet HNHRoundedTextField *titleTextField;
@property (unsafe_unretained) IBOutlet NSTextView *notesTextView;

@property (weak) IBOutlet NSButton *expiresCheckButton;

@property (weak) IBOutlet NSPopUpButton *searchPopupButton;
@property (weak) IBOutlet NSPopUpButton *autotypePopupButton;

- (void)setupBindings:(MPDocument *)document;

@end
