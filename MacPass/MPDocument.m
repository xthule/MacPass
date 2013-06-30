//
//  MPDocument.m
//  MacPass
//
//  Created by Michael Starke on 08.05.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import "MPDocument.h"
#import "MPDocumentWindowController.h"

#import "MPDatabaseVersion.h"
#import "MPRootAdapter.h"
#import "MPIconHelper.h"

#import "KdbLib.h"
#import "Kdb3Node.h"
#import "Kdb4Node.h"
#import "KdbPassword.h"
#import "KdbGroup+Undo.h"
#import "KdbGroup+KVOAdditions.h"
#import "Kdb4Entry+KVOAdditions.h"
#import "KdbGroup+MPTreeTools.h"
#import "KdbEntry+Undo.h"
#import "Kdb3Tree+NewTree.h"
#import "Kdb4Tree+NewTree.h"

NSString *const MPDocumentDidAddGroupNotification     = @"com.hicknhack.macpass.MPDocumentDidAddGroupNotification";
NSString *const MPDocumentWillDelteGroupNotification  = @"com.hicknhack.macpass.MPDocumentDidDelteGroupNotification";
NSString *const MPDocumentDidAddEntryNotification     = @"com.hicknhack.macpass.MPDocumentDidAddEntryNotification";
NSString *const MPDocumentWillDeleteEntryNotification = @"com.hicknhack.macpass.MPDocumentDidDeleteEntryNotification";
NSString *const MPDocumentDidRevertNotifiation        = @"com.hicknhack.macpass.MPDocumentDidRevertNotifiation";

NSString *const MPDocumentEntryKey                    = @"MPDocumentEntryKey";
NSString *const MPDocumentGroupKey                    = @"MPDocumentGroupKey";


@interface MPDocument () {
@private
  BOOL _didLockFile;
}


@property (retain, nonatomic) KdbTree *tree;
@property (assign, nonatomic) KdbGroup *root;
@property (nonatomic, readonly) KdbPassword *passwordHash;
@property (assign) MPDatabaseVersion version;

@property (assign, nonatomic) BOOL secured;
@property (assign) BOOL decrypted;
@property (assign) BOOL readOnly;

@property (retain) NSURL *lockFileURL;
@property (readonly, assign, nonatomic) KdbGroup *recyleBin;
@property (readonly) BOOL useRecylceBin;

@end


@implementation MPDocument

- (id)init
{
  return [self initWithVersion:MPDatabaseVersion4];
}
#pragma mark NSDocument essentials
- (id)initWithVersion:(MPDatabaseVersion)version {
  self = [super init];
  if(self) {
    _didLockFile = NO;
    _decrypted = YES;
    _secured = NO;
    _locked = NO;
    _readOnly = NO;
    _rootAdapter = [[MPRootAdapter alloc] init];
    _version = version;
    switch(_version) {
      case MPDatabaseVersion3:
        self.tree = [Kdb3Tree templateTree];
        break;
      case MPDatabaseVersion4:
        self.tree = [Kdb4Tree templateTree];
        break;
      default:
        [self release];
        return nil;
    }
  }
  return self;
}

- (void)dealloc {
  [self _cleanupLock];
  [_tree release];
  [_password release];
  [_key release];
  [_lockFileURL release];
  [_rootAdapter release];
  [super dealloc];
}

- (void)makeWindowControllers {
  MPDocumentWindowController *windowController = [[MPDocumentWindowController alloc] init];
  [self addWindowController:windowController];
  [windowController release];
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
  [super windowControllerDidLoadNib:aController];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
  NSError *error = nil;
  [KdbWriterFactory persist:self.tree fileURL:url withPassword:self.passwordHash error:&error];
  if(error) {
    NSLog(@"%@", [error localizedDescription]);
    return NO;
  }
  return YES;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
  self.lockFileURL = [url URLByAppendingPathExtension:@"lock"];
  if([[NSFileManager defaultManager] fileExistsAtPath:[_lockFileURL path]]) {
    self.readOnly = YES;
  }
  else {
    [[NSFileManager defaultManager] createFileAtPath:[_lockFileURL path] contents:nil attributes:nil];
    _didLockFile = YES;
    self.readOnly = NO;
  }
  self.decrypted = NO;
  return YES;
}

- (BOOL)revertToContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError {
  self.tree = nil;
  if([self readFromURL:absoluteURL ofType:typeName error:outError]) {
    [[NSNotificationCenter defaultCenter] postNotificationName:MPDocumentDidRevertNotifiation object:self];
    return YES;
  }
  return NO;
}

- (BOOL)isEntireFileLoaded {
  return _decrypted;
}

- (void)close {
  [self _cleanupLock];
  [super close];
}

#pragma mark Protection

- (BOOL)decryptWithPassword:(NSString *)password keyFileURL:(NSURL *)keyFileURL {
  self.key = keyFileURL;
  self.password = [password length] > 0 ? password : nil;
  @try {
    self.tree = [KdbReaderFactory load:[[self fileURL] path] withPassword:self.passwordHash];
  }
  @catch (NSException *exception) {
    return NO;
  }
  
  if([self.tree isKindOfClass:[Kdb4Tree class]]) {
    self.version = MPDatabaseVersion4;
  }
  else if( [self.tree isKindOfClass:[Kdb3Tree class]]) {
    self.version = MPDatabaseVersion3;
  }
  self.decrypted = YES;
  return YES;
}

- (void)setPassword:(NSString *)password {
  if(![_password isEqualToString:password]) {
    [_password release];
    _password = [password retain];
    _secured |= ([_password length] > 0);
  }
}

- (void)setKey:(NSURL *)key {
  if(![[_key absoluteString] isEqualToString:[key absoluteString]]) {
    [_key release];
    _key = [key retain];
    _secured |= (_key != nil);
  }
}

- (KdbPassword *)passwordHash {
  
  return [[[KdbPassword alloc] initWithPassword:self.password passwordEncoding:NSUTF8StringEncoding keyFileURL:self.key] autorelease];
}

+ (BOOL)autosavesInPlace
{
  return NO;
}

#pragma mark Data Accesors
- (void)setTree:(KdbTree *)tree {
  if(_tree != tree) {
    [_tree release];
    _tree = [tree retain];
    self.rootAdapter.tree = _tree;
  }
}

- (KdbGroup *)root {
  return self.tree.root;
}

- (KdbEntry *)findEntry:(UUID *)uuid {
  return [self.root entryForUUID:uuid];
}

- (KdbGroup *)findGroup:(UUID *)uuid {
  return [self.root groupForUUID:uuid];
}

- (Binary *)binaryForRef:(BinaryRef *)binaryRef {
  if(self.version != MPDatabaseVersion4) {
    return nil;
  }
  NSPredicate *filterPredicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
    Binary *binaryFile = evaluatedObject;
    return (binaryFile.binaryId == binaryRef.ref);
  }];
  Kdb4Tree *tree = (Kdb4Tree *)self.tree;
  NSArray *filteredBinary = [tree.binaries filteredArrayUsingPredicate:filterPredicate];
  return [filteredBinary lastObject];
}

- (Kdb3Tree *)treeV3 {
  switch (_version) {
    case MPDatabaseVersion3:
      NSAssert([self.tree isKindOfClass:[Kdb3Tree class]], @"Tree has to be Version3");
      return (Kdb3Tree *)self.tree;
    case MPDatabaseVersion4:
      return nil;
    default:
      return nil;
  }
}

- (Kdb4Tree *)treeV4 {
  switch (_version) {
    case MPDatabaseVersion3:
      return nil;
    case MPDatabaseVersion4:
      NSAssert([self.tree isKindOfClass:[Kdb4Tree class]], @"Tree has to be Version4");
      return (Kdb4Tree *)self.tree;
    default:
      return nil;
  }
}

- (BOOL)useRecylceBin {
  if(self.treeV4) {
    return self.treeV4.recycleBinEnabled;
  }
  return NO;
}

- (KdbGroup *)recyleBin {
  static KdbGroup *_recycleBin;
  if(self.useRecylceBin) {
    if(!_recycleBin) {
      _recycleBin = [self findGroup:self.treeV4.recycleBinUuid];
    }
    return _recycleBin;
  }
  return nil;
}

#pragma mark Data manipulation
- (KdbEntry *)createEntry:(KdbGroup *)parent {
  if(!parent) {
    return nil; // No parent
  }
  KdbEntry *newEntry = [self.tree createEntry:parent];
  newEntry.title = NSLocalizedString(@"DEFAULT_ENTRY_TITLE", @"Title for a newly created entry");
  if(self.treeV4 && ([self.treeV4.defaultUserName length] > 0)) {
    newEntry.title = self.treeV4.defaultUserName;
  }
  [self group:parent addEntry:newEntry atIndex:[parent.entries count]];
  NSDictionary *userInfo = @{ MPDocumentEntryKey : newEntry };
  [[NSNotificationCenter defaultCenter] postNotificationName:MPDocumentDidAddEntryNotification object:self userInfo:userInfo];
  return newEntry;
}

- (KdbGroup *)createGroup:(KdbGroup *)parent {
  if(!parent) {
    return nil; // no parent!
  }
  KdbGroup *newGroup = [self.tree createGroup:parent];
  newGroup.name = NSLocalizedString(@"DEFAULT_GROUP_NAME", @"Title for a newly created group");
  [self group:parent addGroup:newGroup atIndex:[parent.groups count]];
  NSDictionary *userInfo = @{ MPDocumentGroupKey : newGroup };
  [[NSNotificationCenter defaultCenter] postNotificationName:MPDocumentDidAddGroupNotification object:self userInfo:userInfo];
  return newGroup;
}

- (StringField *)createStringField:(KdbEntry *)entry {
  // TODO: Localize!
  if(![entry isKindOfClass:[Kdb4Entry class]]) {
    return nil;
  }
  Kdb4Entry *entryV4 = (Kdb4Entry *)entry;
  StringField *newStringField = [StringField stringFieldWithKey:@"Title" andValue:@"Value"];
  [self entry:entryV4 addStringField:newStringField atIndex:[entryV4.stringFields count]];
  return newStringField;
}


- (void)moveGroup:(KdbGroup *)group toGroup:(KdbGroup *)target index:(NSInteger)index {
  NSInteger oldIndex = [group.parent.groups indexOfObject:group];
  if(group.parent == target && oldIndex == index) {
    return; // No changes
  }
  [[[self undoManager] prepareWithInvocationTarget:self] moveGroup:group toGroup:group.parent index:oldIndex];
  if(self.recyleBin == target) {
    [[self undoManager] setActionName:@"UNDO_DELETE_GROUP"];
  }
  else {
    [[self undoManager] setActionName:@"MOVE_GROUP"];
  }
  [group.parent removeObjectFromGroupsAtIndex:oldIndex];
  if(index < 0 || index > [target.groups count] ) {
    index = [target.groups count];
  }
  [target insertObject:group inGroupsAtIndex:index];
}

- (BOOL)group:(KdbGroup *)group isMoveableToGroup:(KdbGroup *)target {
  if(target == nil) {
    return NO;
  }
  BOOL isMovable = YES;
  
  KdbGroup *ancestor = target.parent;
  while(ancestor.parent) {
    if(ancestor == group) {
      isMovable = NO;
      break;
    }
    ancestor = ancestor.parent;
  }
  return isMovable;
}

- (void)moveEntry:(KdbEntry *)entry toGroup:(KdbGroup *)target index:(NSInteger)index {
  NSInteger oldIndex = [entry.parent.entries indexOfObject:entry];
  if(entry.parent == target && oldIndex == index) {
    return; // No changes
  }
  [[[self undoManager] prepareWithInvocationTarget:self] moveEntry:entry toGroup:entry.parent index:oldIndex];
  if(self.recyleBin == target || self.recyleBin == entry.parent) {
    [[self undoManager] setActionName:@"UNDO_DELETE_ENTRY"];
  }
  else {
    [[self undoManager] setActionName:@"MOVE_ENTRY"];
  }
  [entry.parent removeObjectFromEntriesAtIndex:oldIndex];
  if(index < 0 || index > [target.groups count] ) {
    index = [target.groups count];
  }
  [target insertObject:entry inEntriesAtIndex:index];
}

- (void)group:(KdbGroup *)group addEntry:(KdbEntry *)entry atIndex:(NSUInteger)index {
  [[[self undoManager] prepareWithInvocationTarget:self] group:group removeEntry:entry];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_ADD_ENTRY", "Undo adding of entry")];
  [group insertObject:entry inEntriesAtIndex:index];
}

- (void)group:(KdbGroup *)group addGroup:(KdbGroup *)aGroup atIndex:(NSUInteger)index {
  [[[self undoManager] prepareWithInvocationTarget:self] group:group removeGroup:aGroup];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_ADD_GROUP", @"Create Group Undo")];
  [group insertObject:aGroup inGroupsAtIndex:index];
}

- (void)group:(KdbGroup *)group removeEntry:(KdbEntry *)entry {
  NSInteger index = [group.entries indexOfObject:entry];
  if(NSNotFound == index) {
    return; // No object found;
  }
  if(self.useRecylceBin) {
    if(!self.recyleBin) {
      [self _createRecylceBin];
    }
    [self moveEntry:entry toGroup:self.recyleBin index:[self.recyleBin.entries count]];
    return;
  }
  [[[self undoManager] prepareWithInvocationTarget:self] group:group addEntry:entry atIndex:index];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_DELETE_ENTRY", "Undo deleting of entry")];
  [group removeObjectFromEntriesAtIndex:index];
}

- (void)group:(KdbGroup *)group removeGroup:(KdbGroup *)aGroup {
  NSInteger index = [group.groups indexOfObject:aGroup];
  if(NSNotFound == index) {
    return; // No object found
  }
  /*
   Cleaning the recyclebin is not undoable
   So we do this in a separate action
   */
  if(self.useRecylceBin) {
    if(!self.recyleBin) {
      [self _createRecylceBin];
    }
    [self moveGroup:aGroup toGroup:self.recyleBin index:[self.recyleBin.groups count]];
    return; // Done!
  }
  [[[self undoManager] prepareWithInvocationTarget:self] group:group addGroup:aGroup atIndex:index];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_DELETE_GROUP", @"Delete Group Undo")];
  [group removeObjectFromGroupsAtIndex:index];
}

- (void)entry:(Kdb4Entry *)entry addStringField:(StringField *)field atIndex:(NSUInteger)index {
  [[[self undoManager] prepareWithInvocationTarget:self] entry:entry removeStringField:field];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_ADD_STRING_FIELD", @"Add Stringfield Undo")];
  [entry insertObject:field inStringFieldsAtIndex:index];
}

- (void)entry:(Kdb4Entry *)entry removeStringField:(StringField *)field {
  NSInteger index = [entry.stringFields indexOfObject:field];
  if(NSNotFound == index) {
    return; // Nothing found to be removed
  }
  [[[self undoManager] prepareWithInvocationTarget:self] entry:entry addStringField:field atIndex:index];
  [[self undoManager] setActionName:NSLocalizedString(@"UNDO_DELETE_STRING_FIELD", @"Delte Stringfield undo")];
  [entry removeObjectFromStringFieldsAtIndex:index];
}


#pragma mark Private
- (void)_cleanupLock {
  if(_didLockFile) {
    [[NSFileManager defaultManager] removeItemAtURL:_lockFileURL error:nil];
    _didLockFile = NO;
  }
}

- (void)_createRecylceBin {
  /* Maybe push the stuff to the Tree? */
  if(self.version == MPDatabaseVersion3) {
  }
  else if(self.version == MPDatabaseVersion4) {
    KdbGroup *recycleBin = [self.tree createGroup:self.tree.root];
    recycleBin.name = NSLocalizedString(@"RECYLEBIN", @"Name for the recycle bin group");
    recycleBin.image = MPIconTrash;
    [self.tree.root insertObject:recycleBin inGroupsAtIndex:[self.tree.root.groups count]];
    self.treeV4.recycleBinUuid = ((Kdb4Group *)recycleBin).uuid;
  }
  else {
    NSAssert(NO, @"Database with unknown version: %ld", _version);
  }
}

@end
