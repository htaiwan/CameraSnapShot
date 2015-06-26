//
//  iSKITACamPreviewView.m
//  iSKITACam
//
//  Created by htaiwan on 2014/4/7.
//  Copyright (c) 2014年 htaiwan. All rights reserved.
//

#import "iSKITACamPreviewView.h"
#import <AVFoundation/AVFoundation.h>


@implementation iSKITACamPreviewView

+ (Class)layerClass
{
	return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)session
{
	return [(AVCaptureVideoPreviewLayer *)[self layer] session];
}

- (void)setSession:(AVCaptureSession *)session
{
	[(AVCaptureVideoPreviewLayer *)[self layer] setSession:session];
}

@end
