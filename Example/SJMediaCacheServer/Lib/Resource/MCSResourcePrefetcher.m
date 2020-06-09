//
//  MCSResourcePrefetcher.m
//  SJMediaCacheServer_Example
//
//  Created by BlueDancer on 2020/6/8.
//  Copyright © 2020 changsanjiang@gmail.com. All rights reserved.
//

#import "MCSResourcePrefetcher.h"
#import "MCSResource.h"
#import "MCSResourceReader.h"
#import "MCSResource+MCSPrivate.h"
#import "MCSLogger.h"
#import "NSURLRequest+MCS.h"

@interface MCSResourcePrefetcher ()<NSLocking, MCSResourceReaderDelegate> {
    NSRecursiveLock *_lock;
}

@property (nonatomic, weak) MCSResource *resource;
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic) BOOL isCalledPrepare;
@property (nonatomic) BOOL isPrepared;
@property (nonatomic) BOOL isFinished;
@property (nonatomic) BOOL isClosed;
@property (nonatomic, strong, nullable) MCSResourceReader *reader;
@property (nonatomic) NSUInteger offset;
@end

@implementation MCSResourcePrefetcher
- (instancetype)initWithResource:(__weak MCSResource *)resource request:(NSURLRequest *)request {
    self = [super init];
    if ( self ) {
        _resource = resource;
        _request = request;
        _lock = NSRecursiveLock.alloc.init;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@:<%p> { range: %@\n };", NSStringFromClass(self.class), self, NSStringFromRange(_request.mcs_range)];
}

- (void)dealloc {
    MCSLog(@"%@: <%p>.dealloc;\n", NSStringFromClass(self.class), self);
}

- (void)prepare {
    [self lock];
    @try {
        if ( _isClosed || _isCalledPrepare )
            return;
        
        MCSLog(@"%@: <%p>.prepare { range: %@ };\n", NSStringFromClass(self.class), self, NSStringFromRange(_request.mcs_range));

        _reader = [_resource readerWithRequest:_request];
        _reader.delegate = self;
        [_reader prepare];
        
    } @catch (__unused NSException *exception) {
        
    } @finally {
        [self unlock];
    }
}

- (void)close {
    [self lock];
    @try {
        if ( _isClosed )
            return;
        
        _isClosed = YES;
        [_reader close];
        
        MCSLog(@"%@: <%p>.close { range: %@ };\n", NSStringFromClass(self.class), self, NSStringFromRange(_request.mcs_range));
    } @catch (__unused NSException *exception) {
        
    } @finally {
        [self unlock];
    }
}

#pragma mark -

- (void)lock {
    [_lock lock];
}

- (void)unlock {
    [_lock unlock];
}

#pragma mark -

- (void)readerPrepareDidFinish:(id<MCSResourceReader>)reader {
    [self lock];
    @try {
        if ( _isPrepared )
            return;
        
        _isPrepared = YES;
        [_delegate prefetcherPrepareDidFinish:self];
    } @catch (__unused NSException *exception) {
        
    } @finally {
        [self unlock];
    }
    
    [self readerHasAvailableData:reader];
}

- (void)readerHasAvailableData:(id<MCSResourceReader>)reader {
    [self lock];
    @try {
        while (true) {
            @autoreleasepool {
                NSData *data = [_reader readDataOfLength:1 * 1024 * 1024];
                if ( data.length == 0 )
                    break;
                
                _offset += data.length;
                
                if ( _offset >= _request.mcs_range.length || _offset >= _resource.totalLength ) {
                    [self close];
                    [_delegate prefetcherPrefetchDidFinish:self];
                    break;
                }
            }
        }
    } @catch (__unused NSException *exception) {
        
    } @finally {
        [self unlock];
    }
}

- (void)reader:(id<MCSResourceReader>)reader anErrorOccurred:(NSError *)error {
    [_delegate prefetcher:self anErrorOccurred:error];
}

@end