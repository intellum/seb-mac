//
//  BrowserWindowController.m
//  SafeExamBrowser
//
//  Created by Daniel Schneider on 17.01.12.
//  Copyright (c) 2010-2017 Daniel R. Schneider, ETH Zurich, 
//  Educational Development and Technology (LET), 
//  based on the original idea of Safe Exam Browser 
//  by Stefan Schneider, University of Giessen
//  Project concept: Thomas Piendl, Daniel R. Schneider, 
//  Dirk Bauer, Kai Reuter, Tobias Halbherr, Karsten Burger, Marco Lehre, 
//  Brigitte Schmucki, Oliver Rahs. French localization: Nicolas Dunand
//
//  ``The contents of this file are subject to the Mozilla Public License
//  Version 1.1 (the "License"); you may not use this file except in
//  compliance with the License. You may obtain a copy of the License at
//  http://www.mozilla.org/MPL/
//  
//  Software distributed under the License is distributed on an "AS IS"
//  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
//  License for the specific language governing rights and limitations
//  under the License.
//  
//  The Original Code is Safe Exam Browser for Mac OS X.
//  
//  The Initial Developer of the Original Code is Daniel R. Schneider.
//  Portions created by Daniel R. Schneider are Copyright 
//  (c) 2010-2017 Daniel R. Schneider, ETH Zurich, Educational Development
//  and Technology (LET), based on the original idea of Safe Exam Browser 
//  by Stefan Schneider, University of Giessen. All Rights Reserved.
//  
//  Contributor(s): ______________________________________.
//

#import "SEBBrowserWindowController.h"
#import "MyGlobals.h"
#import <WebKit/WebKit.h>
#import "SEBBrowserWindow.h"
#import "NSScreen+SEBScreen.h"
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <unistd.h>
#include "CGSPrivate.h"


WindowRef FrontWindow();
void DisposeWindow (
                    WindowRef window
                    );


@implementation SEBBrowserWindowController

@synthesize webView;
@synthesize frameForNonFullScreenMode;


- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
        [self setShouldCascadeWindows:NO];
    }
    
    return self;
}


#pragma mark Delegates

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    SEBBrowserWindow *browserWindow = (SEBBrowserWindow *)self.window;
    
    // Set the reference to the browser controller in the browser window instance
    browserWindow.browserController = _browserController;

    [browserWindow setCalculatedFrame];
    self.browserController.activeBrowserWindow = (SEBBrowserWindow *)self.window;
    _previousScreen = self.window.screen;
}


- (void)windowDidBecomeMain:(NSNotification *)notification
{
    DDLogDebug(@"BrowserWindow %@ did become main", self.window);
    if (self.browserController.reinforceKioskModeRequested) {
        self.browserController.reinforceKioskModeRequested = NO;
        [[NSNotificationCenter defaultCenter]
         postNotificationName:@"requestReinforceKioskMode" object:self];
    }
    self.browserController.activeBrowserWindow = (SEBBrowserWindow *)self.window;
    [self.browserController setStateForWindow:(SEBBrowserWindow *)self.window withWebView:self.webView];
    
    // If this is the main browser window, check if it's still on the same screen as when the dock was opened
    if (self.window == self.browserController.mainBrowserWindow) {
        if (self.window.screen != self.browserController.dockController.window.screen) {
            // Post a notification that the main screen changed
            [[NSNotificationCenter defaultCenter]
             postNotificationName:@"mainScreenChanged" object:self];
        }
    }
}


- (void)windowDidBecomeKey:(NSNotification *)notification
{
    self.browserController.activeBrowserWindow = (SEBBrowserWindow *)self.window;
    DDLogDebug(@"BrowserWindow %@ did become key", self.window);
}


- (void)windowDidResignKey:(NSNotification *)notification
{
    DDLogDebug(@"BrowserWindow %@ did resign key", self.window);
    
    NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
    DDLogDebug(@"Current key window: %@", keyWindow);
    if (keyWindow) {
        if (keyWindow.isModalPanel) {
            DDLogWarn(@"Current key window is modal panel: %@", keyWindow);
        }
        if (keyWindow.isFloatingPanel) {
            DDLogWarn(@"Current key window is floating panel: %@", keyWindow);
        }
        if (keyWindow.isSheet) {
            DDLogWarn(@"Current key window is sheet: %@", keyWindow);
        }
    }
}


- (void)windowWillMove:(NSNotification *)notification
{
    DDLogDebug(@"BrowserWindow %@ will move", self.window);
    [self startWindowWatcher];
}


- (void)windowDidMove:(NSNotification *)notification
{
    DDLogDebug(@"BrowserWindow %@ did move", self.window);
    dragStarted = false;
}


- (void)windowWillClose:(NSNotification *)notification
{
    DDLogDebug(@"BrowserWindow %@ will close", self.window);
    
    if (_windowWatchTimer) {
        [_windowWatchTimer invalidate];
        _windowWatchTimer = nil;
    }
    self.window = nil;
    _browserController.activeBrowserWindow = nil;
}


// Start the windows watcher if it's not yet running
- (void)startWindowWatcher
{
#ifdef DEBUG
    DDLogDebug(@"%s", __FUNCTION__);
#endif
    
    if (!_windowWatchTimer) {
        NSDate *dateNow = [NSDate date];
        
        _windowWatchTimer = [[NSTimer alloc] initWithFireDate:dateNow
                                                     interval: 0.05
                                                       target: self
                                                     selector:@selector(windowScreenWatcher)
                                                     userInfo:nil repeats:YES];
        
        NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
        
        [currentRunLoop addTimer:_windowWatchTimer forMode: NSRunLoopCommonModes];
    }
}


// Start the windows watcher if it's not yet running
- (void)stopWindowWatcher
{
#ifdef DEBUG
    DDLogDebug(@"%s on thread %@", __FUNCTION__, [NSThread currentThread]);
#endif
    
    if (_windowWatchTimer) {
        [_windowWatchTimer invalidate];
        _windowWatchTimer = nil;
    }
    [self updateCoveringIntersectingInactiveScreens];
    // If window is still intersecting inactive screens (which are covered therefore)
    // or if it is outside of any screen
#ifdef DEBUG
    DDLogDebug(@"%s number of inactive screen covering windows %lu", __FUNCTION__, (unsigned long)_browserController.sebController.inactiveScreenWindows.count);
    DDLogDebug(@"%s window is currently on screen %@", __FUNCTION__, self.window.screen);
#endif
    
    NSScreen *currentScreen = self.window.screen;
    // Check if window is off-screen or the new screen is inactive
    if (!currentScreen || currentScreen.inactive) {
        // Yes: Move the window back to the screen it has been on before
        currentScreen = _previousScreen;
#ifdef DEBUG
        DDLogDebug(@"Screen is inactive, move window back to previous screen %@", currentScreen);
#endif
    }

    // Move the window back to the screen is has been on previously
    [self adjustWindowForScreen:currentScreen moveBack:(_browserController.sebController.inactiveScreenWindows.count > 0)];
    dragStarted = false;
    [self updateCoveringIntersectingInactiveScreens];
}


- (void)windowScreenWatcher
{
    [self updateCoveringIntersectingInactiveScreens];

    NSUInteger pressedButtons = [NSEvent pressedMouseButtons];
    if ((pressedButtons & (1 << 0)) != (1 << 0)) {
        [self stopWindowWatcher];
#ifdef DEBUG
    } else {
        DDLogDebug(@"windowScreenWatcher called");
#endif
    }
}


- (void)updateCoveringIntersectingInactiveScreens
{
    NSPoint cursorPosition = [NSEvent mouseLocation];
    
    if (!dragStarted) {
        dragStarted = true;
        // Save mouse position when starting dragging
        dragCursorStartPosition = cursorPosition;
    }
    NSRect actualWindowFrame = [self actualWindowFrame];
    
    // Get screens which the window frame intersects
    NSArray *allScreens = [NSScreen screens];
    NSMutableArray *intersectingScreens = [NSMutableArray new];
    NSUInteger allIntersectingScreens = 0;
    for (NSScreen *screen in allScreens) {
        if (CGRectIntersectsRect(actualWindowFrame, screen.frame)) {
            allIntersectingScreens++;
            if (screen.inactive) {
                [intersectingScreens addObject:screen];
            }
        }
    }
    
    if (allIntersectingScreens == 0) {
        resetWindowPosition = true;
    }
    
#ifdef DEBUG
    DDLogDebug(@"Window is on %lu screen(s), %lu inactive screen(s) and has frame %@ and actual frame %@", (unsigned long)allIntersectingScreens, (unsigned long)intersectingScreens.count, CGRectCreateDictionaryRepresentation(self.window.frame), CGRectCreateDictionaryRepresentation(actualWindowFrame));
#endif

    // Cover currently intersected inactive screens and
    // remove cover windows of no longer intersected screens
    [_browserController.sebController coverInactiveScreens:[intersectingScreens copy]];
    
}


- (NSRect)actualWindowFrame
{
    NSRect windowFrame = self.window.frame;

    if (!dragStarted) {
        // If the Window isn't being dragged, we can return the unmodified frame
        return windowFrame;
    }
    
    NSPoint cursorPosition = [NSEvent mouseLocation];
    
    NSPoint cursorDisplacement = NSMakePoint(cursorPosition.x - dragCursorStartPosition.x, cursorPosition.y - dragCursorStartPosition.y);
    NSRect actualWindowFrame = NSMakeRect(windowFrame.origin.x + cursorDisplacement.x,
                                          windowFrame.origin.y + cursorDisplacement.y,
                                          windowFrame.size.width,
                                          windowFrame.size.height);
    return actualWindowFrame;
}


- (void)windowDidChangeScreen:(NSNotification *)notification
{
    NSScreen *currentScreen = self.window.screen;
    BOOL movingWindowBack = false;
    DDLogDebug(@"windowDidChangeScreen to %@", currentScreen);
    // Check if window is off-screen or the new screen is inactive
    if (currentScreen.inactive) {
        // Yes: Move the window back to the screen it has been on before
        currentScreen = _previousScreen;
        movingWindowBack = true;
        DDLogDebug(@"Screen is inactive, move window back to previous screen %@", currentScreen);
    }
    [self adjustWindowForScreen:currentScreen moveBack:movingWindowBack];
}


- (void)adjustWindowForScreen:(NSScreen *)newScreen moveBack:(BOOL)movingWindowBack
{
    DDLogDebug(@"%s screen: %@ moveBack: %hhd", __FUNCTION__, newScreen, movingWindowBack);
    NSUInteger pressedButtons = [NSEvent pressedMouseButtons];
    if (((pressedButtons & (1 << 0)) != (1 << 0))) {
        
        if (newScreen && !newScreen.inactive) {
            _previousScreen = newScreen;
        }
        
        if (!newScreen) {
             newScreen = _previousScreen;
        }
        
        if (resetWindowPosition) {
            resetWindowPosition = false;
            movingWindowBack = true;
            DDLogDebug(@"Window was moved off-screen, reset position.");
        }
        
        // Check if Window is too high for the new screen
        // Get frame of the usable screen (considering if menu bar or SEB dock is enabled)
        NSRect newFrame = [_browserController visibleFrameForScreen:newScreen];
        
        if (movingWindowBack) {
            NSRect recalculatedFrame = NSMakeRect(newFrame.origin.x, newFrame.origin.y, self.window.frame.size.width, newFrame.size.height);
            [self.window setFrame:recalculatedFrame display:YES animate:YES];
            DDLogDebug(@"Moved browser window back to previous screen, frame: %@", CGRectCreateDictionaryRepresentation(recalculatedFrame));
//            [self.window setIsZoomed:YES];
            [self.window zoom:self];
            DDLogDebug(@"Performed zoom: on window, new frame is %@.", CGRectCreateDictionaryRepresentation(self.window.frame));
            
        } else {
            NSRect oldWindowFrame = self.window.frame;
            DDLogDebug(@"window.frame: %@", CGRectCreateDictionaryRepresentation(oldWindowFrame));
            NSRect actualWindowFrame = [self actualWindowFrame];
            DDLogDebug(@"Actual window frame: %@", CGRectCreateDictionaryRepresentation(actualWindowFrame));
            NSRect newWindowFrame = oldWindowFrame;
            if (oldWindowFrame.size.height > newFrame.size.height) {
                newWindowFrame = NSMakeRect(oldWindowFrame.origin.x, newFrame.origin.y, oldWindowFrame.size.width, newFrame.size.height);
                oldWindowFrame = newWindowFrame;
            }
            if (oldWindowFrame.size.width > newFrame.size.width) {
                newWindowFrame = NSMakeRect(newFrame.origin.x, oldWindowFrame.origin.y, newFrame.size.width, oldWindowFrame.size.height);
            }
            // Check if top of window is hidden below the dock (if visible)
            // or just slightly (20 points) above the bottom edge of the visible screen space
            DDLogDebug(@"Checking if window (frame: %@) is hidden below the dock (if enabled) or just slightly above the bottom edge of the visible screen space.", CGRectCreateDictionaryRepresentation(newWindowFrame));
            if ((newWindowFrame.origin.y + newWindowFrame.size.height) < (newFrame.origin.y + kMenuBarHeight) ||
                (actualWindowFrame.origin.y + actualWindowFrame.size.height) < (newFrame.origin.y + kMenuBarHeight) ||
                actualWindowFrame.origin.y > (newFrame.origin.y + newFrame.size.height - kMenuBarHeight - 4)) { //showDock * dockHeight +
                // In this case shift the window up
                newWindowFrame = NSMakeRect(newWindowFrame.origin.x, newFrame.origin.y, newWindowFrame.size.width, newWindowFrame.size.height);
                DDLogDebug(@"Window was hidden below the dock (if enabled) or just slightly above the bottom edge of the visible screen space, change its frame to %@.", CGRectCreateDictionaryRepresentation(newWindowFrame));
            }
            
            [self.window setFrame:newWindowFrame display:YES animate:YES];
            DDLogDebug(@"Adjusted window frame for new screen to: %@", CGRectCreateDictionaryRepresentation(newWindowFrame));
            
            [self.window zoom:self];
            DDLogDebug(@"Performed zoom: on window, new frame is %@.", CGRectCreateDictionaryRepresentation(self.window.frame));
        }
        
        // If this is the main browser window, check if it's still on the same screen as when the dock was opened
        if (!movingWindowBack && self.window == self.browserController.mainBrowserWindow) {
            // Post a notification that the main screen changed
            [[NSNotificationCenter defaultCenter]
             postNotificationName:@"mainScreenChanged" object:self];
        }
    }
}


- (BOOL)shouldCloseDocument
{
    return YES;
}


// Overriding this method without calling super in OS X 10.7 Lion
// prevents the windows' position and size to be restored on restarting the app
- (void)restoreStateWithCoder:(NSCoder *)coder
{
    DDLogDebug(@"BrowserWindowController %@: Prevented windows' position and size to be restored!", self);
    return;
}


- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
    // Check data source of web view
    if (![[[self webView] mainFrame] dataSource]) {
        NSString* appTitleString = [[MyGlobals sharedMyGlobals] infoValueForKey:@"CFBundleShortVersionString"];
        appTitleString = [NSString stringWithFormat:@"Safe Exam Browser %@", appTitleString];
        DDLogInfo(@"BrowserWindow %@: Title of current Page: %@", self.window, appTitleString);
        return appTitleString;
    }
    return @"";
}


- (IBAction) backForward: (id)sender
{
    if ([sender selectedSegment] == 0) {
        [self.webView goBack:self];
    } else {
        [self.webView goForward:self];
    }
}


- (IBAction) zoomText: (id)sender
{
    if ([sender selectedSegment] == 0) {
        [self.webView makeTextSmaller:self];
    } else {
        [self.webView makeTextLarger:self];
    }
}


- (IBAction) zoomPage: (id)sender
{
    if ([sender selectedSegment] == 0) {
        SEL selector = NSSelectorFromString(@"zoomPageOut:");
        [[NSApplication sharedApplication] sendAction:selector to:self.webView from:self];
    } else {
        SEL selector = NSSelectorFromString(@"zoomPageIn:");
        [[NSApplication sharedApplication] sendAction:selector to:self.webView from:self];
    }
}

@end
