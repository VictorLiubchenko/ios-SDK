//
//  BackendlessFile.m
//  backendlessAPI
/*
 * *********************************************************************************************************************
 *
 *  BACKENDLESS.COM CONFIDENTIAL
 *
 *  ********************************************************************************************************************
 *
 *  Copyright 2018 BACKENDLESS.COM. All Rights Reserved.
 *
 *  NOTICE: All information contained herein is, and remains the property of Backendless.com and its suppliers,
 *  if any. The intellectual and technical concepts contained herein are proprietary to Backendless.com and its
 *  suppliers and may be covered by U.S. and Foreign Patents, patents in process, and are protected by trade secret
 *  or copyright law. Dissemination of this information or reproduction of this material is strictly forbidden
 *  unless prior written permission is obtained from Backendless.com.
 *
 *  ********************************************************************************************************************
 */

#import "BackendlessFile.h"
#import "Backendless.h"

@implementation BackendlessFile

-(id)init {
	if (self = [super init]) {
        _fileURL = nil;
	}
	return self;
}

-(id)initWithUrl:(NSString *)url {
	if (self = [super init]) {
        _fileURL = [url retain];
	}
	return self;
}

-(void)dealloc {
	[DebLog logN:@"DEALLOC BackendlessFile"];
    [_fileURL release];
	[super dealloc];
}

+(id)file:(NSString *)url {
    return [[[BackendlessFile alloc] initWithUrl:url] autorelease];
}

-(NSNumber *)remove {
    return [backendless.fileService remove:_fileURL];
}

-(void)remove:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    [backendless.fileService remove:_fileURL response:responseBlock error:errorBlock];
}

-(NSString *)description {
    return [NSString stringWithFormat:@"<BackendlessFile> -> fileURL: %@", _fileURL];
}

@end
