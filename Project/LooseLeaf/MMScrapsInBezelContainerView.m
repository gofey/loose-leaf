//
//  MMScapBubbleContainerView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/31/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "MMScrapsInBezelContainerView.h"
#import "MMScrapBubbleButton.h"
#import "NSThread+BlockAdditions.h"
#import "MMScrapSidebarContentView.h"
#import "MMScrapsInSidebarState.h"
#import "MMImmutableScrapsOnPaperState.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "NSFileManager+DirectoryOptimizations.h"
#import "MMRotationManager.h"
#import "UIView+Debug.h"
#import "MMImmutableScrapsInSidebarState.h"

#define kMaxScrapsInBezel 6

@interface MMSidebarButtonTapGestureRecognizer : UITapGestureRecognizer

@end

@implementation MMSidebarButtonTapGestureRecognizer

-(BOOL) canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer{
    return NO;
}

@end



@implementation MMScrapsInBezelContainerView{
    CGFloat lastRotationReading;
    CGFloat targetAlpha;
    NSMutableDictionary* bubbleForScrap;
    MMCountBubbleButton* countButton;
    MMScrapSidebarContentView* contentView;
    MMScrapsInSidebarState* scrapState;
    NSString* scrapIDsPath;
    
    NSMutableDictionary* rotationAdjustments;
}

@synthesize bubbleDelegate;
@synthesize countButton;
@synthesize scrapState;

-(id) initWithFrame:(CGRect)frame andCountButton:(MMCountBubbleButton *)_countButton{
    if(self = [super initWithFrame:frame forButton:_countButton animateFromLeft:NO]){
        targetAlpha = 1;
        bubbleForScrap = [NSMutableDictionary dictionary];
        
        contentView = [[MMScrapSidebarContentView alloc] initWithFrame:[sidebarContentView contentBounds]];
        contentView.delegate = self;
        [sidebarContentView addSubview:contentView];

        countButton = _countButton;
        countButton.delegate = self;
        [countButton addTarget:self action:@selector(countButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

        
        NSDictionary* loadedRotationValues = [NSDictionary dictionaryWithContentsOfFile:[MMScrapsInBezelContainerView pathToPlist]];
        rotationAdjustments = [NSMutableDictionary dictionary];
        if(loadedRotationValues){
            [rotationAdjustments addEntriesFromDictionary:loadedRotationValues];
        }

        scrapState = [[MMScrapsInSidebarState alloc] initWithDelegate:self];
    }
    return self;
}

-(int) fullByteSize{
    return [super fullByteSize] + scrapState.fullByteSize;
}

-(NSArray*) scrapsInSidebar{
    return [scrapState.allScrapsInSidebar copy];
}


#pragma mark - Helper Methods

-(NSString*) scrapIDsPath{
    if(!scrapIDsPath){
        NSString* documentsPath = [NSFileManager documentsPath];
        NSString* pagesPath = [documentsPath stringByAppendingPathComponent:@"Bezel"];
        [NSFileManager ensureDirectoryExistsAtPath:pagesPath];
        scrapIDsPath = [[pagesPath stringByAppendingPathComponent:@"scrapIDs"] stringByAppendingPathExtension:@"plist"];
    }
    return scrapIDsPath;
}

-(CGPoint) centerForBubbleAtIndex:(NSInteger)index{
    CGFloat rightBezelSide = self.bounds.size.width - 100;
    // midpoint calculates for 6 buttons
    CGFloat midPointY = (self.bounds.size.height - 6*80) / 2;
    CGPoint ret = CGPointMake(rightBezelSide + 40, midPointY + 40);
    ret.y += 80 * index;
    return ret;
}

-(CGFloat) alpha{
    return targetAlpha;
}

-(void) setAlpha:(CGFloat)alpha{
    targetAlpha = alpha;
    if([scrapState.allScrapsInSidebar count] > kMaxScrapsInBezel){
        countButton.alpha = targetAlpha;
    }else{
        countButton.alpha = 0;
        for(UIView* subview in self.subviews){
            if([subview isKindOfClass:[MMScrapBubbleButton class]]){
                subview.alpha = targetAlpha;
            }
        }
    }
    if(!targetAlpha){
        [self sidebarCloseButtonWasTapped];
    }
}


#pragma mark - Scrap Animations

-(void) addScrapToBezelSidebar:(MMScrapView *)scrap animated:(BOOL)animated{
    
    // make sure we've saved its current state
    if(animated){
        // only save when it's animated. non-animated is loading
        // from disk at start up
        [scrap saveScrapToDisk:nil];
        [scrapState scrapIsAddedToSidebar:scrap];
    }
    
    // exit the scrap to the bezel!
    CGPoint center = [self centerForBubbleAtIndex:0];
    
    // prep the animation by creating the new bubble for the scrap
    // and initializing it's probable location (may change if count > 6)
    // and set it's alpha/rotation/scale to prepare for the animation
    MMScrapBubbleButton* bubble = [[MMScrapBubbleButton alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
    bubble.center = center;
    bubble.delegate = self;
    
    //
    // iOS7 changes how buttons can be tapped during a gesture (i think).
    // so adding our gesture recognizer explicitly, and disallowing it to
    // be prevented ensures that buttons can be tapped while other gestures
    // are in flight.
//    [bubble addTarget:self action:@selector(bubbleTapped:) forControlEvents:UIControlEventTouchUpInside];
    UITapGestureRecognizer* tappy = [[MMSidebarButtonTapGestureRecognizer alloc] initWithTarget:self action:@selector(bubbleTapped:)];
    [bubble addGestureRecognizer:tappy];
    bubble.originalScrapScale = scrap.scale;
    [self insertSubview:bubble atIndex:0];
    [self insertSubview:scrap aboveSubview:bubble];
    // keep the scrap in the bezel container during the animation, then
    // push it into the bubble
    bubble.alpha = 0;
    bubble.rotation = lastRotationReading;
    bubble.scale = .9;
    [bubbleForScrap setObject:bubble forKey:scrap.uuid];
    
    
    //
    // unload the scrap state, so that it shows the
    // image preview instead of an editable state
    [scrap unloadState];

    
    if(animated){
        CGFloat animationDuration = 0.5;
        
        if([scrapState.allScrapsInSidebar count] <= kMaxScrapsInBezel){
            // allow adding to 6 in the sidebar, otherwise
            // we need to pull them all into 1 button w/
            // a menu
            
            [self.bubbleDelegate willAddScrapToBezelSidebar:scrap];
            
            [UIView animateWithDuration:animationDuration * .51 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                // animate the scrap into position
                bubble.alpha = 1;
                scrap.transform = CGAffineTransformConcat([MMScrapBubbleButton idealTransformForScrap:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
                scrap.center = bubble.center;
                for(MMScrapBubbleButton* otherBubble in self.subviews){
                    if(otherBubble != bubble){
                        if([otherBubble isKindOfClass:[MMScrapBubbleButton class]]){
                            int index = (int) [scrapState.allScrapsInSidebar indexOfObject:otherBubble.scrap];
                            otherBubble.center = [self centerForBubbleAtIndex:index];
                        }
                    }
                }

            } completion:^(BOOL finished){
                // add it to the bubble and bounce
                bubble.scrap = scrap;
                [rotationAdjustments setObject:@(bubble.rotationAdjustment) forKey:scrap.uuid];
                [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    // scrap "hits" the bubble and pushes it down a bit
                    bubble.scale = .8;
                    bubble.alpha = targetAlpha;
                } completion:^(BOOL finished){
                    [countButton setCount:[scrapState.allScrapsInSidebar count]];
                    [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                        // bounce back
                        bubble.scale = 1.1;
                    } completion:^(BOOL finished){
                        [UIView animateWithDuration:animationDuration * .16 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            // and done
                            bubble.scale = 1.0;
                        } completion:^(BOOL finished){
                            [self.bubbleDelegate didAddScrapToBezelSidebar:scrap];
                        }];
                    }];
                }];
            }];
        }else if([scrapState.allScrapsInSidebar count] > kMaxScrapsInBezel){
            // we need to merge all the bubbles together into
            // a single button during the bezel animation
            [self.bubbleDelegate willAddScrapToBezelSidebar:scrap];
            [countButton setCount:[scrapState.allScrapsInSidebar count]];
            bubble.center = countButton.center;
            bubble.scale = 1;
            [UIView animateWithDuration:animationDuration * .51 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                // animate the scrap into position
                countButton.alpha = 1;
                for(MMScrapBubbleButton* bubble in self.subviews){
                    if([bubble isKindOfClass:[MMScrapBubbleButton class]]){
                        bubble.alpha = 0;
                        bubble.center = countButton.center;
                    }
                }
                scrap.transform = CGAffineTransformConcat([MMScrapBubbleButton idealTransformForScrap:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
                scrap.center = bubble.center;
            } completion:^(BOOL finished){
                // add it to the bubble and bounce
                bubble.scrap = scrap;
                [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    // scrap "hits" the bubble and pushes it down a bit
                    countButton.scale = .8;
                } completion:^(BOOL finished){
                    [countButton setCount:[scrapState.allScrapsInSidebar count]];
                    [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                        // bounce back
                        countButton.scale = 1.1;
                    } completion:^(BOOL finished){
                        [UIView animateWithDuration:animationDuration * .16 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            // and done
                            countButton.scale = 1.0;
                        } completion:^(BOOL finished){
                            [self.bubbleDelegate didAddScrapToBezelSidebar:scrap];
                        }];
                    }];
                }];
            }];
        }
    }else{
        if([scrapState.allScrapsInSidebar count] <= kMaxScrapsInBezel){
            bubble.alpha = 1;
            scrap.transform = CGAffineTransformConcat([MMScrapBubbleButton idealTransformForScrap:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
            scrap.center = bubble.center;
            bubble.scrap = scrap;
            for(MMScrapBubbleButton* anyBubble in self.subviews){
                if([anyBubble isKindOfClass:[MMScrapBubbleButton class]]){
                    int index = (int) [scrapState.allScrapsInSidebar indexOfObject:anyBubble.scrap];
                    anyBubble.center = [self centerForBubbleAtIndex:index];
                }
            }
        }else{
            [countButton setCount:[scrapState.allScrapsInSidebar count]];
            countButton.alpha = 1;
            for(MMScrapBubbleButton* bubble in self.subviews){
                if([bubble isKindOfClass:[MMScrapBubbleButton class]]){
                    bubble.alpha = 0;
                    bubble.center = countButton.center;
                }
            }
            scrap.transform = CGAffineTransformConcat([MMScrapBubbleButton idealTransformForScrap:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
            scrap.center = bubble.center;
            bubble.scrap = scrap;
        }
        [self saveScrapContainerToDisk];
    }
}

-(BOOL) containsScrap:(MMScrapView*)scrap{
    return [scrapState.allScrapsInSidebar containsObject:scrap];
}

-(BOOL) containsScrapUUID:(NSString *)scrapUUID{
    for(MMScrapView* scrap in scrapState.allScrapsInSidebar){
        if([scrap.uuid isEqualToString:scrapUUID]){
            return YES;
        }
    }
    return NO;
}


#pragma mark - Button Tap

-(void) bubbleTapped:(UITapGestureRecognizer*)gesture{
    MMScrapBubbleButton* bubble = (MMScrapBubbleButton*) gesture.view;
    if([scrapState.allScrapsInSidebar containsObject:bubble.scrap]){
        [scrapState scrapIsRemovedFromSidebar:bubble.scrap];
        
        MMScrapView* scrap = bubble.scrap;
        scrap.center = [self convertPoint:scrap.center fromView:scrap.superview];
        scrap.rotation += (bubble.rotation - bubble.rotationAdjustment);
        scrap.transform = CGAffineTransformConcat([MMScrapBubbleButton idealTransformForScrap:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
        [self insertSubview:scrap atIndex:0];
        
        [self animateAndAddScrapBackToPage:scrap withPreferredScrapProperties:nil];
        
        [bubbleForScrap removeObjectForKey:scrap.uuid];
        [rotationAdjustments removeObjectForKey:scrap.uuid];
    }
}

-(void) didTapOnScrapFromMenu:(MMScrapView*)scrap{
    [self didTapOnScrapFromMenu:scrap withPreferredScrapProperties:nil];
}

-(void) didTapOnScrapFromMenu:(MMScrapView*)scrap withPreferredScrapProperties:(NSDictionary*)properties{
    [scrapState scrapIsRemovedFromSidebar:scrap];
    
    scrap.center = [self convertPoint:scrap.center fromView:scrap.superview];
    [self insertSubview:scrap atIndex:0];
    
    [self sidebarCloseButtonWasTapped];
    [self animateAndAddScrapBackToPage:scrap withPreferredScrapProperties:properties];
    [countButton setCount:[scrapState.allScrapsInSidebar count]];
    
    [bubbleForScrap removeObjectForKey:scrap.uuid];
}

-(void) animateAndAddScrapBackToPage:(MMScrapView*)scrap withPreferredScrapProperties:(NSDictionary*)properties{
    MMScrapBubbleButton* bubble = [bubbleForScrap objectForKey:scrap.uuid];
    [scrap loadScrapStateAsynchronously:YES];
    
    scrap.scale = scrap.scale * [MMScrapBubbleButton idealScaleForScrap:scrap];
    
    BOOL hadProperties = properties != nil;
    
    if(!properties){
        CGPoint positionOnScreenToScaleTo = [self.bubbleDelegate positionOnScreenToScaleScrapTo:scrap];
        CGFloat scaleOnScreenToScaleTo = [self.bubbleDelegate scaleOnScreenToScaleScrapTo:scrap givenOriginalScale:bubble.originalScrapScale];
        NSMutableDictionary* mproperties = [NSMutableDictionary dictionary];
        [mproperties setObject:[NSNumber numberWithFloat:positionOnScreenToScaleTo.x] forKey:@"center.x"];
        [mproperties setObject:[NSNumber numberWithFloat:positionOnScreenToScaleTo.y] forKey:@"center.y"];
        [mproperties setObject:[NSNumber numberWithFloat:scrap.rotation] forKey:@"rotation"];
        [mproperties setObject:[NSNumber numberWithFloat:scaleOnScreenToScaleTo] forKey:@"scale"];
        properties = mproperties;
    }
    
    [self.bubbleDelegate willAddScrapBackToPage:scrap];
    [UIView animateWithDuration:.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [scrap setPropertiesDictionary:properties];
    } completion:^(BOOL finished){
        NSUInteger index = NSNotFound;
        if([properties objectForKey:@"subviewIndex"]){
            index = [[properties objectForKey:@"subviewIndex"] unsignedIntegerValue];
        }
        MMUndoablePaperView* page = [self.bubbleDelegate didAddScrapBackToPage:scrap atIndex:index];
        [scrap blockToFireWhenStateLoads:^{
            if(!hadProperties){
                NSLog(@"tapped on scrap from sidebar. should add undo item to page %@", page.uuid);
                [page addUndoItemForMostRecentAddedScrapFromBezelFromScrap:scrap];
            }else{
                NSLog(@"scrap added from undo item, don't add new undo item");
            }
        }];
    }];
    [UIView animateWithDuration:.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        bubble.alpha = 0;
        for(MMScrapBubbleButton* otherBubble in self.subviews){
            if(otherBubble != countButton && [otherBubble isKindOfClass:[MMScrapBubbleButton class]]){
                if(otherBubble != bubble){
                    int index = (int) [scrapState.allScrapsInSidebar indexOfObject:otherBubble.scrap];
                    otherBubble.center = [self centerForBubbleAtIndex:index];
                    if([scrapState.allScrapsInSidebar count] <= kMaxScrapsInBezel){
                        otherBubble.scrap = otherBubble.scrap; // reset it
                        otherBubble.alpha = 1;
                    }
                }
            }
        }
        if([scrapState.allScrapsInSidebar count] <= kMaxScrapsInBezel){
            countButton.alpha = 0;
        }
    } completion:^(BOOL finished){
        [bubble removeFromSuperview];
    }];
}


// count button was tapped,
// so show or hide the menu
// so the user can choose a scrap to add
-(void) countButtonTapped:(UIButton*)button{
    if(countButton.alpha){
        countButton.alpha = 0;
        [contentView prepareContentView];
        [self show:YES];
    }
}

#pragma mark - Rotation

-(CGFloat) sidebarButtonRotation{
    return -([[[MMRotationManager sharedInstance] currentRotationReading] angle] + M_PI/2);
}

-(CGFloat) sidebarButtonRotationForReading:(MMVector*)currentReading{
    return -([currentReading angle] + M_PI/2);
}

-(void) didUpdateAccelerometerWithReading:(MMVector *)currentRawReading{
    lastRotationReading = [self sidebarButtonRotationForReading:currentRawReading];
    CGFloat rotReading = [self sidebarButtonRotationForReading:currentRawReading];
    countButton.rotation = rotReading;
    for(MMScrapBubbleButton* bubble in self.subviews){
        if([bubble isKindOfClass:[MMScrapBubbleButton class]]){
            // during an animation, the scrap will also be a subview,
            // so we need to make sure that we're rotating only the
            // bubble button
            bubble.rotation = rotReading;
        }
    }
}


#pragma mark - Ignore Touches

/**
 * these two methods make sure that this scrap container view
 * can never intercept any touch input. instead it will
 * effectively pass through this view to the views behind it
 */
-(UIView*) hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    for(MMScrapBubbleButton* bubble in self.subviews){
        if([bubble isKindOfClass:[MMScrapBubbleButton class]]){
            UIView* output = [bubble hitTest:[self convertPoint:point toView:bubble] withEvent:event];
            if(output) return output;
        }
    }
    if(contentView.alpha){
        UIView* output = [contentView hitTest:[self convertPoint:point toView:contentView] withEvent:event];
        if(output) return output;
    }
    return [super hitTest:point withEvent:event];
}

-(BOOL) pointInside:(CGPoint)point withEvent:(UIEvent *)event{
    for(MMScrapBubbleButton* bubble in self.subviews){
        if([bubble isKindOfClass:[MMScrapBubbleButton class]]){
            if([bubble pointInside:[self convertPoint:point toView:bubble] withEvent:event]){
                return YES;
            }
        }
    }
    return [super pointInside:point withEvent:event];
}



#pragma mark - Save and Load


static NSString* bezelStatePath;


+(NSString*) pathToPlist{
    if(!bezelStatePath){
        NSString* documentsPath = [NSFileManager documentsPath];
        NSString* bezelStateDirectory = [documentsPath stringByAppendingPathComponent:@"Bezel"];
        [NSFileManager ensureDirectoryExistsAtPath:bezelStateDirectory];
        bezelStatePath = [[bezelStateDirectory stringByAppendingPathComponent:@"rotations"] stringByAppendingPathExtension:@"plist"];
    }
    return bezelStatePath;
}

-(void) saveScrapContainerToDisk{
    MMImmutableScrapsInSidebarState* immutableState = [scrapState immutableStateForPath:self.scrapIDsPath];
    NSMutableDictionary* writeableAdjustments = [rotationAdjustments copy];
    dispatch_async([MMScrapsOnPaperState importExportStateQueue], ^(void) {
        @autoreleasepool {
            [immutableState saveStateToDiskBlocking];
            [writeableAdjustments writeToFile:[MMScrapsInBezelContainerView pathToPlist] atomically:YES];
        }
    });
}

-(void) loadFromDisk{
    [scrapState loadStateAsynchronously:YES atPath:self.scrapIDsPath andMakeEditable:NO];
}


#pragma mark - MMScrapsInSidebarStateDelegate & MMScrapBezelMenuViewDelegate

-(void) didLoadScrapInSidebar:(MMScrapView *)scrap{
    // add to the bezel
    NSNumber* rotationAdjustment = [rotationAdjustments objectForKey:scrap.uuid];
    scrap.rotation += [rotationAdjustment floatValue];
    [self addScrapToBezelSidebar:scrap animated:NO];
}

-(void) didLoadAllScrapsInSidebar:(MMScrapsInSidebarState *)_scrapState{
    // noop
}

-(void) didUnloadAllScrapsInSidebar:(MMScrapsInSidebarState *)scrapState{
    // noop
}

-(MMScrapsOnPaperState*) paperStateForPageUUID:(NSString*)uuidOfPage{
    return [bubbleDelegate pageForUUID:uuidOfPage].scrapsOnPaperState;
}

@end