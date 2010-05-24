//
//  $Id$
//
//  SPWindowController.m
//  sequel-pro
//
//  Created by Rowan Beentje on May 16, 2010
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>

#import "SPWindowController.h"
#import "SPConstants.h"
#import "TableDocument.h"
#import <PSMTabBar/PSMTabBarControl.h>
#import <PSMTabBar/PSMTabStyle.h>

@implementation SPWindowController

/**
 * awakeFromNib
 */
- (void) awakeFromNib
{

	// Disable automatic cascading - this occurs before the size is set, so let the app
	// controller apply cascading after frame autosaving.
	[self setShouldCascadeWindows:NO];

	// Initialise the managed database connections array
	managedDatabaseConnections = [[NSMutableArray alloc] init];

	// Set up the tab bar
	[tabBar setStyleNamed:@"Metal"];
	[tabBar setCanCloseOnlyTab:NO];
	[tabBar setHideForSingleTab:YES];
	[tabBar setShowAddTabButton:YES];
	[tabBar setSizeCellsToFit:NO];
	[tabBar setCellMinWidth:100];
	[tabBar setCellMaxWidth:250];
	[tabBar setCellOptimumWidth:250];

    // hook up add tab button
    [[tabBar addTabButton] setTarget:self];
    [[tabBar addTabButton] setAction:@selector(addNewConnection:)];

	// Retrieve references to the 'Close Window' and 'Close Tab' menus.  These are updated as window focus changes.
	closeWindowMenuItem = [[[[NSApp mainMenu] itemWithTag:SPMainMenuFile] submenu] itemWithTag:1003];
	closeTabMenuItem = [[[[NSApp mainMenu] itemWithTag:SPMainMenuFile] submenu] itemWithTag:1103];

	// Add a new connection to the new window
	[self addNewConnection:self];
}

/**
 * Deallocation
 */
- (void) dealloc
{
	[managedDatabaseConnections release];
}

#pragma mark -
#pragma mark Database connection management

/**
 * Add a new database connection to the window, in a tab view.
 */
- (IBAction) addNewConnection:(id)sender
{

	// Create a new database connection view
	TableDocument *newTableDocument = [[TableDocument alloc] init];
	[newTableDocument setParentWindowController:self];
	[newTableDocument setParentWindow:[self window]];

	// Set up a new tab with the connection view as the identifier, add the view, and add it to the tab view
    NSTabViewItem *newItem = [[[NSTabViewItem alloc] initWithIdentifier:newTableDocument] autorelease];
	[newItem setView:[newTableDocument parentView]];
    [tabView addTabViewItem:newItem];
    [tabView selectTabViewItem:newItem];
	[newTableDocument setParentTabViewItem:newItem];

	// Tell the new database connection view to set up the window and update titles
	[newTableDocument didBecomeActiveTabInWindow];
	[newTableDocument updateWindowTitle:self];
	
	[newTableDocument release];
}

/**
 * Retrieve the currently connection view in the window.
 */
- (TableDocument *) selectedTableDocument
{
	return [[tabView selectedTabViewItem] identifier];
}

/**
 * Ask all the connection views to update their titles.
 * As tab titles depend on the currently selected tab, changes
 * within each tab may require other tabs to update their titles.
 * If the sender is a tab, that tab is skipped when updating titles.
 */
- (void) updateAllTabTitles:(id)sender
{
	for (NSTabViewItem *eachItem in [tabView tabViewItems]) {
		TableDocument *eachDocument = [eachItem identifier];
		if (eachDocument != sender) [eachDocument updateWindowTitle:self];
	}
}


/**
 * Close the current tab, or if it's the last in the window, the window.
 */
- (IBAction)closeTab:(id)sender
{

	// Return if the frontmost tab shouldn't be closed
	TableDocument *frontDocument = [[tabView selectedTabViewItem] identifier];
	if (![frontDocument parentTabShouldClose]) return NO;

	// If there are multiple tabs, close the front tab.
	if ([tabView numberOfTabViewItems] > 1) {
		[tabView removeTabViewItem:[tabView selectedTabViewItem]];
	} else {
		[[self window] performClose:self];
	}
}

/**
 * Retrieve the documents associated with this window.
 */
- (NSArray *)documents
{
	NSMutableArray *documentsArray = [NSMutableArray array];
	for (NSTabViewItem *eachItem in [tabView tabViewItems]) {
		[documentsArray addObject:[eachItem identifier]];
	}
	return documentsArray;
}

#pragma mark -
#pragma mark Tab view delegate methods

/**
 * Called when a tab item is about to be selected.
 */
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	TableDocument *currentlySelectedDocument = [[tabView selectedTabViewItem] identifier];
	[currentlySelectedDocument willResignActiveTabInWindow];
}

/**
 * Called when a tab item was selected.
 */
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	TableDocument *theDocument = [tabViewItem identifier];
	[theDocument didBecomeActiveTabInWindow];
	if ([[self window] isKeyWindow]) [theDocument tabDidBecomeKey];
	[self updateAllTabTitles:self];
}

/**
 * Called to determine whether a tab view item can be closed
 */
- (BOOL)tabView:(NSTabView *)aTabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
	TableDocument *theDocument = [tabViewItem identifier];
	if (![theDocument parentTabShouldClose]) return NO;
	return YES;
}

/**
 * Called after a tab view item is closed.
 */
- (void)tabView:(NSTabView *)aTabView didCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
	TableDocument *theDocument = [tabViewItem identifier];
	[theDocument parentTabDidClose];
}

/**
 * Called to allow dragging of tab view items
 */
- (BOOL)tabView:(NSTabView *)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl
{
	return YES;
}

/**
 * Called when a tab finishes a drop.  This is called with the new tabView.
 */
- (void)tabView:(NSTabView*)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl
{
	TableDocument *draggedDocument = [tabViewItem identifier];

	// Grab a reference to the old window
	NSWindow *draggedFromWindow = [draggedDocument parentWindow];

	// If the window changed, perform additional processing.
	if (draggedFromWindow != [tabBarControl window]) {
		
		// Update the old window
		[[[draggedFromWindow windowController] selectedTableDocument] didBecomeActiveTabInWindow];

		// Update the item's document's window
		[draggedDocument willResignActiveTabInWindow];
		[draggedDocument setParentWindow:[tabBarControl window]];
		[draggedDocument didBecomeActiveTabInWindow];
	}
}

- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem
{
	[[aTabView window] close];
}

#pragma mark -
#pragma mark Window delegate methods

/**
 * Determine whether the window is permitted to close.
 * Go through the tabs in this window, and ask the database connection view
 * in each one if it can be closed, returning YES only if all can be closed.
 */
- (BOOL)windowShouldClose:(id)sender
{
	for (NSTabViewItem *eachItem in [tabView tabViewItems]) {
		TableDocument *eachDocument = [eachItem identifier];
		if (![eachDocument parentTabShouldClose]) return NO;
	}

	return YES;
}

/**
 * When the window does close, close all tabs.
 */
- (void)windowWillClose:(NSNotification *)notification

{
	for (NSTabViewItem *eachItem in [tabView tabViewItems]) {
		[tabView removeTabViewItem:eachItem];
	}
	[self autorelease];
}

/**
 * When the window becomes key, inform the selected tab and
 * update menu items.
 */
- (void)windowDidBecomeKey:(NSNotification *)notification
{
	TableDocument *selectedTab = [[tabView selectedTabViewItem] identifier];
	[selectedTab tabDidBecomeKey];

	// Update the "Close window" item
	[closeWindowMenuItem setTitle:NSLocalizedString(@"Close Window", @"Close Window menu item")];
	[closeWindowMenuItem setKeyEquivalentModifierMask:(NSCommandKeyMask | NSShiftKeyMask)];

	// Ensure the "Close tab" item is enabled and has the standard shortcut
	[closeTabMenuItem setEnabled:YES];
	[closeTabMenuItem setKeyEquivalent:@"w"];
	[closeTabMenuItem setKeyEquivalentModifierMask:NSCommandKeyMask];
}

/**
 * When the window resigns key, update menu items.
 */
- (void)windowDidResignKey:(NSNotification *)notification
{
	// Disable the "Close tab" menu item
	[closeTabMenuItem setEnabled:NO];
	[closeTabMenuItem setKeyEquivalent:@""];

	// Update the "Close window" item to show only "Close"
	[closeWindowMenuItem setTitle:NSLocalizedString(@"Close", @"Close menu item")];
	[closeWindowMenuItem setKeyEquivalentModifierMask:NSCommandKeyMask];
}

/**
 * If the window is resized, notify all the tabs.
 */
- (void)windowDidResize:(NSNotification *)notification
{
	for (NSTabViewItem *eachItem in [tabView tabViewItems]) {
		TableDocument *eachDocument = [eachItem identifier];
		[eachDocument tabDidResize];
	}
}

#pragma mark -
#pragma mark First responder forwarding to active tab

/**
 * Delegate unrecognised methods to the selected table document, thanks to the magic
 * of NSInvocation (see forwardInvocation: docs for background). Must be paired
 * with methodSignationForSelector:.
 */
- (void) forwardInvocation:(NSInvocation *)theInvocation
{
	TableDocument *frontDocument = [[tabView selectedTabViewItem] identifier]; 
	SEL theSelector = [theInvocation selector];
	if (![frontDocument respondsToSelector:theSelector]) [self doesNotRecognizeSelector:theSelector];
	[theInvocation invokeWithTarget:frontDocument];
}

/**
 * Return the correct method signatures for the selected table document if
 * NSObject doesn't implement the requested methods.
 */
- (NSMethodSignature *) methodSignatureForSelector:(SEL)theSelector
{
	NSMethodSignature *defaultSignature = [super methodSignatureForSelector:theSelector];
	if (defaultSignature) return defaultSignature;

	return [[[tabView selectedTabViewItem] identifier] methodSignatureForSelector:theSelector];
}

/**
 * Override the default repondsToSelector:, returning true if either NSObject
 * or the selected table document supports the selector.
 */
- (BOOL) respondsToSelector:(SEL)theSelector
{	
	return ([super respondsToSelector:theSelector] || [[[tabView selectedTabViewItem] identifier] respondsToSelector:theSelector]);
}

/**
 * Override the default performSelector:, again either using NSObject defaults
 * or performing the selector on the selected table document.
 */
- (id) performSelector:(SEL)theSelector
{
	if ([super respondsToSelector:theSelector]) return [super performSelector:theSelector];

	TableDocument *frontDocument = [[tabView selectedTabViewItem] identifier]; 
	if (![frontDocument respondsToSelector:theSelector]) [self doesNotRecognizeSelector:theSelector];
	return [frontDocument performSelector:theSelector];
}

/**
 * Override the default performSelector:withObject: - see performSelector:
 */
- (id) performSelector:(SEL)theSelector withObject:(id)theObject
{
	if ([super respondsToSelector:theSelector]) return [super performSelector:theSelector withObject:theObject];

	TableDocument *frontDocument = [[tabView selectedTabViewItem] identifier]; 
	if (![frontDocument respondsToSelector:theSelector]) [self doesNotRecognizeSelector:theSelector];

	return [frontDocument performSelector:theSelector withObject:theObject];
}

@end