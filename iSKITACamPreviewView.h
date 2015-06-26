//
//  iSKITACamPreviewView.h
//  iSKITACam
//
//  Created by htaiwan on 2014/4/7.
//  Copyright (c) 2014年 htaiwan. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AVCaptureSession;

@interface iSKITACamPreviewView : UIView

@property (nonatomic) AVCaptureSession *session;

@end
