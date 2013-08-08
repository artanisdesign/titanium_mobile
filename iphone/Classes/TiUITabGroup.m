/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
#ifdef USE_TI_UITAB

#import "TiUITabGroup.h"
#import "TiUITabProxy.h"
#import "TiUtils.h"
#import "TiColor.h"
#import "TiUITabController.h"
#import "TiWindowProxy.h"
#import "TiUITabGroupProxy.h"

@implementation TiUITabGroup

DEFINE_EXCEPTIONS

-(void)dealloc
{
	RELEASE_TO_NIL(controller);
	RELEASE_TO_NIL(focused);
	[super dealloc];
}

-(UITabBarController*)tabController
{
	if (controller==nil)
	{
		controller = [[UITabBarController alloc] init];
		controller.delegate = self;
	}
	return controller;
}

- (id)accessibilityElement
{
	return [self tabbar];
}

-(UITabBar*)tabbar
{
	return [self tabController].tabBar;
}

-(int)findIndexForTab:(TiProxy*)proxy
{
	if (proxy!=nil)
	{
		int index = 0;
		for (UINavigationController *tc in controller.viewControllers)
		{
			if (tc.delegate == (id)proxy)
			{
				return index;
			}
			index++;
		}
	}
	return -1;
}

-(void)layoutSubviews
{
	[super layoutSubviews];
	UIView *view = [self tabController].view;
	[view setTransform:CGAffineTransformIdentity];
	[view setFrame:[self bounds]];
}

#pragma mark Dispatching focus change

- (void)handleWillShowTab:(TiUITabProxy *)newFocus
{
    if (focused != newFocus) {
        [focused handleWillBlur];
        [newFocus handleWillFocus];
    }
}

- (void)handleDidShowTab:(TiUITabProxy *)newFocus
{
    // Do nothing if no tabs are being focused or blurred (or the window is opening)
    if ((focused == nil && newFocus == nil) || (focused == newFocus)) {
        //TIMOB-10796. Ensure activeTab is set to focused on early return
        if (focused != nil) {
            [self.proxy replaceValue:focused forKey:@"activeTab" notification:NO];
        }
        return;
    }
    
	NSMutableDictionary * event = [NSMutableDictionary dictionaryWithCapacity:4];

	NSArray * tabArray = [controller viewControllers];

	int previousIndex = -1;
	int index = -1;

	if (focused != nil)
	{
		[event setObject:focused forKey:@"previousTab"];
		previousIndex = [tabArray indexOfObject:[(TiUITabProxy *)focused controller]];
	}
	
	if (newFocus != nil)
	{
		[event setObject:newFocus forKey:@"tab"];
		index = [tabArray indexOfObject:[(TiUITabProxy *)newFocus controller]];
	}

	[event setObject:NUMINT(previousIndex) forKey:@"previousIndex"];
	[event setObject:NUMINT(index) forKey:@"index"];

	[self.proxy fireEvent:@"blur" withObject:event];
	[focused handleDidBlur:event];
    [focused replaceValue:[NSNumber numberWithBool:NO] forKey:@"active" notification:NO];
	
	RELEASE_TO_NIL(focused);
	focused = [newFocus retain];
	[self.proxy replaceValue:focused forKey:@"activeTab" notification:NO];
    [focused replaceValue:[NSNumber numberWithBool:YES] forKey:@"active" notification:NO];

    // If we're in the middle of opening, the focus happens once the tabgroup is opened
    if (![(TiWindowProxyNeue*)[self proxy] opening]) {
        [self.proxy fireEvent:@"focus" withObject:event];
    }
	[focused handleDidFocus:event];
}


#pragma mark More tab delegate


-(void)updateMoreBar:(UINavigationController *)moreController
{
	if ([[moreController viewControllers] count] != 1)
	{
		return;
	}
	
	[TiUtils applyColor:barColor toNavigationController:moreController];
}

-(void)setEditButton:(UINavigationController*)moreController
{
	if ([[moreController viewControllers] count] == 1) {
		UINavigationBar* navBar = [moreController navigationBar];
		UINavigationItem* navItem = [navBar topItem];
		UIBarButtonItem* editButton = [navItem rightBarButtonItem];
		if (editTitle != nil) {
			editButton.title = editTitle;
		}
		else {
			// TODO: Need to get the localized value here
			editButton.title = @"Edit";
		}
	}
}

-(void)removeEditButton:(UINavigationController*)moreController
{
	if ([[moreController viewControllers] count] == 1) {
		UINavigationBar* navBar = [moreController navigationBar];
		UINavigationItem* navItem = [navBar topItem];
		[navItem setRightBarButtonItem:nil];
	}
}

-(void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated	
{
    NSArray * moreViewControllerStack = [navigationController viewControllers];
    int stackHeight = [moreViewControllerStack count];
    if (stackHeight > 1) {
        UIViewController * rootController = [moreViewControllerStack objectAtIndex:1];
        if ([rootController respondsToSelector:@selector(proxy)]) {
            id theProxy = [(id)rootController proxy];
            if ([theProxy conformsToProtocol:@protocol(TiWindowProtocol)] ) {
                TiUITabProxy * tabProxy = (TiUITabProxy *)[(id)theProxy tab];
                [tabProxy handleWillShowViewController:viewController animated:animated];
            } else {
                DebugLog(@"[ERROR] The view controller is not hosting a window proxy. Can not find tab.");
            }
        } else {
            DebugLog(@"[ERROR] The view controller does not respond to selector proxy. Can not find window");
        }
    } else {
        [self handleWillShowTab:nil];
        [self updateMoreBar:navigationController];
        if (allowConfiguration) {
            [self setEditButton:navigationController];
        }
        // However, under iOS4, we have to manage the appearance/disappearance of the edit button ourselves.
        else {
            [self removeEditButton:navigationController];
        }
    }
}


- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    NSArray * moreViewControllerStack = [navigationController viewControllers];
    int stackHeight = [moreViewControllerStack count];
    if (stackHeight < 2) { //No more faux roots.
        if (focused != nil) {
            [self handleDidShowTab:nil];
        }
        return;
    }

    UIViewController * rootController = [moreViewControllerStack objectAtIndex:1];
    TiUITabProxy * tabProxy = nil;
    if ([rootController respondsToSelector:@selector(proxy)]) {
        id theProxy = [(id)rootController proxy];
        if ([theProxy conformsToProtocol:@protocol(TiWindowProtocol)] ) {
            tabProxy = (TiUITabProxy *)[(id)theProxy tab];
        } else {
            DebugLog(@"[ERROR] The view controller is not hosting a window proxy. Can not find tab.");
            return;
        }
    } else {
        DebugLog(@"[ERROR] The view controller does not respond to selector proxy. Can not find window");
        return;
    }

    if (stackHeight == 2) {	//One for the picker, one for the faux root.
        if (tabProxy != focused) {
            [self handleDidShowTab:tabProxy];
        }
    }

    [tabProxy handleDidShowViewController:viewController animated:animated];
}

#pragma mark TabBarController Delegates

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    TiUITabProxy * target=nil;
    if ([tabBarController moreNavigationController] == viewController) {
        NSArray * moreViewControllerStack = [(UINavigationController *)viewController viewControllers];
        if ([moreViewControllerStack count]>1) {
            UIViewController * rootController = [moreViewControllerStack objectAtIndex:1];
            if ([rootController respondsToSelector:@selector(proxy)]) {
                id theProxy = [(id)rootController proxy];
                if ([theProxy conformsToProtocol:@protocol(TiWindowProtocol)] ) {
                    target = (TiUITabProxy *)[(id)theProxy tab];
                } else {
                    DebugLog(@"[ERROR] The view controller is not hosting a window proxy. Can not find tab.");
                }
            } else {
                DebugLog(@"[ERROR] The view controller does not respond to selector proxy. Can not find window");
            }
		}
	}
	else
	{
		target = (TiUITabProxy *)[(UINavigationController *)viewController delegate];
	}

	[self handleWillShowTab:target];

	return YES;
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController
{
	if ([tabBarController moreNavigationController] == viewController)
	{
		if (self != [(UINavigationController *)viewController delegate])
		{
			[(UINavigationController *)viewController setDelegate:self];
		}
		NSArray * moreViewControllerStack = [(UINavigationController *)viewController viewControllers];
		int stackCount = [moreViewControllerStack count];
		if (stackCount>1)
		{
			viewController = [moreViewControllerStack objectAtIndex:1];
		}
		else
		{
			[self updateMoreBar:(UINavigationController *)viewController];
			viewController = nil;
		}

	}

	[self handleDidShowTab:(TiUITabProxy *)[(UINavigationController *)viewController delegate]];
}


- (void)tabBarController:(UITabBarController *)tabBarController didEndCustomizingViewControllers:(NSArray *)viewControllers changed:(BOOL)changed
{
	if (changed) {
		NSMutableArray* tabProxies = [NSMutableArray arrayWithCapacity:[viewControllers count]];
		for (UINavigationController* controller_ in viewControllers) {
			id delegate = [controller_ delegate];
			if ([delegate isKindOfClass:[TiUITabProxy class]]) {
				TiUITabProxy* tabProxy = (TiUITabProxy*)delegate;
				[tabProxies addObject:tabProxy];
			}
		}
		
		// We do it this way to reset the 'tabs' array on the proxy without changing the active
		// controller.  The SDK documentation actually conflicts itself on whether or not the 'more' tab
		// can be manually reselected anyway.
		[(TiUITabGroupProxy*)[self proxy] _resetTabArray:tabProxies];
	}
}

-(void)setTabsBackgroundColor_:(id)value
{
	if (![TiUtils isIOS5OrGreater])
	{
		NSLog(@"[WARN] tabsBackgroundColor is only supported in iOS 5 or above.");
		return;
	}
	TiColor* color = [TiUtils colorValue:value];
	//A nil tintColor is fine, too.
	controller.tabBar.tintColor = color.color;
}

-(void)setTabsBackgroundImage_:(id)value
{
    if (![TiUtils isIOS5OrGreater]) {
		NSLog(@"[WARN] tabsBackgroundImage is only supported in iOS 5 or above.");
		return;
	}
	controller.tabBar.backgroundImage = [self loadImage:value];
}

-(void)setActiveTabBackgroundImage_:(id)value
{
    if (![TiUtils isIOS5OrGreater]) {
		NSLog(@"[WARN] activeTabBackgroundImage is only supported in iOS 5 or above.");
		return;
	}
	controller.tabBar.selectionIndicatorImage = [self loadImage:value];
}

-(void)setShadowImage_:(id)value
{
    if (![TiUtils isIOS6OrGreater]) {
		NSLog(@"[WARN] activeTabBackgroundImage is only supported in iOS 6 or above.");
		return;
	}
	//Because we still support XCode 4.3, we cannot use the shadowImage property
	[controller.tabBar setShadowImage:[self loadImage:value]];
}

-(void) setActiveTabIconTint_:(id)value
{
	if (![TiUtils isIOS5OrGreater])
	{
		NSLog(@"[WARN] activeTabIconTint is only supported in iOS 5 or above.");
		return;
	}
	TiColor* color = [TiUtils colorValue:value];
	//A nil tintColor is fine, too.
	controller.tabBar.selectedImageTintColor = color.color;
}

#pragma mark Public APIs

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[controller willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
}


-(void)setBarColor_:(id)value
{
	[barColor release];
	barColor = [[TiUtils colorValue:value] retain];
	[self updateMoreBar:[controller moreNavigationController]];
}

-(void)setActiveTab_:(id)value
{
	UIViewController *active = nil;
	
	if (controller == nil)
	{
		return;
	}
	if ([value isKindOfClass:[TiUITabProxy class]])
	{
		
		TiUITabProxy *tab = (TiUITabProxy*)value;
		for (UIViewController *c in [self tabController].viewControllers)
		{
			if ([[tab controller] isEqual:c])
			{
				active = c;
				break;
			}
		}
	}
	else if (value != nil)
	{
		int index = [TiUtils intValue:value];
		if (index >= 0 && index < [[self tabController].viewControllers count])
		{
			active = [[self tabController].viewControllers objectAtIndex:index];
		}
	}
	if (active == nil && [self tabController].viewControllers.count > 0)  {
		active = [self tabController].selectedViewController;
	}
	if (active == nil)  {
		DebugLog(@"setActiveTab called but active view controller could not be determined");
	}
	else {
		[self tabController].selectedViewController = active;
	}
	[self tabBarController:[self tabController] didSelectViewController:active];
}

-(void)setAllowUserCustomization_:(id)value
{
	allowConfiguration = [TiUtils boolValue:value def:YES];
	if (allowConfiguration) {
		[self tabController].customizableViewControllers = [self tabController].viewControllers;
		[self setEditButton:[controller moreNavigationController]];
	}
	else {
		[self tabController].customizableViewControllers = nil;
		[self removeEditButton:[controller moreNavigationController]];
	}
}

-(void)setEditButtonTitle_:(id)value
{
	editTitle = [TiUtils stringValue:value];
	[self setEditButton:[controller moreNavigationController]];
}

-(void)setTabs_:(id)tabs
{
    ENSURE_TYPE_OR_NIL(tabs,NSArray);

    if (tabs!=nil && [tabs count] > 0) {
        NSMutableArray *controllers = [[NSMutableArray alloc] init];
        id thisTab = [[self proxy] valueForKey:@"activeTab"];
        
        TiUITabProxy *theActiveTab = nil;
        
        if (thisTab != nil && thisTab != [NSNull null]) {
            if (![thisTab isKindOfClass:[TiUITabProxy class]]) {
                int index = [TiUtils intValue:thisTab];
                if (index < [tabs count]) {
                    theActiveTab = [tabs objectAtIndex:index];
                }
            }
            else {
                if ([tabs containsObject:thisTab]) {
                    theActiveTab = thisTab;
                }
            }
        }
		
        for (TiUITabProxy *tabProxy in tabs) {
            [controllers addObject:[tabProxy controller]];
            if ([TiUtils boolValue:[tabProxy valueForKey:@"active"]]) {
                RELEASE_TO_NIL(focused);
                focused = [tabProxy retain];
            }
        }
        
        if (theActiveTab != nil && focused != theActiveTab) {
            RELEASE_TO_NIL(focused);
            focused = [theActiveTab retain];
        }

        [self tabController].viewControllers = nil;
        [self tabController].viewControllers = controllers;
        if ( focused != nil && ![tabs containsObject:focused]) {
            if (theActiveTab != nil) {
                [self setActiveTab_:theActiveTab];
            }
            else {
                DebugLog(@"[WARN] ActiveTab property points to tab not in list. Ignoring");
                RELEASE_TO_NIL(focused);
            }
        }

        [controllers release];
    }
    else {
        RELEASE_TO_NIL(focused);
        [self tabController].viewControllers = nil;
    }

    [self.proxy	replaceValue:focused forKey:@"activeTab" notification:YES];
    [self setAllowUserCustomization_:[NSNumber numberWithBool:allowConfiguration]];
}

-(void)open:(id)args
{
	UIView *view = [self tabController].view;
	[view setFrame:[self bounds]];
	[self addSubview:view];

	// on an open, make sure we send the focus event to focused tab
    NSArray * tabArray = [controller viewControllers];
    int index = 0;
    if (focused != nil)
	{
		index = [tabArray indexOfObject:[(TiUITabProxy *)focused controller]];
	}
	NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:focused,@"tab",NUMINT(index),@"index",NUMINT(-1),@"previousIndex",[NSNull null],@"previousTab",nil];
	[self.proxy fireEvent:@"focus" withObject:event];
    
    // Tab has already been focused by the tab controller delegate
	//[focused handleDidFocus:event];
}

-(void)close:(id)args
{
	if (controller!=nil)
	{
		controller.viewControllers = nil;
	}
	RELEASE_TO_NIL(controller);
}


-(void)focusVisibleWindow
{
    //DEAD CODE. FOCUS NOW HANDLED THROUGH APPEARANCE METHODS OF TiViewControllerNeue
    /*
	UINavigationController * ourCurrentNC = (UINavigationController *)[controller selectedViewController];
	TiUITabController * ourCurrentVC = (TiUITabController *)[ourCurrentNC visibleViewController];
	if([ourCurrentVC isKindOfClass:[TiUITabController class]])
	{
		TiWindowProxy * ourCurrentWindow = [ourCurrentVC window];
		[ourCurrentWindow _tabFocus];
	}
    */
}

-(void)blurVisibleWindow
{
    //DEAD CODE. BLUR NOW HANDLED THROUGH APPEARANCE METHODS OF TiViewControllerNeue
    /*
	UINavigationController * ourCurrentNC = (UINavigationController *)[controller selectedViewController];
	TiUITabController * ourCurrentVC = (TiUITabController *)[ourCurrentNC visibleViewController];
	if([ourCurrentVC isKindOfClass:[TiUITabController class]])
	{
		TiWindowProxy * ourCurrentWindow = [ourCurrentVC window];
		[ourCurrentWindow _tabBlur];
	}
     */
}

@end

#endif