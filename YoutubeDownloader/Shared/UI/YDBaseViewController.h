//
//  YDBaseViewController.h
//  YoutubeDownloader
//
//  Created by Hao Wang  on 13-11-4.
//  Copyright (c) 2013年 HAO WANG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GAI.h"

@interface YDBaseViewController : UIViewController

@property (nonatomic, strong) NSArray *navigationButtons;

/*!
 The tracker on which view tracking calls are be made, or `nil`, in which case
 [GAI defaultTracker] will be used.
 */
@property(nonatomic, assign) id<GAITracker> tracker;
/*!
 The screen name, for purposes of Google Analytics tracking. If this is `nil`,
 no tracking calls will be made.
 */
@property(nonatomic, copy)   NSString *screenName;

- (void)showToastMessage:(NSString *)msg hideAfterDelay:(NSTimeInterval)seconds;
- (void)showToastMessage:(NSString *)msg hideAfterDelay:(NSTimeInterval)seconds withProgress:(BOOL)useProgress;
- (void)showToastMessage:(NSString *)msg
          hideAfterDelay:(NSTimeInterval)seconds
            withProgress:(BOOL)useProgress
         backgroundColor:(UIColor *)backgroundColor
               textColor:(UIColor *)textColor;
- (void)dismissToastMessage;
- (void)dismissAllToastMessages;

@end
