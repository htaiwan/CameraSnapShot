//
//  iSKITACamViewController.h
//  iSKITACam
//
//  Created by htaiwan on 2014/4/7.
//  Copyright (c) 2014年 htaiwan. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "RIOInterface.h"
#import "KeyHelper.h"

@class RIOInterface;

@interface iSKITACamViewController : UIViewController

@property(nonatomic, retain) NSMutableString *key;
@property(nonatomic, retain) NSString *prevChar;
@property(nonatomic, assign) RIOInterface *rioRef;
@property(nonatomic, assign) float currentFrequency;
@property(assign) BOOL isListening;

- (void)startListener;
- (void)stopListener;

- (void)frequencyChangedWithValue:(float)newFrequency;
- (void)updateFrequencyLabel;

@end
