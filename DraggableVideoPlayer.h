//
//  DraggableVideoPlayer.h
//  tvapp
//
//  Created by Weiyu Chen on 2016/1/12.
//  Copyright © 2016年 Weiyu.Chen All rights reserved.
//

#import <MediaPlayer/MediaPlayer.h>

typedef NS_ENUM(NSInteger, DraggableVideoPlayerOrientation)
{
    DraggableVideoPlayerOrientationPortrait,
    DraggableVideoPlayerOrientationLandScape
};

/* Some video player size or ratio constant 
   Try different values to fit your need */
static CGFloat const draggableVideoPlayerWidthAndHeightRatio            = 16.0f / 10.0f;
static CGFloat const draggableVideoPlayerMinimumTransitionRatio         = 1.0f / 3.0f;
static CGFloat const draggableVideoPlayerTopPaddingInDefaultSize        = 45.0f + 64.0f;
static CGFloat const draggableVideoPlayerBottomPaddingInMinimizedSize   = 60.0f;

@protocol DraggableVideoPlayerDelegate <NSObject>

@optional
- (void) scrollParentBackgroundToTop;
- (void) removeDraggableVideoPlayer;
- (void) videoPlayerDidRotateToOrientation:(DraggableVideoPlayerOrientation)orientation;
@end


@interface DraggableVideoPlayer : MPMoviePlayerController
/*  Movie player size boolValue,
 playerMinimized = YES : movie player has dragged to bottom
 playerMaximized = YES : movie player has dragged to default position
 playerFullScreen = YES : movie player has become fullscreen */
@property (nonatomic) BOOL playerMinimized;
@property (nonatomic) BOOL playerMaximized;
@property (nonatomic) BOOL playerFullScreen;

@property (weak, nonatomic) id <DraggableVideoPlayerDelegate> delegate;

- (instancetype) initWithContentURL:(NSURL *)url;
- (void) show;
- (void) changeContentURL:(NSURL *)url;
- (void) parentScrollViewDidScroll:(UIScrollView *)scrollView;
- (void) moviePlayerViewVerticalMinimizeAnimation;
- (void) moviePlayerViewVerticalDefaultAnimation;
- (void) cleanPlayer;
@end
