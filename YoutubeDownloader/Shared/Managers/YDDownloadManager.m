//
//  YDDownloadManager.m
//  YoutubeDownloader
//
//  Created by Hao Wang  on 13-11-17.
//  Copyright (c) 2013年 HAO WANG. All rights reserved.
//

#import "YDDownloadManager.h"
#import "DownloadTask.h"
#import "Video.h"
#import "YDMedia.h"
#import "YDFileUtil.h"
#import "AFNetworking.h"

@interface YDDownloadManager ()
{
    NSTimer *_refreshPlayStatusTimer;
    
}

@property (atomic, strong)      NSNumber *downloadTaskID;
@property (atomic, strong)      AFURLConnectionOperation *downloadOperation;

@end

@implementation YDDownloadManager

+ (YDDownloadManager *)sharedInstance
{
    static YDDownloadManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YDDownloadManager alloc] init];
    });
    return instance;
}

- (void)stopRefreshTimer
{
    if (_refreshPlayStatusTimer)
    {
        [_refreshPlayStatusTimer invalidate];
        _refreshPlayStatusTimer = nil;
    }
}

- (void)startRefreshTimer
{
    [self  stopRefreshTimer];
    _refreshPlayStatusTimer = [NSTimer timerWithTimeInterval:10 target:self selector:@selector(checkNewDownloadTask:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_refreshPlayStatusTimer forMode:NSRunLoopCommonModes];
    
}

- (void)checkNewDownloadTask:(NSTimer*)timer
{
    if (self.downloadTaskID)
    {
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.downloadTaskID)
        {
            return;
        }
        
        NSManagedObjectContext *privateQueueContext = [NSManagedObjectContext MR_contextForCurrentThread];
        DownloadTask   *downloadingTask = [DownloadTask getDownloadingTaskInContext:privateQueueContext];
        if (!downloadingTask) {
            downloadingTask = [DownloadTask getWaitingDownloadTaskInContext:privateQueueContext];
        }
        
        if (downloadingTask)
        {
            self.downloadTaskID = downloadingTask.downloadID;
            downloadingTask.downloadTaskStatus = @(DownloadTaskDownloading);
            NSString *downloadUrl = downloadingTask.videoDownloadUrl;
            [downloadingTask updateWithContext:privateQueueContext completion:^(BOOL success, NSError *error) {
                if (![self createBackgroundTaskWithUrl:downloadUrl])
                {
                    [self setDownloadTaskStatus:NO];
                }
                
             }];
        }
    
    });
}

- (void)createDownloadTaskWithDownloadPageUrl:(NSString*)downloadPageUrl qualityType:(NSString*)qualityType videoDescription:(NSString*)videoDescription videoTitle:(NSString*)videoTitle videoDownloadUrl:(NSString*)videoDownloadUrl inContext:(NSManagedObjectContext *)context completion:(void(^)(BOOL success))completion
{
    DownloadTask *task = [DownloadTask createDownloadTaskInContext:context];
    if (!task)
    {
        if (completion)
            completion(NO);
        return;
    }
    
    task.downloadPageUrl = downloadPageUrl;
	task.downloadPriority = DOWNLOAD_TASK_DEFAULT_PRIORITY;
	task.downloadTaskStatus = @(DownloadTaskWaiting);
	task.qualityType = qualityType;
    task.videoTitle = videoTitle;
	task.videoDescription = videoDescription;
	task.videoImagePath = nil;
	task.videoDownloadUrl = videoDownloadUrl;
    [context MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        if (completion)
        {
            completion(YES);
        }
    }];
}

- (BOOL)createBackgroundTaskWithUrl:(NSString*)url
{
    
    if (![url hasPrefix:@"http"] && ![url hasPrefix:@"https"])
    {
        return NO;
    }
    NSURL *downloadUrl = [NSURL URLWithString:url];
    NSURLRequest *requestVid = [NSURLRequest requestWithURL:downloadUrl];
    __weak YDDownloadManager *weakSelf = self;
    self.downloadOperation = [[AFHTTPRequestOperation alloc] initWithRequest:requestVid];
    self.downloadOperation.outputStream = [NSOutputStream outputStreamToFileAtPath:[self getCurrentDownloadFileDestPath] append:NO];
    [self.downloadOperation setCompletionBlock:^{
        [weakSelf setDownloadTaskStatus:YES];
    }];
    
    [self.downloadOperation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
        float currentProgress = totalBytesExpectedToRead > 0 ? (float)totalBytesRead / totalBytesExpectedToRead : 0.0;
        NSManagedObjectContext *privateQueueContext = [NSManagedObjectContext MR_contextForCurrentThread];
        DownloadTask *downloadingTask = [DownloadTask findByDownloadID:weakSelf.downloadTaskID inContext:privateQueueContext];
        if (downloadingTask) {
            downloadingTask.downloadProgress = @(currentProgress);
            [downloadingTask updateWithContext:privateQueueContext completion:^(BOOL success, NSError *error) {
            }];
        }
    }];
   
    [self.downloadOperation start];
 
    return YES;
}

- (void)createCurrentDownloadVideoThumbWithDownloadTask:(DownloadTask*)downloadTask
{
    YDMedia *media = [[YDMedia alloc] init];
    media.mediaType = ALAssetTypeVideo;
    media.mediaUrl = [self getCurrentDownloadFileDestPath];
    [media duration];
    NSString *imagePath = [[YDFileUtil documentDirectoryPath] stringByAppendingPathComponent:@"images"];
    [YDFileUtil createAbsoluteDirectory:imagePath];
    NSString *imageFileName = [NSString stringWithFormat:@"%@.jpeg", self.downloadTaskID];
    NSString *imageFilePath = [imagePath stringByAppendingPathComponent:imageFileName];
    [media getThumbnailImageWithCompletion:^(UIImage *thumbnail) {
        if (thumbnail)
        {
            NSData* imageData = UIImageJPEGRepresentation(thumbnail, 1.0);
            [imageData writeToFile:imageFilePath atomically:YES];
            
        }
        NSManagedObjectContext * privateQueueContext = [NSManagedObjectContext MR_contextForCurrentThread];
        DownloadTask *downloadingTask = [DownloadTask findByDownloadID:self.downloadTaskID inContext:privateQueueContext];
        Video *video = [Video createVideoWithContext:privateQueueContext];
        video.createDate = [NSDate date];
        video.duration = @([media duration]);
        video.isNew = @(YES);
        video.isRemoved = @(NO);
        video.qualityType = downloadingTask.qualityType;
        video.videoDescription = downloadingTask.videoDescription;
        video.videoFilePath = media.mediaUrl;
        video.videoImagePath = imageFilePath;
        video.videoTitle = downloadingTask.videoTitle;
        [video updateWithContext:privateQueueContext completion:^(BOOL success, NSError *error) {
            self.downloadTaskID = nil;
            self.downloadOperation = nil;
        }];

    } WithWidth:80 height:80];
    
}

- (void)setDownloadTaskStatus:(BOOL)success
{
    NSManagedObjectContext *privateQueueContext = [NSManagedObjectContext MR_contextForCurrentThread];
    DownloadTask *downloadingTask = [DownloadTask findByDownloadID:self.downloadTaskID inContext:privateQueueContext];
    if (success) {
        downloadingTask.downloadTaskStatus = @(DownloadTaskFinished);
    }
    else {
        downloadingTask.downloadTaskStatus = @(DownloadTaskFailed);
    }
    
    if (!success)
    {
        [downloadingTask updateWithContext:privateQueueContext completion:^(BOOL success, NSError *error) {
            self.downloadTaskID = nil;
            self.downloadOperation = nil;
        }];
        return;
    }
    [downloadingTask updateWithContext:privateQueueContext completion:^(BOOL success, NSError *error) {
        [self createCurrentDownloadVideoThumbWithDownloadTask:downloadingTask];
    }];
    
}

- (NSString*)getCurrentDownloadFileDestPath
{
    NSString *videoDirectory = [[YDFileUtil documentDirectoryPath] stringByAppendingPathComponent:@"videos"];
    [YDFileUtil createAbsoluteDirectory:videoDirectory];
    NSManagedObjectContext *privateQueueContext = [NSManagedObjectContext MR_contextForCurrentThread];
    DownloadTask   *downloadingTask = [DownloadTask getDownloadingTaskInContext:privateQueueContext];
    NSString *fileName = [NSString stringWithFormat:@"%d.mp4",downloadingTask.downloadIDValue];
    return [videoDirectory stringByAppendingPathComponent:fileName];
}

-(void)cancelDownloadTaskWithID:(NSNumber *)downloadID
{
    if (!self.downloadTaskID)
        return;
    
    if (![self.downloadTaskID isEqualToNumber:downloadID])
        return;
    
    if (self.downloadOperation)
    {
        [self.downloadOperation cancel];
        self.downloadOperation = nil;
    }
}

@end
