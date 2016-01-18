//
//  DraggableVideoPlayer.m
//  tvapp
//
//  Created by Weiyu Chen on 2016/1/12.
//  Copyright © 2016年 Weiyu.Chen All rights reserved.
//

#import "DraggableVideoPlayer.h"
#import "AppDelegate.h"

typedef NS_ENUM(NSInteger, PlayerViewPanGestureDirection)
{
    PlayerViewPanGestureDirectionUp,
    PlayerViewPanGestureDirectionDown,
    PlayerViewPanGestureDirectionLeft,
    PlayerViewPanGestureDirectionRight
};

@interface DraggableVideoPlayer ()
@property (strong, nonatomic) UIWindow           *playerWindow;
@property (strong, nonatomic) NSLayoutConstraint *moviePlayerRightPaddingConstraint;
@property (strong, nonatomic) NSLayoutConstraint *moviePlayerCenterYConstraint;
@property (strong, nonatomic) NSLayoutConstraint *moviePlayerWidthConstraint;
@property (strong, nonatomic) NSLayoutConstraint *moviePlayerHeightConstraint;
@property (strong, nonatomic) NSArray            *moviePlayerFullScreenConstraints;

@property (nonatomic) BOOL                       isPause;
@property (nonatomic) BOOL                       isBufferLoadingDisconnect;
@property (nonatomic) NSTimeInterval             tempPlayBackTime;
@property (strong, nonatomic) UIView             *loadingView;
@property (strong, nonatomic) UIButton           *productButton;
@property (strong, nonatomic) NSTimer            *videoReloadTimer;
@property (strong, nonatomic) NSTimer            *bufferCheckingTimer;

/* Movie player default width, height and center Y when initialized */
@property (nonatomic) CGFloat playerFrameDefaultWidth;
@property (nonatomic) CGFloat playerFrameDefaultHeight;
@property (nonatomic) CGFloat playerFrameDefaultCenterY;

/* Movie player minimized width, height and center Y when dragged to bottom */
@property (nonatomic) CGFloat playerFrameMinWidth;
@property (nonatomic) CGFloat playerFrameMinHeight;
@property (nonatomic) CGFloat playerFrameMaxCenterY;

/* Movie player top padding to window top when dragged to bottom */
@property (nonatomic) CGFloat playerFrameMaxTopPadding;

/* The width and height ratio of movie player */
@property (nonatomic) CGFloat playerFrameSizeRatio;

/* The minimum ratio of transition */
@property (nonatomic) CGFloat playerFrameTransitionMinRatio;

/* The vertical range for moving the movie player */
@property (nonatomic) CGFloat playerVerticalDraggingRange;

/* PanGestureRecognizer direction */
@property (nonatomic) PlayerViewPanGestureDirection panDirection;
@property (nonatomic) BOOL panGestureIsVertical;
@property (nonatomic) BOOL panGestureIsHorizontal;
@end

@implementation DraggableVideoPlayer

- (instancetype) initWithContentURL:(NSURL *)url {
    self = [super initWithContentURL:url];
    if (self) {
        [self setControlStyle:MPMovieControlStyleNone];
        [self setScalingMode:MPMovieScalingModeFill];
        
        _playerWindow = [AppDelegate sharedAppDelegate].window;
        
        // Video player frame params setting
        _playerFrameSizeRatio = draggableVideoPlayerWidthAndHeightRatio;
        _playerFrameTransitionMinRatio = draggableVideoPlayerMinimumTransitionRatio;
        _playerFrameDefaultWidth = [UIScreen mainScreen].bounds.size.width;
        _playerFrameDefaultHeight = _playerFrameDefaultWidth / _playerFrameSizeRatio;
        _playerFrameDefaultCenterY = draggableVideoPlayerTopPaddingInDefaultSize + _playerFrameDefaultHeight / 2;
        _playerFrameMinWidth = [UIScreen mainScreen].bounds.size.width * draggableVideoPlayerMinimumTransitionRatio;
        _playerFrameMinHeight = _playerFrameMinWidth / _playerFrameSizeRatio;
        _playerFrameMaxTopPadding = [UIScreen mainScreen].bounds.size.height - draggableVideoPlayerBottomPaddingInMinimizedSize - _playerFrameMinHeight;
        _playerFrameMaxCenterY = _playerFrameMaxTopPadding + _playerFrameMinHeight / 2;
        _playerVerticalDraggingRange = _playerFrameMaxCenterY - _playerFrameDefaultCenterY;
        
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deviceDidRotate:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
        [self initNotificationObserver];
    }
    return self;
}

- (void) show {
    [self showPlayerView];
}

- (void) initNotificationObserver {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayLoadStateDidChanged:)
                                                 name:MPMoviePlayerLoadStateDidChangeNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayStateDidChanged:)
                                                 name:MPMoviePlayerPlaybackStateDidChangeNotification
                                               object:nil];
}

- (void) removeNotificationObserver {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackStateDidChangeNotification object:nil];
}

- (void) changeContentURL:(NSURL *)url {
    [self stop];
    [self setContentURL:url];
    [self prepareToPlay];
}

#pragma mark - Movie player view setup & Constraints methods
- (void) showPlayerView {
    [self.view setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.view addGestureRecognizer:panGestureRecognizer];
    
    [_playerWindow addSubview:self.view];
    [_playerWindow addConstraints:[self moviePlayerDefaultConstrains]];
    [_playerWindow layoutIfNeeded];
    
    [self showLoadingView];
    
    _playerMaximized = YES;
    _playerMinimized = NO;
    _playerFullScreen = NO;
    _panGestureIsHorizontal = NO;
    _panGestureIsVertical = NO;
    _isPause = YES;
    
    [self prepareToPlay];
    self.shouldAutoplay = YES;
    
    if ([[UIDevice currentDevice] orientation] != UIDeviceOrientationPortrait) {
        switch ([[UIDevice currentDevice] orientation]) {
            case UIDeviceOrientationLandscapeLeft:
                [self rotateMoviePlayerToAngle:M_PI/2];
                break;
            case UIDeviceOrientationLandscapeRight:
                [self rotateMoviePlayerToAngle:-M_PI/2];
                break;
            default:
                break;
        }
    }
    
    [self startReloadTimer];
}

- (void) showLoadingView {
    if ([self.view.subviews containsObject:_loadingView]) {
        [self removeLoadingView];
    }
    
    if (!_loadingView) {
        _loadingView = [[[NSBundle mainBundle] loadNibNamed:@"ViewsForVideoPlayer" owner:self options:nil] firstObject];
        [_loadingView setTranslatesAutoresizingMaskIntoConstraints:NO];
    }
    
    [self.view addSubview:_loadingView];
    NSMutableArray *constraints = [NSMutableArray array];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:_loadingView
                                                        attribute:NSLayoutAttributeCenterX
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:self.view
                                                        attribute:NSLayoutAttributeCenterX
                                                       multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:_loadingView
                                                        attribute:NSLayoutAttributeCenterY
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:self.view
                                                        attribute:NSLayoutAttributeCenterY
                                                       multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:_loadingView
                                                        attribute:NSLayoutAttributeHeight
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:self.view
                                                        attribute:NSLayoutAttributeHeight
                                                       multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:_loadingView
                                                        attribute:NSLayoutAttributeWidth
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:self.view
                                                        attribute:NSLayoutAttributeWidth
                                                       multiplier:1.0f constant:0.0f]];
    [self.view addConstraints:constraints];
}

- (void) removeLoadingView {
    if (_loadingView) {
        [_loadingView removeFromSuperview];
        _loadingView = nil;
    }
}

- (NSArray *) moviePlayerDefaultConstrains {
    _moviePlayerRightPaddingConstraint = [NSLayoutConstraint constraintWithItem:self.view
                                                                      attribute:NSLayoutAttributeRight
                                                                      relatedBy:NSLayoutRelationEqual
                                                                         toItem:_playerWindow
                                                                      attribute:NSLayoutAttributeRight
                                                                     multiplier:1.0f constant:0.0f];
    _moviePlayerCenterYConstraint = [NSLayoutConstraint constraintWithItem:self.view
                                                                 attribute:NSLayoutAttributeCenterY
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:_playerWindow
                                                                 attribute:NSLayoutAttributeTop
                                                                multiplier:1.0f constant:_playerFrameDefaultCenterY];
    _moviePlayerWidthConstraint = [NSLayoutConstraint constraintWithItem:self.view
                                                               attribute:NSLayoutAttributeWidth
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:nil
                                                               attribute:NSLayoutAttributeNotAnAttribute
                                                              multiplier:1.0f constant:_playerFrameDefaultWidth];
    _moviePlayerHeightConstraint = [NSLayoutConstraint constraintWithItem:self.view
                                                                attribute:NSLayoutAttributeHeight
                                                                relatedBy:NSLayoutRelationEqual
                                                                   toItem:self.view
                                                                attribute:NSLayoutAttributeWidth
                                                               multiplier:1.0f/_playerFrameSizeRatio constant:0.0f];
    return @[_moviePlayerRightPaddingConstraint, _moviePlayerCenterYConstraint, _moviePlayerWidthConstraint, _moviePlayerHeightConstraint];
}

- (NSArray *) moviePlayerFullScreenConstrains {
    float ver = [[[UIDevice currentDevice] systemVersion] floatValue];
    NSMutableArray *constraints = [NSMutableArray array];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.view
                                                        attribute:NSLayoutAttributeWidth
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:_playerWindow
                                                        attribute:ver < 8 ? NSLayoutAttributeWidth : NSLayoutAttributeHeight
                                                       multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.view
                                                        attribute:NSLayoutAttributeHeight
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:_playerWindow
                                                        attribute:ver < 8 ? NSLayoutAttributeHeight : NSLayoutAttributeWidth
                                                       multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.view
                                                        attribute:NSLayoutAttributeCenterX
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:_playerWindow
                                                        attribute:NSLayoutAttributeCenterX
                                                       multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.view
                                                        attribute:NSLayoutAttributeCenterY
                                                        relatedBy:NSLayoutRelationEqual
                                                           toItem:_playerWindow
                                                        attribute:NSLayoutAttributeCenterY
                                                       multiplier:1.0f constant:0.0f]];
    return constraints;
}

#pragma mark - MPMoviePlayer Notificaation Handler
- (void) moviePlayStateDidChanged:(NSNotification*)notification {
    if (self.playbackState == MPMoviePlaybackStateStopped) {
        NSLog(@"[moviePlayStateDidChanged] >> MPMoviePlaybackStateStopped");
        [self showLoadingView];
        [self endBufferChecking];
        _isPause = YES;
    }
    else if (self.playbackState == MPMoviePlaybackStatePlaying) {
        NSLog(@"[moviePlayStateDidChanged] >> MPMoviePlaybackStatePlaying");
        
        if (_isBufferLoadingDisconnect) {
            _isBufferLoadingDisconnect = NO;
            [self pause];
            [self prepareToPlay];
            self.shouldAutoplay = YES;
        }
        else {
            [self removeLoadingView];
            _isPause = NO;
            _tempPlayBackTime = 0;
            [self endReloadTimer];
            [self startBufferChecking];
        }
    }
    else if (self.playbackState == MPMoviePlaybackStatePaused) {
        NSLog(@"[moviePlayStateDidChanged] >> MPMoviePlaybackStatePaused");
        [self showLoadingView];
        [self endBufferChecking];
        _isPause = YES;
    }
    else if (self.playbackState == MPMoviePlaybackStateInterrupted) {
        NSLog(@"[moviePlayStateDidChanged] >> MPMoviePlaybackStateInterrupted");
        [self showLoadingView];
        [self endBufferChecking];
        _isPause = YES;
    }
}

- (void) moviePlayLoadStateDidChanged:(NSNotification*)notification {
    if ((self.loadState & MPMovieLoadStatePlayable) == MPMovieLoadStatePlayable) {
        NSLog(@"[moviePlayLoadStateDidChanged] >> MPMovieLoadStatePlayable");
        if (_isPause) {
            [self play];
        }
    }else if((self.loadState & MPMovieLoadStatePlaythroughOK) == MPMovieLoadStatePlaythroughOK) {
        NSLog(@"[moviePlayLoadStateDidChanged] >> MPMovieLoadStatePlaythroughOK");
    }else if((self.loadState & MPMovieLoadStateStalled) == MPMovieLoadStateStalled) {
        NSLog(@"[moviePlayLoadStateDidChanged] >> MPMovieLoadStateStalled");
        [self showLoadingView];
    }else if((self.loadState & MPMovieLoadStateUnknown) == MPMovieLoadStateUnknown) {
        NSLog(@"[moviePlayLoadStateDidChanged] >> MPMovieLoadStateUnknown");
        [self showLoadingView];
        [self endBufferChecking];
        [self startReloadTimer];
    }
}

#pragma mark - Movie player PanGestureRecognizer action & methods
- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    if (!_playerFullScreen) {
        CGPoint translation = [recognizer translationInView:_playerWindow];
        
        CGFloat tempPlayerCenterY = _moviePlayerCenterYConstraint.constant;

        if (tempPlayerCenterY < _playerFrameDefaultCenterY) {
            _panGestureIsVertical = YES;
            _panGestureIsHorizontal = NO;
            // 避免超出螢幕頂部
            if (tempPlayerCenterY + translation.y < _playerFrameDefaultHeight / 2) {
                _moviePlayerCenterYConstraint.constant = _playerFrameDefaultHeight / 2;
                return;
            }
            [[UIApplication sharedApplication] setStatusBarHidden:NO];
            // y軸變化
            _moviePlayerCenterYConstraint.constant += translation.y;
            // Frame size固定
            _moviePlayerWidthConstraint.constant = [UIScreen mainScreen].bounds.size.width;
            [_playerWindow layoutIfNeeded];
            [self panDirectionWithTranslation:translation Vertical:YES];
        }
        else if (tempPlayerCenterY + translation.y >= _playerFrameDefaultCenterY && tempPlayerCenterY + translation.y < _playerFrameMaxCenterY && !_panGestureIsHorizontal) {
            _panGestureIsVertical = YES;
            _panGestureIsHorizontal = NO;
            // y軸變化
            _moviePlayerCenterYConstraint.constant += translation.y;
            [_playerWindow layoutIfNeeded];
            // Frame size變化
            CGFloat transitionRatio = 1.0f - (CGRectGetMidY(self.view.frame) - _playerFrameDefaultCenterY) / _playerVerticalDraggingRange;
            _moviePlayerWidthConstraint.constant = _playerFrameDefaultWidth * (_playerFrameTransitionMinRatio + (1 - _playerFrameTransitionMinRatio) * transitionRatio);
            [_playerWindow layoutIfNeeded];
            
            [self panDirectionWithTranslation:translation Vertical:YES];
        }
        else if (_playerMinimized && translation.x != 0 && !_panGestureIsVertical) {
            _panGestureIsVertical = NO;
            _panGestureIsHorizontal = YES;
            // x軸變化
            _moviePlayerRightPaddingConstraint.constant += translation.x;
            [_playerWindow layoutIfNeeded];
            
            // 透明度變化
            if (_moviePlayerRightPaddingConstraint.constant < 0) {
                self.view.alpha = 1 - (-_moviePlayerRightPaddingConstraint.constant / [UIScreen mainScreen].bounds.size.width);
            }
            else {
                self.view.alpha = 1-(_moviePlayerRightPaddingConstraint.constant / _playerFrameMinWidth);
            }
            
            [self panDirectionWithTranslation:translation Vertical:NO];
        }
        
        // When user dragging is end
        if (recognizer.state == UIGestureRecognizerStateEnded) {
            // down
            if (_panDirection == PlayerViewPanGestureDirectionDown) {
                _panGestureIsVertical = NO;
                [self moviePlayerViewVerticalMinimizeAnimation];
            }
            // up
            else if (_panDirection == PlayerViewPanGestureDirectionUp) {
                _panGestureIsVertical = NO;
                [self moviePlayerViewVerticalDefaultAnimation];
            }
            else if (_panDirection == PlayerViewPanGestureDirectionRight) {
                _panGestureIsHorizontal = NO;
                if (_moviePlayerRightPaddingConstraint.constant < 30) {
                    [self moviePlayerViewHorizontalMinimizeAnimation];
                }
                else {
                    [self moviePlayerViewHorizontalRightFadeoutAnimation];
                }
            }
            else {
                _panGestureIsHorizontal = NO;
                if (_moviePlayerRightPaddingConstraint.constant > -120) {
                    [self moviePlayerViewHorizontalMinimizeAnimation];
                }
                else {
                    [self moviePlayerViewHorizontalLeftFadeoutAnimation];
                }
            }
            
        }
        
        [recognizer setTranslation:CGPointMake(0, 0) inView:_playerWindow];
    }
}

- (void) moviePlayerViewVerticalMinimizeAnimation {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration: 0.3
                              delay: 0
                            options: UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             _moviePlayerCenterYConstraint.constant = _playerFrameMaxCenterY;
                             _moviePlayerWidthConstraint.constant = _playerFrameMinWidth;
                             [_playerWindow layoutIfNeeded];
                             _playerMinimized = YES;
                             _playerMaximized = NO;
                         }
                         completion:nil];
    });
}

- (void) moviePlayerViewVerticalDefaultAnimation {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration: 0.3
                              delay: 0
                            options: UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             _moviePlayerCenterYConstraint.constant = _playerFrameDefaultCenterY;
                             _moviePlayerWidthConstraint.constant = _playerFrameDefaultWidth;
                             [_playerWindow layoutIfNeeded];
                             
                             if ([self.delegate respondsToSelector:@selector(scrollParentBackgroundToTop)]) {
                                 [self.delegate scrollParentBackgroundToTop];
                             }
                             else {
                                 NSLog(@"Delegate method 'scrollParentBackgroundToTop' not implement.");
                             }
                             _playerMinimized = NO;
                             _playerMaximized = YES;
                         }
                         completion:nil];
    });
}

- (void) moviePlayerViewHorizontalMinimizeAnimation {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration: 0.3
                              delay: 0
                            options: UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             _moviePlayerRightPaddingConstraint.constant = 0.0f;
                             self.view.alpha = 1;
                             [_playerWindow layoutIfNeeded];
                         }
                         completion:^(BOOL finished) {
                             return ;
                         }];
    });
}

- (void) moviePlayerViewHorizontalRightFadeoutAnimation {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration: 0.3
                              delay: 0
                            options: UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             _moviePlayerRightPaddingConstraint.constant = _playerFrameMinWidth;
                             [_playerWindow layoutIfNeeded];
                             self.view.alpha = 0;
                         }
                         completion:^(BOOL finished){
                             _playerMinimized = NO;
                             [self cleanPlayer];
                         }];
    });
}

- (void) moviePlayerViewHorizontalLeftFadeoutAnimation {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration: 0.3
                              delay: 0
                            options: UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             _moviePlayerRightPaddingConstraint.constant = -[UIScreen mainScreen].bounds.size.width;
                             [_playerWindow layoutIfNeeded];
                             self.view.alpha = 0;
                         }
                         completion:^(BOOL finished){
                             _playerMinimized = NO;
                             [self cleanPlayer];
                         }];
    });
}

#pragma mark - Notification handler
- (void)deviceDidRotate:(NSNotification *)notification
{
    if ([_playerWindow.subviews containsObject:self.view] && !_playerMinimized) {
        switch ([[UIDevice currentDevice] orientation]) {
            case UIDeviceOrientationPortrait:
                [self rotateMoviePlayerToAngle:0.0f];
                break;
            case UIDeviceOrientationLandscapeLeft:
                [self rotateMoviePlayerToAngle:M_PI/2];
                break;
            case UIDeviceOrientationLandscapeRight:
                [self rotateMoviePlayerToAngle:-M_PI/2];
                break;
            default:
                break;
        }
    }
}

#pragma mark - Other methods
- (void) parentScrollViewDidScroll:(UIScrollView *)scrollView {
    if (!_playerMinimized) {
        if (scrollView.contentOffset.y <= 45.0f + 64.0f) {
            _moviePlayerCenterYConstraint.constant = _playerFrameDefaultCenterY - scrollView.contentOffset.y;
            [_playerWindow layoutIfNeeded];
            [[UIApplication sharedApplication] setStatusBarHidden:NO];
        }
        else {
            _moviePlayerCenterYConstraint.constant = 0.0f + _playerFrameDefaultHeight / 2;
            [_playerWindow layoutIfNeeded];
            [[UIApplication sharedApplication] setStatusBarHidden:YES];
        }
    }
}

- (void) rotateMoviePlayerToAngle:(CGFloat)angle {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3
                              delay:0.0
                            options:0
                         animations:^{
                             [UIView setAnimationBeginsFromCurrentState:YES];
                             self.view.transform = CGAffineTransformMakeRotation(angle);
                             
                             // Not portrait, but landscape left or right --> Fullscreen
                             if (angle != 0) {
                                 [[UIApplication sharedApplication] setStatusBarHidden:YES];
                                 [self cleanPlayerWindowLayoutConstraints];
                                 _moviePlayerFullScreenConstraints = [self moviePlayerFullScreenConstrains];
                                 [_playerWindow addConstraints:_moviePlayerFullScreenConstraints];
                                 [_playerWindow layoutIfNeeded];
                                 _playerFullScreen = YES;
                             }
                             else {
                                 [[UIApplication sharedApplication] setStatusBarHidden:NO];
                                 [self cleanPlayerWindowLayoutConstraints];
                                 [_playerWindow addConstraints:[self moviePlayerDefaultConstrains]];
                                 [_playerWindow layoutIfNeeded];
                                 
                                 if ([self.delegate respondsToSelector:@selector(scrollParentBackgroundToTop)]) {
                                     [self.delegate scrollParentBackgroundToTop];
                                 }
                                 else {
                                     NSLog(@"Delegate method 'scrollParentBackgroundToTop' not implement.");
                                 }
                                 _playerMinimized = NO;
                                 _playerFullScreen = NO;
                             }
                             
                             
                         }
                         completion:^(BOOL finished) {
                             DraggableVideoPlayerOrientation orientation = angle == 0 ? DraggableVideoPlayerOrientationPortrait : DraggableVideoPlayerOrientationLandScape;
                             if ([self.delegate respondsToSelector:@selector(videoPlayerDidRotateToOrientation:)]) {
                                 [self.delegate videoPlayerDidRotateToOrientation:orientation];
                             }
                             else {
                                 NSLog(@"[Delegate method not found]:Video player did rotate, but no delegate method implement.");
                             }
                         }];
    });
}

- (void) panDirectionWithTranslation:(CGPoint)translation Vertical:(BOOL)vertical{
    if (vertical) {
        if (translation.y > 0) {
            _panDirection = PlayerViewPanGestureDirectionDown;
        }
        else if (translation.y < 0) {
            _panDirection = PlayerViewPanGestureDirectionUp;
        }
    }
    else {
        if (translation.x > 0) {
            _panDirection = PlayerViewPanGestureDirectionRight;
        }
        else if (translation.x < 0) {
            _panDirection = PlayerViewPanGestureDirectionLeft;
        }
    }
    
}

- (void) startReloadTimer {
    [self endReloadTimer];
    _videoReloadTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(reloadStreaming:) userInfo:nil repeats:YES];
}

- (void) endReloadTimer {
    if (_videoReloadTimer) {
        [_videoReloadTimer invalidate];
        _videoReloadTimer = nil;
    }
}

- (void) startBufferChecking {
    [self endBufferChecking];
    _bufferCheckingTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(checkBuffer:) userInfo:nil repeats:YES];
}

- (void) endBufferChecking {
    if (_bufferCheckingTimer) {
        [_bufferCheckingTimer invalidate];
        _bufferCheckingTimer = nil;
    }
}

- (void) reloadStreaming:(id)sender {
    NSLog(@"reload streaming");
    [self stop];
    [self setContentURL:self.contentURL];
    [self prepareToPlay];
    self.shouldAutoplay = YES;
}

- (void) checkBuffer:(id)sender {
    NSArray *events = self.accessLog.events;
    MPMovieAccessLogEvent *currentEvent = [events lastObject];
    NSLog(@"## CurrentPlayBackTime:%f, LastPlayBackTime:%f",currentEvent.durationWatched,_tempPlayBackTime);
    if (currentEvent.durationWatched > _tempPlayBackTime) {
        _tempPlayBackTime = currentEvent.durationWatched;
        NSLog(@"## Playing");
    }
    else if (currentEvent.durationWatched == _tempPlayBackTime && currentEvent.durationWatched != 0) {
        NSLog(@"## Play stocked");
        _isBufferLoadingDisconnect = YES;
        [self endBufferChecking];
        [self startReloadTimer];
    }
}

- (void) cleanPlayer {
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    
    [[UIApplication sharedApplication] setStatusBarHidden:NO];
    
    if (_videoReloadTimer) {
        [_videoReloadTimer invalidate];
        _videoReloadTimer = nil;
    }
    
    if (_bufferCheckingTimer) {
        [_bufferCheckingTimer invalidate];
        _bufferCheckingTimer = nil;
    }
    
    [self removeNotificationObserver];

    [self stop];
    [self.view removeFromSuperview];
    
    if ([self.delegate respondsToSelector:@selector(removeDraggableVideoPlayer)]) {
        [self.delegate removeDraggableVideoPlayer];
    }
    else {
        NSLog(@"Delegate method 'removeDraggableVideoPlayer' not implement.");
    }
}

- (void) cleanPlayerWindowLayoutConstraints {
    for (NSLayoutConstraint *constraint in _moviePlayerFullScreenConstraints) {
        if ([_playerWindow.constraints containsObject:constraint]) {
            [_playerWindow removeConstraint:constraint];
        }
    }
    
    if ([_playerWindow.constraints containsObject:_moviePlayerCenterYConstraint]) {
        [_playerWindow removeConstraints:@[_moviePlayerRightPaddingConstraint, _moviePlayerCenterYConstraint, _moviePlayerWidthConstraint, _moviePlayerHeightConstraint]];
    }
}
@end
