/*
 * This file is part of the JPVideoPlayer package.
 * (c) NewPan <13246884282@163.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 *
 * Click https://github.com/Chris-Pan
 * or http://www.jianshu.com/users/e2f2d779c022/latest_articles to contact me.
 */

#import "JPVideoPlayerResourceLoader.h"
#import "JPVideoPlayerCompat.h"
#import "JPVideoPlayerCacheFile.h"
#import "JPVideoPlayerCachePath.h"
#import "JPVideoPlayerManager.h"
#import "JPResourceLoadingRequestTask.h"

@interface JPVideoPlayerResourceLoader()<JPResourceLoadingRequestTaskDelegate>

/**
 * The request queues.
 * It save the requests waiting for being given video data.
 */
@property (nonatomic, strong, nullable)NSMutableArray<AVAssetResourceLoadingRequest *> *pendingRequests;

@property (nonatomic, strong) JPVideoPlayerCacheFile *cacheFile;

@property (nonatomic, strong) NSHTTPURLResponse *response;

@property (nonatomic, strong) JPResourceLoadingRequestTask *requestTask;

@end

static const NSString *const kJPVideoPlayerContentRangeKey = @"Content-Range";
@implementation JPVideoPlayerResourceLoader

- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

+ (instancetype)resourceLoaderWithCustomURL:(NSURL *)customURL {
    return [[JPVideoPlayerResourceLoader alloc] initWithCustomURL:customURL];
}

- (instancetype)initWithCustomURL:(NSURL *)customURL {
    NSParameterAssert(customURL);
    if(!customURL){
        return nil;
    }

    self = [super init];
    if(self){
        _customURL = customURL;
        _pendingRequests = [@[] mutableCopy];
        NSString *key = [JPVideoPlayerManager.sharedManager cacheKeyForURL:customURL];
        _cacheFile = [JPVideoPlayerCacheFile cacheFileWithFilePath:[JPVideoPlayerCachePath videoCacheTemporaryPathForKey:key]
                                                     indexFilePath:[JPVideoPlayerCachePath videoCacheIndexSavePathForKey:key]];
    }
    return self;
}


#pragma mark - AVAssetResourceLoaderDelegate

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader
shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest{
    if (resourceLoader && loadingRequest){
        [self.pendingRequests addObject:loadingRequest];
        JPDebugLog(@"ResourceLoader received a new loadingRequest, current loadingRequest number is: %ld", self.pendingRequests.count);
        if (self.requestTask.loadingRequest && !self.requestTask.loadingRequest.isFinished) {
            JPDebugLog(@"Call delegate until downloder cancel the current task");
            // Cancel current request task, and then receive message on `requestTask:didCompleteWithError:`
            // to start next request.
            if (self.delegate && [self.delegate respondsToSelector:@selector(resourceLoader:didCancelLoadingRequestTask:)]) {
                [self.delegate resourceLoader:self didCancelLoadingRequestTask:self.requestTask];
            }
        }
        else {
            JPDebugLog(@"Send new task immediately because have no current task");
            [self findAndStartNextRequestIfNeed];
        }
    }
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader
didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest{
    if (self.requestTask.loadingRequest == loadingRequest) {
        JPDebugLog(@"Cancel a loading Request that loading");
        [self removeCurrentRequestTaskAnResetAll];
    }
    else {
        JPDebugLog(@"Remove a loading Request that not loading");
        [self.pendingRequests removeObject:loadingRequest];
    }
}


#pragma mark - Private

- (void)findAndStartNextRequestIfNeed {
    if (self.requestTask.loadingRequest || self.pendingRequests.count == 0) {
        return;
    }

    AVAssetResourceLoadingRequest *loadingRequest = [self.pendingRequests firstObject];
    NSRange dataRange;
    // data range.
    if ([loadingRequest.dataRequest respondsToSelector:@selector(requestsAllDataToEndOfResource)] && loadingRequest.dataRequest.requestsAllDataToEndOfResource) {
        dataRange = NSMakeRange((NSUInteger)loadingRequest.dataRequest.requestedOffset, NSUIntegerMax);
    }
    else {
        dataRange = NSMakeRange((NSUInteger)loadingRequest.dataRequest.requestedOffset, loadingRequest.dataRequest.requestedLength);
    }

    // response.
    if (!self.response && self.cacheFile.responseHeaders.count > 0) {
        if (dataRange.length == NSUIntegerMax) {
            dataRange.length = [self.cacheFile fileLength] - dataRange.location;
        }

        NSMutableDictionary *responseHeaders = [self.cacheFile.responseHeaders mutableCopy];
        BOOL supportRange = responseHeaders[kJPVideoPlayerContentRangeKey] != nil;
        if (supportRange && JPValidByteRange(dataRange)) {
            responseHeaders[kJPVideoPlayerContentRangeKey] = JPRangeToHTTPRangeReponseHeader(dataRange, [self.cacheFile fileLength]);
        }
        else {
            [responseHeaders removeObjectForKey:kJPVideoPlayerContentRangeKey];
        }
        responseHeaders[@"Content-Length"] = [NSString stringWithFormat:@"%tu", dataRange.length];
        NSInteger statusCode = supportRange ? 206 : 200;
        self.response = [[NSHTTPURLResponse alloc] initWithURL:loadingRequest.request.URL
                                                    statusCode:statusCode
                                                   HTTPVersion:@"HTTP/1.1"
                                                  headerFields:responseHeaders];
        [loadingRequest jp_fillContentInformationWithResponse:self.response];
    }

    if(loadingRequest){
        [self startCurrentRequestWithLoadingRequest:loadingRequest
                                              range:dataRange];
    }
}

- (void)startCurrentRequestWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                                        range:(NSRange)dataRange {
    if (dataRange.length == NSUIntegerMax) {
        [self addTaskWithLoadingRequest:loadingRequest
                                  range:NSMakeRange(dataRange.location, NSUIntegerMax)
                                 cached:NO];
    }
    else {
        NSUInteger start = dataRange.location;
        NSUInteger end = NSMaxRange(dataRange);
        while (start < end) {
            NSRange firstNotCachedRange = [self.cacheFile firstNotCachedRangeFromPosition:start];
            if (!JPValidFileRange(firstNotCachedRange)) {
                JPDebugLog(@"Never cached for dataRange, request data from web, while circle over, dataRange is: %@", NSStringFromRange(dataRange));
                [self addTaskWithLoadingRequest:loadingRequest
                                          range:dataRange
                                         cached:self.cacheFile.cachedDataBound > 0];
                start = end;
            }
            else if (firstNotCachedRange.location >= end) {
                JPDebugLog(@"All data did cache for dataRange, fetch data from disk, while circle over, dataRange is: %@", NSStringFromRange(dataRange));
                [self addTaskWithLoadingRequest:loadingRequest
                                          range:dataRange
                                         cached:YES];
                start = end;
            }
            else if (firstNotCachedRange.location >= start) {
                if (firstNotCachedRange.location > start) {
                    JPDebugLog(@"Part of the data did cache for dataRange, fetch data from disk, dataRange is: %@", NSStringFromRange(NSMakeRange(start, firstNotCachedRange.location - start)));
                    [self addTaskWithLoadingRequest:loadingRequest
                                              range:NSMakeRange(start, firstNotCachedRange.location - start)
                                             cached:YES];
                }
                NSUInteger notCachedEnd = MIN(NSMaxRange(firstNotCachedRange), end);
                JPDebugLog(@"Part of the data did not cache for dataRange, request data from web, while circle over, dataRange is: %@", NSStringFromRange(NSMakeRange(firstNotCachedRange.location, notCachedEnd - firstNotCachedRange.location)));
                [self addTaskWithLoadingRequest:loadingRequest
                                          range:NSMakeRange(firstNotCachedRange.location, notCachedEnd - firstNotCachedRange.location)
                                         cached:NO];
                start = notCachedEnd;
            }
            else {
                JPDebugLog(@"Other situation for creating task, while circle over, dataRange is: %@", NSStringFromRange(dataRange));
                [self addTaskWithLoadingRequest:loadingRequest
                                          range:dataRange
                                         cached:YES];
                start = end;
            }
        }
    }
}

- (void)addTaskWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                            range:(NSRange)range
                           cached:(BOOL)cached {
    JPResourceLoadingRequestTask *task = [JPResourceLoadingRequestTask requestTaskWithLoadingRequest:loadingRequest
                                                                                        requestRange:range
                                                                                           cacheFile:self.cacheFile
                                                                                           customURL:self.customURL];
    task.delegate = self;
    self.requestTask = task;
    if (!cached) {
        task.response = self.response;
    }
    
    JPDebugLog(@"Creat a new request task");
    JPDispatchSyncOnMainQueue(^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(resourceLoader:didReceiveLoadingRequestTask:)]) {
            [self.delegate resourceLoader:self didReceiveLoadingRequestTask:task];
        }
    });
}

- (void)removeCurrentRequestTaskAnResetAll {
    [self.pendingRequests removeObject:self.requestTask.loadingRequest];
    self.response = nil;
    self.requestTask = nil;
    JPDebugLog(@"Remove current request task, current loadingRequest number is: %ld", self.pendingRequests.count);
}


#pragma mark - JPResourceLoadingRequestTaskDelegate

- (void)requestTask:(JPResourceLoadingRequestTask *)requestTask
didCompleteWithError:(NSError *)error {
    if (requestTask.isCancelled || error.code == NSURLErrorCancelled) {
        // Cancel current request task, and then receive message on `requestTask:didCompleteWithError:`
        // to start next request.
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorCancelled
                                         userInfo:nil];
        JPDebugLog(@"Downloader cancel the current task, then resource loader send new task");
        [self finishCurrentRequestWithError:error];
        return;
    }

    if (error) {
        [self finishCurrentRequestWithError:error];
    }
    else {
        [self finishCurrentRequestWithError:nil];
    }
}


#pragma mark - Finish Request

- (void)finishCurrentRequestWithError:(NSError *)error {
    if (error) {
        JPDebugLog(@"Finish loading request with error: %@", error);
        [self.requestTask.loadingRequest finishLoadingWithError:error];
    }
    else {
        JPDebugLog(@"Finish loading request with no error");
        [self.requestTask.loadingRequest finishLoading];
    }
    [self removeCurrentRequestTaskAnResetAll];
    [self findAndStartNextRequestIfNeed];
}

@end