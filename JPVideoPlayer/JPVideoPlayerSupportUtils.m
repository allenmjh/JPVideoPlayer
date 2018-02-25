//
// Created by NewPan on 2018/2/20.
// Copyright (c) 2018 NewPan. All rights reserved.
//

#import "JPVideoPlayerSupportUtils.h"
#import "objc/runtime.h"
#import "JPVideoPlayer.h"
#import "UIView+WebVideoCache.h"
#import "JPVideoPlayerControlViews.h"
#import "JPVideoPlayerCompat.h"

@implementation NSURL (StripQuery)

- (NSString *)absoluteStringByStrippingQuery{
    NSString *absoluteString = [self absoluteString];
    NSUInteger queryLength = [[self query] length];
    NSString* strippedString = (queryLength ? [absoluteString substringToIndex:[absoluteString length] - (queryLength + 1)] : absoluteString);

    if ([strippedString hasSuffix:@"?"]) {
        strippedString = [strippedString substringToIndex:absoluteString.length-1];
    }
    return strippedString;
}

@end

static char loadOperationKey;
static char currentPlayingURLKey;

@implementation UIView (WebVideoCacheOperation)

#pragma mark - Public

- (void)setCurrentPlayingURL:(NSURL *)currentPlayingURL{
    objc_setAssociatedObject(self, &currentPlayingURLKey, currentPlayingURL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSURL *)currentPlayingURL{
    return objc_getAssociatedObject(self, &currentPlayingURLKey);
}

@end

@interface UIView ()

@property(nonatomic)JPVideoPlayerProgressView *progressView;

@property(nonatomic)UIView *jp_videoLayerView;

@property(nonatomic)UIView *jp_indicatorView;

@property(nonatomic)UIColor *progressViewTintColor;

@property(nonatomic)UIColor *progressViewBackgroundColor;

@property(nonatomic)JPVideoPlayerActivityIndicator *activityIndicatorView;

@end

static char progressViewKey;
static char progressViewTintColorKey;
static char progressViewBackgroundColorKey;
static char activityIndicatorViewKey;
static char videoLayerViewKey;
static char indicatorViewKey;
static char downloadProgressValueKey;
static char playingProgressValueKey;
static char backgroundLayerKey;
@implementation UIView (PlayerStatusAndDownloadIndicator)

#pragma mark - Public

- (UIView *)jp_indicatorView{
    UIView *view = objc_getAssociatedObject(self, &indicatorViewKey);
    if (!view) {
        view = [UIView new];
        view.frame = self.bounds;
        view.backgroundColor = [UIColor clearColor];
        view.userInteractionEnabled = NO;
        objc_setAssociatedObject(self, &indicatorViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return nil;
}

- (void)jp_perfersPlayingProgressViewColor:(UIColor *)color{
    if (color) {
        [self.progressView perfersPlayingProgressViewColor:color];
        self.progressViewTintColor = color;
    }
}

- (void)jp_perfersDownloadProgressViewColor:(UIColor *)color{
    if (color) {
        [self.progressView perfersDownloadProgressViewColor:color];
        self.progressViewBackgroundColor = color;
    }
}


#pragma mark - Private

- (void)displayBackLayer{
    if (self.jp_backgroundLayer.superlayer) {
        return;
    }
    self.jp_backgroundLayer.frame = self.bounds;
    UIColor *backcolor = [UIColor clearColor];
    if (self.jp_videoPlayerDelegate && [self.jp_videoPlayerDelegate respondsToSelector:@selector(shouldDisplayBlackLayerBeforePlayStart)]) {
        if ([self.jp_videoPlayerDelegate shouldDisplayBlackLayerBeforePlayStart]) {
            backcolor = [UIColor blackColor];
        }
    }
    self.jp_backgroundLayer.backgroundColor = backcolor.CGColor;
    [self.jp_videoLayerView.layer addSublayer:self.jp_backgroundLayer];
}

- (void)refreshIndicatorViewForPortrait{
    [self layoutProgressViewForPortrait:self.progressView];
    [self layoutActivityIndicatorViewForPortrait:self.activityIndicatorView];
    [self.progressView refreshProgressViewForScreenEvents];
}

- (void)refreshIndicatorViewForLandscape{
    [self layoutProgressViewForLandscape:self.progressView];
    [self layoutActivityIndicatorViewForLandscape:self.activityIndicatorView];
    [self.progressView refreshProgressViewForScreenEvents];
}

- (void)jp_showProgressView{
    if (!self.progressView.superview) {
        [self.jp_indicatorView addSubview:self.progressView];
        [self.progressView setDownloadProgress:0];
        [self.progressView setPlayingProgress:0];
        self.progressView.hidden = NO;
    }
}

- (void)jp_hideProgressView{
    if (self.progressView.superview) {
        self.progressView.hidden = YES;
        [self.progressView setDownloadProgress:0];
        [self.progressView setPlayingProgress:0];
        [self.progressView removeFromSuperview];
    }
}

- (void)jp_progressViewDownloadingStatusChangedWithProgressValue:(NSNumber *)progress{
    CGFloat delta = [progress floatValue];
    delta = MAX(0, delta);
    delta = MIN(delta, 1);
    [self.progressView setDownloadProgress:delta];
    self.jp_downloadProgressValue = delta;
}

- (void)jp_progressViewPlayingStatusChangedWithProgressValue:(NSNumber *)progress{
    CGFloat delta = [progress floatValue];
    delta = MAX(0, delta);
    delta = MIN(delta, 1);
    [self.progressView setPlayingProgress:delta];
    self.jp_playingProgressValue = delta;
}

- (void)jp_showActivityIndicatorView{
    if (!self.activityIndicatorView.superview) {
        [self.jp_indicatorView addSubview:self.activityIndicatorView];
        [self.activityIndicatorView startAnimating];
    }
}

- (void)jp_hideActivityIndicatorView{
    if (self.activityIndicatorView.superview) {
        [self.activityIndicatorView stopAnimating];
        [self.activityIndicatorView removeFromSuperview];
    }
}

- (void)jp_setupVideoLayerViewAndIndicatorView{
    if (!self.jp_videoLayerView.superview && !self.jp_indicatorView.superview) {
        [self addSubview:self.jp_videoLayerView];
        [self addSubview:self.jp_indicatorView];
    }
}

- (void)jp_removeVideoLayerViewAndIndicatorView{
    if (self.jp_videoLayerView.superview && self.jp_indicatorView.superview) {
        [self.jp_videoLayerView removeFromSuperview];
        [self.jp_indicatorView removeFromSuperview];
    }
}


#pragma mark - Properties

- (CALayer *)jp_backgroundLayer{
    CALayer *backLayer = objc_getAssociatedObject(self, &backgroundLayerKey);
    if (!backLayer) {
        backLayer = [CALayer new];
        backLayer.backgroundColor = [UIColor blackColor].CGColor;
        objc_setAssociatedObject(self, &backgroundLayerKey, backLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return backLayer;
}

- (void)setJp_playingProgressValue:(CGFloat)jp_playingProgressValue{
    objc_setAssociatedObject(self, &playingProgressValueKey, @(jp_playingProgressValue), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)jp_playingProgressValue{
    return [objc_getAssociatedObject(self, &playingProgressValueKey) floatValue];
}

- (void)setJp_downloadProgressValue:(CGFloat)jp_downloadProgressValue{
    objc_setAssociatedObject(self, &downloadProgressValueKey, @(jp_downloadProgressValue), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)jp_downloadProgressValue{
    return [objc_getAssociatedObject(self, &downloadProgressValueKey) floatValue];
}

- (void)setProgressViewTintColor:(UIColor *)progressViewTintColor{
    objc_setAssociatedObject(self, &progressViewTintColorKey, progressViewTintColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIColor *)progressViewTintColor{
    UIColor *color = objc_getAssociatedObject(self, &progressViewTintColorKey);
    if (!color) {
        color = [UIColor colorWithRed:0.0/255 green:118.0/255 blue:255.0/255 alpha:1];
    }
    return color;
}

- (void)setProgressViewBackgroundColor:(UIColor *)progressViewBackgroundColor{
    objc_setAssociatedObject(self, &progressViewBackgroundColorKey, progressViewBackgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIColor *)progressViewBackgroundColor{
    UIColor *color = objc_getAssociatedObject(self, &progressViewTintColorKey);
    if (!color) {
        color = [UIColor colorWithRed:155.0/255 green:155.0/255 blue:155.0/255 alpha:1.0];
    }
    return color;
}

- (JPVideoPlayerProgressView *)progressView{
    JPVideoPlayerProgressView *progressView = objc_getAssociatedObject(self, &progressViewKey);
    if (!progressView) {
        progressView = [JPVideoPlayerProgressView new];
        progressView.hidden = YES;
        [self layoutProgressViewForPortrait:progressView];
        [progressView perfersDownloadProgressViewColor:self.progressViewBackgroundColor];
        [progressView perfersPlayingProgressViewColor:self.progressViewTintColor];
        progressView.backgroundColor = [UIColor clearColor];
        objc_setAssociatedObject(self, &progressViewKey, progressView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return nil;
}

- (JPVideoPlayerActivityIndicator *)activityIndicatorView{
    JPVideoPlayerActivityIndicator *acv = objc_getAssociatedObject(self, &activityIndicatorViewKey);
    if (!acv) {
        acv = [JPVideoPlayerActivityIndicator new];
        [self layoutActivityIndicatorViewForPortrait:acv];
        acv.hidden = YES;
        objc_setAssociatedObject(self, &activityIndicatorViewKey, acv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return nil;
}

- (UIView *)jp_videoLayerView{
    UIView *view = objc_getAssociatedObject(self, &videoLayerViewKey);
    if (!view) {
        view = [UIView new];
        view.frame = self.bounds;
        view.backgroundColor = [UIColor clearColor];
        view.userInteractionEnabled = NO;
        objc_setAssociatedObject(self, &videoLayerViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return nil;
}


#pragma mark - Landscape Events

- (void)layoutProgressViewForPortrait:(UIView *)progressView{
    CGFloat progressViewY = self.frame.size.height - JPVideoPlayerLayerFrameY;
    if ([self.jp_videoPlayerDelegate respondsToSelector:@selector(shouldProgressViewOnTop)] && [self.jp_videoPlayerDelegate shouldProgressViewOnTop]) {
        progressViewY = 0;
    }
    progressView.frame = CGRectMake(0, progressViewY, self.frame.size.width, JPVideoPlayerLayerFrameY);
}

- (void)layoutProgressViewForLandscape:(UIView *)progressView{
    CGFloat width = CGRectGetHeight(self.superview.bounds);
    CGFloat hei = CGRectGetWidth(self.superview.bounds);
    CGFloat progressViewY = hei - JPVideoPlayerLayerFrameY;
    if ([self.jp_videoPlayerDelegate respondsToSelector:@selector(shouldProgressViewOnTop)] && [self.jp_videoPlayerDelegate shouldProgressViewOnTop]) {
        progressViewY = 0;
    }
    progressView.frame = CGRectMake(0, progressViewY, width, hei);
}

- (void)layoutActivityIndicatorViewForPortrait:(UIView *)acv{
    CGSize viewSize = self.frame.size;
    CGFloat selfX = (viewSize.width-JPVideoPlayerActivityIndicatorWH)*0.5;
    CGFloat selfY = (viewSize.height-JPVideoPlayerActivityIndicatorWH)*0.5;
    acv.frame = CGRectMake(selfX, selfY, JPVideoPlayerActivityIndicatorWH, JPVideoPlayerActivityIndicatorWH);
}

- (void)layoutActivityIndicatorViewForLandscape:(UIView *)acv{
    CGFloat width = CGRectGetHeight(self.superview.bounds);
    CGFloat hei = CGRectGetWidth(self.superview.bounds);
    CGFloat selfX = (width-JPVideoPlayerActivityIndicatorWH)*0.5;
    CGFloat selfY = (hei-JPVideoPlayerActivityIndicatorWH)*0.5;
    acv.frame = CGRectMake(selfX, selfY, JPVideoPlayerActivityIndicatorWH, JPVideoPlayerActivityIndicatorWH);
}

@end

@implementation NSFileHandle (MCCacheSupport)

- (BOOL)jp_safeWriteData:(NSData *)data {
    NSInteger retry = 3;
    size_t bytesLeft = data.length;
    const void *bytes = [data bytes];
    int fileDescriptor = [self fileDescriptor];
    while (bytesLeft > 0 && retry > 0) {
        ssize_t amountSent = write(fileDescriptor, bytes + data.length - bytesLeft, bytesLeft);
        if (amountSent < 0) {
            // write failed.
            JPErrorLog(@"Write file failed");
            break;
        }
        else {
            bytesLeft = bytesLeft - amountSent;
            if (bytesLeft > 0) {
                // not finished continue write after sleep 1 second.
                JPWarningLog(@"Write file retry");
                sleep(1);  //probably too long, but this is quite rare.
                retry--;
            }
        }
    }
    return bytesLeft == 0;
}

@end
