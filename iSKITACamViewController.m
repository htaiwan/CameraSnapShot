//
//  iSKITACamViewController.m
//  iSKITACam
//
//  Created by htaiwan on 2014/4/7.
//  Copyright (c) 2014年 htaiwan. All rights reserved.
//

#import "iSKITACamViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "iSKITACamPreviewView.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import "PhotoViewController.h"
#import "UIImage+Crop.h"
//#import "XHMediaZoom.h"




#define kValue 10  // kvalue = 5 (單鍵指令) kvalue = 10 (學習模式)
#define KBackLightTime 120  // 背光消失時間

#define iPhone5 ([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(640, 1136), [[UIScreen mainScreen] currentMode].size) : NO)


static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * RecordingContext = &RecordingContext;
static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;

@interface iSKITACamViewController () <AVCaptureFileOutputRecordingDelegate,UIGestureRecognizerDelegate,UIImagePickerControllerDelegate,UINavigationControllerDelegate,UIAlertViewDelegate>
{
    CGFloat effectiveScale;
    int timerCount;  // 控制倒數拍照
    AVCaptureFlashMode flashMode;
    NSTimeInterval intervel;
    NSTimer *timer1; // 倒數拍照
    NSTimer *timer2; // 背光關閉
    NSTimer *timer3; // 計算錄影時間
    
    NSMutableArray *array1;  // 記錄learing model的結果
    NSMutableArray *array2;
    BOOL flag; // 判斷是否為new key
    int tmpCount1; // 記錄上個階段array1的count值
    int tmpCount2; // 記錄目前非有效的pitch的數量
    float pitchLevel;
    int flashStatus; // 記錄上個閃光燈狀態
    
    int timeCount; // 計算背光時間
    int recordCount; // 計算錄影時間

    BOOL lineStatus; // 記住隔線狀態
    BOOL recordStatus; // 顯示錄影狀態

}

//@property (strong, nonatomic) UIImageView *imageView;
//@property (strong, nonatomic) XHMediaZoom *imageZoomView;


@property UIImageView *focusImageView;
@property (weak, nonatomic) IBOutlet UIView *hiddenView;
@property (weak, nonatomic) IBOutlet UIView *iphone5View;

@property (weak, nonatomic) IBOutlet iSKITACamPreviewView *previewView;
@property (weak, nonatomic) IBOutlet UIButton *stillButton;
@property (weak, nonatomic) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UIButton *functionButton;
@property (weak, nonatomic) IBOutlet UIButton *zoomButton;
@property (weak, nonatomic) IBOutlet UIButton *positionButton;
@property (weak, nonatomic) IBOutlet UIButton *flashButton;
@property (weak, nonatomic) IBOutlet UIButton *lineButton;
@property (weak, nonatomic) IBOutlet UIButton *timerButton;
@property (weak, nonatomic) IBOutlet UIButton *brightneeButton;
@property (weak, nonatomic) IBOutlet UIImageView *priveImageView;



- (IBAction)toggleVoiceControl:(UISwitch *)sender;
- (IBAction)toggleMovieRecording:(UIButton *)sender;
- (IBAction)toggleFlashControl:(UIButton *)sender;
- (IBAction)toggleSeperateLine:(UIButton *)sender;
- (IBAction)toggleTimerControl:(UIButton *)sender;
- (IBAction)toggleBrightness:(UIButton *)sender;

- (IBAction)snapStillImage:(UIButton *)sender;
- (IBAction)changeMode:(UIButton *)sender;
- (IBAction)zoom:(UIButton *)sender;
- (IBAction)focusAndExposeTap:(UITapGestureRecognizer *)sender;
- (IBAction)changePosition:(UIButton *)sender;

@property (weak, nonatomic) IBOutlet UILabel *currentPitchLabel;
@property (weak, nonatomic) IBOutlet UILabel *modeLabel;
@property (weak, nonatomic) IBOutlet UILabel *zoomLabel;
@property (weak, nonatomic) IBOutlet UILabel *timerLabel;
@property (weak, nonatomic) IBOutlet UILabel *batteryLabel;
@property (weak, nonatomic) IBOutlet UILabel *recordTimeLabel;

@property (weak, nonatomic) IBOutlet UIImageView *modelImageView;
@property (weak, nonatomic) IBOutlet UIImageView *zoomImageView;
@property (weak, nonatomic) IBOutlet UIImageView *functionImageView;
@property (weak, nonatomic) IBOutlet UIImageView *bigmodelImageView;
@property (weak, nonatomic) IBOutlet UIImageView *batteryLevelImageView;
//@property (weak, nonatomic) IBOutlet UIView *seperateView;



// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue; // Communicate with the session and other session objects on this queue.
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;

// Utilities.
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic) BOOL lockInterfaceRotation;
@property (nonatomic) id runtimeErrorHandlingObserver;


@end

@implementation iSKITACamViewController

- (BOOL)isSessionRunningAndDeviceAuthorized
{
	return [[self session] isRunning] && [self isDeviceAuthorized];
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
	return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

#pragma mark - life Cycle
- (void)viewDidLoad
{
    [super viewDidLoad];

    // 設定相機模式參數
    // Create the AVCaptureSession
	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	[self setSession:session];
    
    // Setup the preview view
	[[self previewView] setSession:session];
    
    // Check for device authorization
	[self checkDeviceAuthorizationStatus];
    
    dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
	[self setSessionQueue:sessionQueue];
    
    dispatch_async(sessionQueue, ^{
        [self setBackgroundRecordingID:UIBackgroundTaskInvalid];
        
        NSError *error = nil;
		
		AVCaptureDevice *videoDevice = [iSKITACamViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        if (error)
		{
			NSLog(@"%@", error);
		}
        
        if ([session canAddInput:videoDeviceInput])
        {
            [session addInput:videoDeviceInput];
			[self setVideoDeviceInput:videoDeviceInput];
            
			dispatch_async(dispatch_get_main_queue(), ^{
				[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)[self interfaceOrientation]];
			});
        }
        
        AVCaptureDevice *audioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
		AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
		
		if (error)
		{
			NSLog(@"%@", error);
		}
		
		if ([session canAddInput:audioDeviceInput])
		{
			[session addInput:audioDeviceInput];
		}

        AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
		if ([session canAddOutput:movieFileOutput])
		{
			[session addOutput:movieFileOutput];
			AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
			if ([connection isVideoStabilizationSupported])
				[connection setEnablesVideoStabilizationWhenAvailable:YES];
			[self setMovieFileOutput:movieFileOutput];
		}
        
        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
		if ([session canAddOutput:stillImageOutput])
		{
			[stillImageOutput setOutputSettings:@{AVVideoCodecKey : AVVideoCodecJPEG}];
			[session addOutput:stillImageOutput];
			[self setStillImageOutput:stillImageOutput];
		}
    });
    
    
    effectiveScale = 1.0;
    timerCount = 1;
    flashMode = AVCaptureFlashModeOff;
    intervel = 0;
    
    // Tap to focus indicator
    // -------------------------------------
    UIImage *defaultImage   = [UIImage imageNamed:@"focus_indicator@2x.png"];
    _focusImageView         = [[UIImageView alloc] initWithImage:defaultImage];
    self.focusImageView.frame   = CGRectMake(0, 0, defaultImage.size.width, defaultImage.size.height);
    self.focusImageView.hidden = YES;
    [self.view addSubview:self.focusImageView];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longPressTap:)];
    [self.stillButton addGestureRecognizer:longPress];
    
    UITapGestureRecognizer *tap1 = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(openPhotoAlbum:)];
    [self.priveImageView addGestureRecognizer:tap1];
    self.priveImageView.userInteractionEnabled = YES;
    
    //電池量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    [self updateBatteryLevel];
    [[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(batteryLevelChanged:)
												 name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    
    
    // 設定音控模式參數
    self.rioRef = [RIOInterface sharedInstance];
    [self.rioRef setSampleRate:44100];
	[self.rioRef setFrequency:294];
	[self.rioRef initializeAudioSession];
    
    array1 = [NSMutableArray new];
    array2 = [NSMutableArray new];
    
    pitchLevel = 13000.0;
    flag = YES;
    tmpCount1 = 0;
    tmpCount2 = 0;
    lineStatus = NO;
    recordCount = 0;
    flashStatus = 0;
    recordStatus = NO;
    
    // 調整背光亮度至最強
    [self timerStart];
    
    // 若是iphone5 調整拍照畫面大小
    if (iPhone5) {
        self.hiddenView.hidden = NO;
        self.iphone5View.hidden = NO;
    }
}


- (void)viewWillAppear:(BOOL)animated
{
    // 音控模式開啟
    if ([[NSUserDefaults standardUserDefaults]objectForKey:@"command"]==nil) {
//        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"尚未完成配對" message:@"是否要進行配對?" delegate:self cancelButtonTitle:@"否" otherButtonTitles:@"是",nil];
//        alert.tag = 100;
//       [alert show];
    }
    
    // 相機模式功能開啟
	dispatch_async([self sessionQueue], ^{
		[self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningAndDeviceAuthorizedContext];
		[self addObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:CapturingStillImageContext];
		[self addObserver:self forKeyPath:@"movieFileOutput.recording" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:RecordingContext];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
		
		__weak iSKITACamViewController *weakSelf = self;
		[self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self session] queue:nil usingBlock:^(NSNotification *note) {
			iSKITACamViewController *strongSelf = weakSelf;
			dispatch_async([strongSelf sessionQueue], ^{
				// Manually restarting the session since it must have been stopped due to an error.
				[[strongSelf session] startRunning];
				[[strongSelf recordButton] setTitle:NSLocalizedString(@"Record", @"Recording button record title") forState:UIControlStateNormal];
			});
		}]];
		[[self session] startRunning];
	});
}

- (void)viewDidDisappear:(BOOL)animated
{
	dispatch_async([self sessionQueue], ^{
		[[self session] stopRunning];
		
		[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
		[[NSNotificationCenter defaultCenter] removeObserver:[self runtimeErrorHandlingObserver]];
		
		[self removeObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" context:SessionRunningAndDeviceAuthorizedContext];
		[self removeObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" context:CapturingStillImageContext];
		[self removeObserver:self forKeyPath:@"movieFileOutput.recording" context:RecordingContext];
	});
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

//- (BOOL)shouldAutorotate
//{
//	// Disable autorotation of the interface when recording is in progress.
//	return ![self lockInterfaceRotation];
//}
//
//- (NSUInteger)supportedInterfaceOrientations
//{
//	return UIInterfaceOrientationMaskAll;
//}


- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)toInterfaceOrientation];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UIAlertView delegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(alertView.tag == 100){
        if (buttonIndex == 1) {
            // 開始配對
//            [MMProgressHUD setDisplayStyle:MMProgressHUDDisplayStyleBordered];
//            [MMProgressHUD showWithTitle:@"Bordered" status:@"Bordered Style"];
            // 開啟音控
            [self startListener];
        }
    }
}

#pragma mark - observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == CapturingStillImageContext)
	{
		BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
		
		if (isCapturingStillImage)
		{
			[self runStillImageCaptureAnimation];
		}
	}
    
    else if (context == RecordingContext)
	{
		BOOL isRecording = [change[NSKeyValueChangeNewKey] boolValue];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (isRecording)
			{
				[[self functionButton] setEnabled:NO];
                
//				[[self recordButton] setTitle:NSLocalizedString(@"停止", @"Recording button stop title") forState:UIControlStateNormal];
                // 錄影模式下關閉timer
                [self timerStop];
                self.zoomImageView.image = [UIImage imageNamed:@"錄影按鈕2.png"];
				[[self recordButton] setEnabled:YES];
                // 開始計算錄影時間
                self.recordTimeLabel.hidden = NO;
                timer3 = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateRecordLabel) userInfo:nil repeats: YES];
			}
			else
			{
				[[self functionButton] setEnabled:YES];
//				[[self recordButton] setTitle:NSLocalizedString(@"錄影", @"Recording button record title") forState:UIControlStateNormal];
                [self timerStart];
                self.zoomImageView.image = [UIImage imageNamed:@"錄影按鈕.png"];
				[[self recordButton] setEnabled:YES];
                self.recordTimeLabel.hidden = YES;
                [timer3 invalidate];
                timer3 = nil;
                recordCount = 0;
                
                // 擷取錄影的預覽圖
                [[self stillImageOutput] captureStillImageAsynchronouslyFromConnection:[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
                    
                    if (imageDataSampleBuffer)
                    {
                        NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                        UIImage *image = [[UIImage alloc] initWithData:imageData];
                        self.priveImageView.image = image; 
                    }
                }];
			}
		});
	}
    
    else if (context == SessionRunningAndDeviceAuthorizedContext)
	{
		BOOL isRunning = [change[NSKeyValueChangeNewKey] boolValue];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (isRunning)
			{
				[[self functionButton] setEnabled:YES];
				[[self recordButton] setEnabled:YES];
				[[self stillButton] setEnabled:YES];
                [[self zoomButton] setEnabled:YES];
                [[self positionButton] setEnabled:YES];
                [[self flashButton] setEnabled:YES];
                [[self lineButton] setEnabled:YES];
                [[self timerButton] setEnabled:YES];
                [[self brightneeButton] setEnabled:YES];
			}
			else
			{
				[[self functionButton] setEnabled:NO];
				[[self recordButton] setEnabled:NO];
				[[self stillButton] setEnabled:NO];
                [[self zoomButton] setEnabled:NO];
                [[self positionButton] setEnabled:NO];
                [[self flashButton] setEnabled:NO];
                [[self lineButton] setEnabled:NO];
                [[self timerButton] setEnabled:NO];
                [[self brightneeButton] setEnabled:NO];
			}
		});
	}
    
    else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark - button


- (IBAction)toggleVoiceControl:(UISwitch *)sender
{
    if (sender.on == YES) {
      [self startListener];
    }else {
       [self stopListener]; 
    }
}

- (IBAction)toggleMovieRecording:(UIButton *)sender
{
    if ([self.modeLabel.text isEqualToString:@"錄影模式"]) {
        [self snapStillImage:nil];
//        [[self recordButton] setEnabled:NO];
//        dispatch_async([self sessionQueue], ^{
//            if (![[self movieFileOutput] isRecording])
//            {
//                [self setLockInterfaceRotation:YES];
//                
//                if ([[UIDevice currentDevice] isMultitaskingSupported])
//                {
//                    // Setup background task. This is needed because the captureOutput:didFinishRecordingToOutputFileAtURL: callback is not received until AVCam returns to the foreground unless you request background execution time. This also ensures that there will be time to write the file to the assets library when AVCam is backgrounded. To conclude this background execution, -endBackgroundTask is called in -recorder:recordingDidFinishToOutputFileURL:error: after the recorded file has been saved.
//                    [self setBackgroundRecordingID:[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil]];
//                }
//                
//                // Update the orientation on the movie file output video connection before starting recording.
//                [[[self movieFileOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] videoOrientation]];
//                
//                // Turning OFF flash for video recording
//                [iSKITACamViewController setFlashMode:AVCaptureFlashModeOff forDevice:[[self videoDeviceInput] device]];
//                
//                // Start recording to a temporary file.
//                NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"movie" stringByAppendingPathExtension:@"mov"]];
//                [[self movieFileOutput] startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
//            }
//            else
//            {
//                [[self movieFileOutput] stopRecording];
//            }
//        });
    }
    
    if ([self.modeLabel.text isEqualToString:@"相機模式"]) {
        [self snapStillImage:nil];
    }

}

//- (IBAction)toggleFlashControl:(UISwitch *)sender
//{
//    if (sender.on == YES) {
//        // Turning OFF flash for video recording
//        [iSKITACamViewController setFlashMode:AVCaptureFlashModeAuto forDevice:[[self videoDeviceInput] device]];
//    }else {
//          [iSKITACamViewController setFlashMode:AVCaptureFlashModeOff forDevice:[[self videoDeviceInput] device]];
//    }
//}

#define SC_APP_SIZE         [[UIScreen mainScreen] applicationFrame].size

- (IBAction)toggleSeperateLine:(UIButton *)sender
{
    [self timerStart];
    //    [self flashlight];
    if ([sender.titleLabel.text isEqualToString:@"隔線關閉"]){
        [sender setTitle:@"隔線開啟" forState:UIControlStateNormal];
        [sender setImage:[UIImage imageNamed:@"格子on.png"] forState:UIControlStateNormal];
//        CGFloat headHeight = self.seperateView.bounds.size.height - SC_APP_SIZE.width;
//        CGFloat squareLength = self.seperateView.bounds.size.width;
//        
//        CGFloat eachAreaLength = squareLength / 3;
        
        for (int i = 0; i < 4; i++) {
            CGRect frame = CGRectZero;
            if (i == 0 || i == 1) {//画横线
                if (iPhone5) {
                  frame = CGRectMake(0, (i + 1) * self.iphone5View.frame.size.height/3, self.iphone5View.frame.size.width, 1);
                }else {
                  frame = CGRectMake(0, (i + 1) * [[UIScreen mainScreen] applicationFrame].size.width/3,  [[UIScreen mainScreen] applicationFrame].size.height, 1);
                }
            } else {
                if (iPhone5) {
                    frame = CGRectMake((i + 1 - 2) * self.iphone5View.frame.size.width/3, 0, 1, self.iphone5View.frame.size.height);
                }else {
                  frame = CGRectMake((i + 1 - 2) * [[UIScreen mainScreen] applicationFrame].size.height/3, 0, 1, [[UIScreen mainScreen] applicationFrame].size.width);
                }
            }
            
            if (iPhone5) {
                 [self drawALineWithFrame:frame andColor:[UIColor whiteColor] inLayer:self.iphone5View.layer];
            }else {
                [self drawALineWithFrame:frame andColor:[UIColor whiteColor] inLayer:self.view.layer];  
            }
//            [self drawALineWithFrame:frame andColor:[UIColor whiteColor] inLayer:self.previewView.layer];
        }
    }else {
        [sender setTitle:@"隔線關閉" forState:UIControlStateNormal];
        [sender setImage:[UIImage imageNamed:@"格子off.png"] forState:UIControlStateNormal];
        
        NSArray *layersArr;
        if (iPhone5) {
           layersArr = [NSArray arrayWithArray:self.iphone5View.layer.sublayers];
        }else {
            layersArr = [NSArray arrayWithArray:self.view.layer.sublayers];
        }
        for (CALayer *layer in layersArr) {
            if (layer.frame.size.width == 1 || layer.frame.size.height == 1) {
                [layer removeFromSuperlayer];
            }
        }
    }
    
    
    //    if (!toShow) {
    //        NSArray *layersArr = [NSArray arrayWithArray:_preview.layer.sublayers];
    //        for (CALayer *layer in layersArr) {
    //            if (layer.frame.size.width == 1 || layer.frame.size.height == 1) {
    //                [layer removeFromSuperlayer];
    //            }
    //        }
    //        return;
    //    }
    //
    //    CGFloat headHeight = _previewLayer.bounds.size.height - SC_APP_SIZE.width;
    //    CGFloat squareLength = SC_APP_SIZE.width;
    //    CGFloat eachAreaLength = squareLength / 3;
    //
    //    for (int i = 0; i < 4; i++) {
    //        CGRect frame = CGRectZero;
    //        if (i == 0 || i == 1) {//画横线
    //            frame = CGRectMake(0, headHeight + (i + 1) * eachAreaLength, squareLength, 1);
    //        } else {
    //            frame = CGRectMake((i + 1 - 2) * eachAreaLength, headHeight, 1, squareLength);
    //        }
    //        [SCCommon drawALineWithFrame:frame andColor:[UIColor whiteColor] inLayer:_preview.layer];
    //    }
}

//- (IBAction)toggleSeperateLine:(UIButton *)sender
//{
////    [self flashlight];
//    if ([sender.titleLabel.text isEqualToString:@"隔線關閉"]){
//        [sender setTitle:@"隔線開啟" forState:UIControlStateNormal];
//        [sender setImage:[UIImage imageNamed:@"格子on.png"] forState:UIControlStateNormal];
//        CGFloat headHeight = self.seperateView.bounds.size.height - SC_APP_SIZE.width;
//        CGFloat squareLength = self.seperateView.bounds.size.width;
//
//        CGFloat eachAreaLength = squareLength / 3;
//        
//        for (int i = 0; i < 4; i++) {
//            CGRect frame = CGRectZero;
//            if (i == 0 || i == 1) {//画横线
//                frame = CGRectMake(0, headHeight + (i + 1) * eachAreaLength, squareLength, 1);
//            } else {
//                frame = CGRectMake((i + 1 - 2) * eachAreaLength, headHeight, 1, squareLength);
//            }
//            [self drawALineWithFrame:frame andColor:[UIColor whiteColor] inLayer:self.seperateView.layer];
//        }
//    }else {
//        [sender setTitle:@"隔線關閉" forState:UIControlStateNormal];
//        [sender setImage:[UIImage imageNamed:@"格子off.png"] forState:UIControlStateNormal];
//
//        NSArray *layersArr = [NSArray arrayWithArray:self.seperateView.layer.sublayers];
//        for (CALayer *layer in layersArr) {
//            if (layer.frame.size.width == 1 || layer.frame.size.height == 1) {
//                [layer removeFromSuperlayer];
//            }
//        }
//    }
//
//    
////    if (!toShow) {
////        NSArray *layersArr = [NSArray arrayWithArray:_preview.layer.sublayers];
////        for (CALayer *layer in layersArr) {
////            if (layer.frame.size.width == 1 || layer.frame.size.height == 1) {
////                [layer removeFromSuperlayer];
////            }
////        }
////        return;
////    }
////    
////    CGFloat headHeight = _previewLayer.bounds.size.height - SC_APP_SIZE.width;
////    CGFloat squareLength = SC_APP_SIZE.width;
////    CGFloat eachAreaLength = squareLength / 3;
////    
////    for (int i = 0; i < 4; i++) {
////        CGRect frame = CGRectZero;
////        if (i == 0 || i == 1) {//画横线
////            frame = CGRectMake(0, headHeight + (i + 1) * eachAreaLength, squareLength, 1);
////        } else {
////            frame = CGRectMake((i + 1 - 2) * eachAreaLength, headHeight, 1, squareLength);
////        }
////        [SCCommon drawALineWithFrame:frame andColor:[UIColor whiteColor] inLayer:_preview.layer];
////    }
//}

- (void)drawALineWithFrame:(CGRect)frame andColor:(UIColor*)color inLayer:(CALayer*)parentLayer {
    CALayer *layer = [CALayer layer];
    layer.frame = frame;

    layer.backgroundColor = color.CGColor;
    [parentLayer addSublayer:layer];
}

- (IBAction)toggleTimerControl:(UIButton *)sender
{
    [self timerStart];
    timerCount = timerCount + 1;
    if (timerCount <= 3) {
        switch (timerCount) {
            case 1:
                self.timerLabel.text = @"0";
                [sender setImage:[UIImage imageNamed:@"時間.png"] forState:UIControlStateNormal];
                intervel = 0;
                break;
            case 2:
                self.timerLabel.text = @"3";
                [sender setImage:[UIImage imageNamed:@"時間3sec.png"] forState:UIControlStateNormal];
                intervel = 3;
                break;
            case 3:
                self.timerLabel.text = @"10";
                [sender setImage:[UIImage imageNamed:@"時間10sec.png"] forState:UIControlStateNormal];
                intervel = 10;
                break;
            default:
                break;
        }

    }else{
        timerCount = 1;
        self.timerLabel.text = @"0";
        [sender setImage:[UIImage imageNamed:@"時間.png"] forState:UIControlStateNormal];
        intervel = 0;
    }
}

- (IBAction)toggleBrightness:(UIButton *)sender
{
    if ([sender.titleLabel.text isEqualToString:@"背光開啟"]){
       [sender setTitle:@"背光關閉" forState:UIControlStateNormal];
        [[UIScreen mainScreen] setBrightness:0];
    }else {
        [sender setTitle:@"背光開啟" forState:UIControlStateNormal];
        [[UIScreen mainScreen] setBrightness:0.8];
    }
}

- (IBAction)toggleFlashControl:(UIButton *)sender
{
    [self timerStart];
//    if ([sender.titleLabel.text isEqualToString:@"閃光燈開啟"]) {
//        [sender setTitle:@"閃光燈關閉" forState:UIControlStateNormal];
//        [sender setImage:[UIImage imageNamed:@"閃光燈off.png"] forState:UIControlStateNormal];
//        // Turning OFF flash for video recording
//        flashMode = AVCaptureFlashModeOff;
//    }else {
//        [sender setTitle:@"閃光燈開啟" forState:UIControlStateNormal];
//        [sender setImage:[UIImage imageNamed:@"閃光燈on.png"] forState:UIControlStateNormal];
//        flashMode = AVCaptureFlashModeOn;
//    }
    
    [self turnoffFlashlight];
    if (flashStatus < 3) {
        flashStatus = flashStatus + 1;
    }else {
        flashStatus = 0;
    }
    AVCaptureDevice *flashLight;
    
    switch (flashStatus) {
        case 0:
            // 關閉閃光燈
            [sender setImage:[UIImage imageNamed:@"閃光off.png"] forState:UIControlStateNormal];
            flashMode = AVCaptureFlashModeOff;
            break;
        case 1:
            // 自動閃光燈
            [sender setImage:[UIImage imageNamed:@"自動閃光.png"] forState:UIControlStateNormal];
            flashMode = AVCaptureFlashModeAuto;
            break;
        case 2:
            // 強制閃光燈
            [sender setImage:[UIImage imageNamed:@"閃光on.png"] forState:UIControlStateNormal];
            flashMode = AVCaptureFlashModeOn;
            break;
        case 3:
            // 手電筒
            [sender setImage:[UIImage imageNamed:@"長亮.png"] forState:UIControlStateNormal];
            flashLight = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            [flashLight lockForConfiguration:nil];
            [flashLight setTorchMode:AVCaptureTorchModeOn];
            [flashLight unlockForConfiguration];
//            [self flashlight];
            break;
        
            
        default:
            break;
    }
    
    if ([self.modeLabel.text isEqualToString:@"相機模式"]) {
        if (effectiveScale < 3.0) {
            effectiveScale = effectiveScale + 1.0;
        }else {
            effectiveScale = 1.0;
        }
        
        self.zoomLabel.text = [NSString stringWithFormat:@"%.f",effectiveScale];
        
        if ([self.zoomLabel.text isEqualToString:@"1"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦圓.png"];
        }
        
        if ([self.zoomLabel.text isEqualToString:@"2"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦x2圓.png"];
        }
        
        if ([self.zoomLabel.text isEqualToString:@"3"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦x4圓.png"];
        }
    }
}


//- (IBAction)toggleFlashControl:(UIButton *)sender
//{
//    [self timerStart];
//    if ([sender.titleLabel.text isEqualToString:@"閃光燈開啟"]) {
//        [sender setTitle:@"閃光燈關閉" forState:UIControlStateNormal];
//        [sender setImage:[UIImage imageNamed:@"閃光燈off.png"] forState:UIControlStateNormal];
//        // Turning OFF flash for video recording
//        flashMode = AVCaptureFlashModeOff;
//    }else {
//        [sender setTitle:@"閃光燈開啟" forState:UIControlStateNormal];
//        [sender setImage:[UIImage imageNamed:@"閃光燈on.png"] forState:UIControlStateNormal];
//        flashMode = AVCaptureFlashModeOn;
//    }
//}


- (IBAction)snapStillImage:(UIButton *)sender
{
    [self timerStart];
    timer1 = [NSTimer scheduledTimerWithTimeInterval:intervel target:self selector:@selector(takePhoto) userInfo:nil repeats:NO];
}

- (IBAction)changeMode:(UIButton *)sender
{
    [self timerStart];
    [self runStillImageCaptureAnimation];
    if ([self.modeLabel.text isEqualToString:@"相機模式"]) {
        self.modeLabel.text = @"錄影模式";
//        self.modelImageView.image = [UIImage imageNamed:@"切換錄影.png"];
        self.modelImageView.image = [UIImage imageNamed:@"切換拍照.png"];

        self.bigmodelImageView.image = [UIImage imageNamed:@"Small-white-video-down-dark.png"];
//        self.zoomImageView.image = [UIImage imageNamed:@"拍照模式.png"];
//        self.functionImageView.image = [UIImage imageNamed:@"play.png"];
        self.zoomImageView.image = [UIImage imageNamed:@"錄影按鈕.png"];
        self.functionImageView.image = [UIImage imageNamed:@"照相按鈕.png"];
        // 若隔現是開啟時，需要關閉
        if ([self.lineButton.titleLabel.text isEqualToString:@"隔線開啟"]) {
            [self toggleSeperateLine:self.lineButton];
            lineStatus = YES;
        } else {
            lineStatus = NO;
        }
        // 關閉自動對焦
        [self focusWithMode:AVCaptureFocusModeLocked exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:self.view.center monitorSubjectAreaChange:YES];
        // 全螢幕錄影
        if (iPhone5) {
            self.hiddenView.hidden = YES;
        }

    }else {
        self.modeLabel.text = @"相機模式";
        self.modelImageView.image = [UIImage imageNamed:@"切換錄影.png"];

//        self.modelImageView.image = [UIImage imageNamed:@"切換拍照.png"];
//        self.zoomImageView.image = [UIImage imageNamed:@"變焦.png"];
        self.bigmodelImageView.image = [UIImage imageNamed:@"拍照模式.png"];
        self.functionImageView.image = [UIImage imageNamed:@"照相按鈕.png"];
        
        // 比例拍照
        if (iPhone5) {
            self.hiddenView.hidden = NO;
        }
        
        // 回復初始隔線狀態
        if (lineStatus == YES) {
            [self.lineButton setTitle:@"隔線關閉" forState:UIControlStateNormal];
            [self toggleSeperateLine:self.lineButton];
    
        }
        
        // 回復原本zoom label image
        if ([self.zoomLabel.text isEqualToString:@"1"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦圓.png"];
        }
        
        if ([self.zoomLabel.text isEqualToString:@"2"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦x2圓.png"];
        }
        
        if ([self.zoomLabel.text isEqualToString:@"3"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦x4圓.png"];
        }
        
    }
}

- (IBAction)zoom:(UIButton *)sender
{
    [self timerStart];

    if ([self.modeLabel.text isEqualToString:@"相機模式"]) {
        if (effectiveScale < 3.0) {
            effectiveScale = effectiveScale + 1.0;
        }else {
            effectiveScale = 1.0;
        }
        
        self.zoomLabel.text = [NSString stringWithFormat:@"%.f",effectiveScale];
        
        if ([self.zoomLabel.text isEqualToString:@"1"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦圓.png"];
        }
        
        if ([self.zoomLabel.text isEqualToString:@"2"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦x2圓.png"];
        }
        
        if ([self.zoomLabel.text isEqualToString:@"3"]) {
            self.zoomImageView.image = [UIImage imageNamed:@"變焦x4圓.png"];
        }
        
        [CATransaction begin];
        [CATransaction setAnimationDuration:.025];
        [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setAffineTransform:CGAffineTransformMakeScale(effectiveScale, effectiveScale)];
        [CATransaction commit];
    }
    
    if ([self.modeLabel.text isEqualToString:@"錄影模式"]) {
//        [self snapStillImage:nil];
        [[self recordButton] setEnabled:NO];
        dispatch_async([self sessionQueue], ^{
            if (![[self movieFileOutput] isRecording])
            {
                [self setLockInterfaceRotation:YES];
                
                if ([[UIDevice currentDevice] isMultitaskingSupported])
                {
                    // Setup background task. This is needed because the captureOutput:didFinishRecordingToOutputFileAtURL: callback is not received until AVCam returns to the foreground unless you request background execution time. This also ensures that there will be time to write the file to the assets library when AVCam is backgrounded. To conclude this background execution, -endBackgroundTask is called in -recorder:recordingDidFinishToOutputFileURL:error: after the recorded file has been saved.
                    [self setBackgroundRecordingID:[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil]];
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                [[[self movieFileOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] videoOrientation]];
                
                // Turning OFF flash for video recording
                [iSKITACamViewController setFlashMode:AVCaptureFlashModeOff forDevice:[[self videoDeviceInput] device]];
                
                // Start recording to a temporary file.
                NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"movie" stringByAppendingPathExtension:@"mp4"]];
                [[self movieFileOutput] startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
            }
            else
            {
                [[self movieFileOutput] stopRecording];
            }
        });
    }
}

- (IBAction)changePosition:(UIButton *)sender
{
    [self timerStart];

	[[self recordButton] setEnabled:NO];
	[[self stillButton] setEnabled:NO];
	
	dispatch_async([self sessionQueue], ^{
		AVCaptureDevice *currentVideoDevice = [[self videoDeviceInput] device];
		AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
		AVCaptureDevicePosition currentPosition = [currentVideoDevice position];
		
		switch (currentPosition)
		{
			case AVCaptureDevicePositionUnspecified:
				preferredPosition = AVCaptureDevicePositionBack;
				break;
			case AVCaptureDevicePositionBack:
				preferredPosition = AVCaptureDevicePositionFront;
                [sender setTitle:@"前鏡頭" forState:UIControlStateNormal];
				break;
			case AVCaptureDevicePositionFront:
				preferredPosition = AVCaptureDevicePositionBack;
                [sender setTitle:@"後鏡頭" forState:UIControlStateNormal];
				break;
		}
		
		AVCaptureDevice *videoDevice = [iSKITACamViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
		
		[[self session] beginConfiguration];
		
		[[self session] removeInput:[self videoDeviceInput]];
		if ([[self session] canAddInput:videoDeviceInput])
		{
			[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
			
			[iSKITACamViewController setFlashMode:AVCaptureFlashModeAuto forDevice:videoDevice];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];
			
			[[self session] addInput:videoDeviceInput];
			[self setVideoDeviceInput:videoDeviceInput];
		}
		else
		{
			[[self session] addInput:[self videoDeviceInput]];
		}
		
		[[self session] commitConfiguration];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[[self recordButton] setEnabled:YES];
			[[self stillButton] setEnabled:YES];
		});
	});
    
}


- (IBAction)focusAndExposeTap:(UITapGestureRecognizer *)sender
{
    [self timerStart];
    CGPoint devicePoint = [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] captureDevicePointOfInterestForPoint:[sender locationInView:[sender view]]];
	[self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
    
    CGPoint point = [sender locationInView:[sender view]];
    
    if (point.x > 50 &&  point.x < 450 && point.y > 50 && point.y < 235) {
//        NSLog(@"Y-------->>%@",NSStringFromCGPoint([sender locationInView:[sender view]]));
        self.focusImageView.center = [sender locationInView:self.view];
        [self animateFocusImage];
    }else {
//           NSLog(@"N-------->>%@",NSStringFromCGPoint([sender locationInView:[sender view]]));
    }
}


- (void)subjectAreaDidChange:(NSNotification *)notification
{
	CGPoint devicePoint = CGPointMake(.5, .5);
	[self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

#pragma mark - Private method

- (void) takePhoto
{
    [timer1 invalidate];
    dispatch_async([self sessionQueue], ^{
		// Update the orientation on the still image output video connection before capturing.
		[[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] videoOrientation]];
		
		// Flash set to Auto for Still Capture
		[iSKITACamViewController setFlashMode:flashMode forDevice:[[self videoDeviceInput] device]];
        
        AVCaptureConnection *stillImageConnection = [[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo];
        
        CGFloat maxScale = stillImageConnection.videoMaxScaleAndCropFactor;
        if (effectiveScale > 1.0f && effectiveScale < maxScale)
        {
            stillImageConnection.videoScaleAndCropFactor = effectiveScale;;
        }
		
        [self playSound];
		// Capture a still image.
		[[self stillImageOutput] captureStillImageAsynchronouslyFromConnection:[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
			
			if (imageDataSampleBuffer)
			{
				NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                UIImage *image = [[UIImage alloc] initWithData:imageData];
                if(iPhone5 && [self.modeLabel.text isEqualToString:@"相機模式"]) {
                    UIImage *image1 = [image crop:CGRectMake(0, 0, image.size.width-400, image.size.height)];
                    [[[ALAssetsLibrary alloc] init] writeImageToSavedPhotosAlbum:[image1 CGImage] orientation:(ALAssetOrientation)[image1 imageOrientation] completionBlock:nil];
                } else {
                    [[[ALAssetsLibrary alloc] init] writeImageToSavedPhotosAlbum:[image CGImage] orientation:(ALAssetOrientation)[image imageOrientation] completionBlock:nil];
                
                }
                self.priveImageView.image = image;
			}
		}];
	});
}

- (void)animateFocusImage
{
    self.focusImageView.alpha = 0.0;
    self.focusImageView.hidden = false;
    
    [UIView animateWithDuration:0.2 animations:^{
        self.focusImageView.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.focusImageView.alpha = 0.0;
        } completion:^(BOOL secondFinished) {
            self.focusImageView.hidden = true;
        }];
    }];
}

-(void)longPressTap:(UILongPressGestureRecognizer*)sender
{
    if (sender.state == UIGestureRecognizerStateEnded) {
        NSLog(@"UIGestureRecognizerStateEnded");
    }
    else if (sender.state == UIGestureRecognizerStateBegan){
        NSLog(@"UIGestureRecognizerStateBegan.");
        //Do Whatever You want on End of Gesture
        CGPoint devicePoint = [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] captureDevicePointOfInterestForPoint:[sender locationInView:[sender view]]];
        [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
        
        self.focusImageView.center = self.view.center;
        
        [self animateFocusImage];
        [self performSelector:@selector(snapStillImage:) withObject:nil afterDelay:0.5];
//        [self snapStillImage:nil];
    }
}

- (void) openPhotoAlbum:(UITapGestureRecognizer*) sender
{
    [self timerStop];
    UIImagePickerController * picker = [[UIImagePickerController alloc] init];
	picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
    picker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeMovie, (NSString *) kUTTypeImage,nil];
    [self presentViewController:picker animated:YES completion:nil];
    
//    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
//    imagePicker.delegate = self;
//    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
//    imagePicker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeMovie,      nil];
//    
//    [self presentModalViewController:imagePicker animated:YES];
}





// 閃光燈控制
- (void) flashlight
{
    AVCaptureDevice *flashLight = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([flashLight isTorchAvailable] && [flashLight isTorchModeSupported:AVCaptureTorchModeOn])
    {
        BOOL success = [flashLight lockForConfiguration:nil];
        if (success)
        {
            [flashLight setTorchMode:AVCaptureTorchModeOn];
            [self performSelector:@selector(turnoffFlashlight) withObject:nil afterDelay:0.5];
            
//            if ([flashLight isTorchActive]) {
//                [flashLight setTorchMode:AVCaptureTorchModeOff];
//            } else {
//                [flashLight setTorchMode:AVCaptureTorchModeOn];
//            }
            [flashLight unlockForConfiguration];
        }
    }
}

// 閃光燈控制
-(void) turnoffFlashlight
{
    AVCaptureDevice *flashLight = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([flashLight isTorchAvailable] && [flashLight isTorchModeSupported:AVCaptureTorchModeOn])
    {
        BOOL success = [flashLight lockForConfiguration:nil];
        if (success)
        {
            if([flashLight isTorchActive]) {
                [flashLight setTorchMode:AVCaptureTorchModeOff];
            }
            [flashLight unlockForConfiguration];
        }
    }
}

// 快門聲響
-(void) playSound
{
    NSString *soundPath = [[NSBundle mainBundle] pathForResource:@"sound" ofType:@"mp3"];
    NSURL *url = [NSURL fileURLWithPath:soundPath];
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    [player setVolume:5.0];
    [player play];
}

- (void)batteryLevelChanged:(NSNotification *)notification
{
    [self updateBatteryLevel];
}

- (void)updateBatteryLevel
{
    float batteryLevel = [UIDevice currentDevice].batteryLevel;
    if (batteryLevel < 0.0) {
        // -1.0 means battery state is UIDeviceBatteryStateUnknown
        self.batteryLabel.text = NSLocalizedString(@"Unknown", @"");
    }
    else {
        static NSNumberFormatter *numberFormatter = nil;
        if (numberFormatter == nil) {
            numberFormatter = [[NSNumberFormatter alloc] init];
            [numberFormatter setNumberStyle:NSNumberFormatterPercentStyle];
            [numberFormatter setMaximumFractionDigits:1];
        }
        
        NSNumber *levelObj = [NSNumber numberWithFloat:batteryLevel];
        self.batteryLabel.text = [numberFormatter stringFromNumber:levelObj];
        
        if (self.batteryLabel.text.intValue > 70) {
            self.batteryLevelImageView.image = [UIImage imageNamed:@"battery_full.png"];
        }
        
        if (self.batteryLabel.text.intValue > 30 && self.batteryLabel.text.intValue < 70) {
            self.batteryLevelImageView.image = [UIImage imageNamed:@"battery_23"];
        }
        
        if (self.batteryLabel.text.intValue < 30 ) {
            self.batteryLevelImageView.image = [UIImage imageNamed:@"battery_13"];
        }
    }
}

// 開始計時
- (void) timerStart
{
    if(timer2 != nil) {
        [self timerStop];
        [self timerStart];
    }else {
        [[UIScreen mainScreen] setBrightness:1.0];
        timeCount = 0;
        timer2 = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateCount) userInfo:nil repeats: YES];
    }
}

- (void) timerStop
{
    [timer2 invalidate];
    timer2 = nil;
}

- (void) updateCount
{
    timeCount = timeCount + 1;
    // 超過特定時間就關閉背光
    if(timeCount > KBackLightTime) {
        [[UIScreen mainScreen] setBrightness:0.0];
        [self timerStop];
    }
}

- (void) updateRecordLabel
{
    recordCount = recordCount+1;
    NSTimeInterval elapsed =  recordCount;
    self.recordTimeLabel.text = [NSString stringWithFormat:@"%02u:%02u:%02.f",
                                 (int)(elapsed/3600),(int)(elapsed/60), fmod(elapsed, 60)];
    // 更新錄影圖片
    if(recordStatus == NO) {
        self.bigmodelImageView.image = [UIImage imageNamed:@"Small-white-video-down-light.png"];
        recordStatus = YES;
    }else {
        self.bigmodelImageView.image = [UIImage imageNamed:@"Small-white-video-down-dark.png"];
        recordStatus = NO;
    }
}

#pragma mark - UIImagePickerControllerDelegate

//- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
//    NSString *mediaType = [info objectForKey: UIImagePickerControllerMediaType];
//    
//    if (CFStringCompare ((__bridge CFStringRef) mediaType, kUTTypeMovie, 0) == kCFCompareEqualTo) {
//        NSString *moviePath = [[info objectForKey:UIImagePickerControllerMediaURL] path];
//        // NSLog(@"%@",moviePath);
//        NSURL *videoUrl=(NSURL*)[info objectForKey:UIImagePickerControllerMediaURL];
//        
//        if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum (moviePath)) {
//            UISaveVideoAtPathToSavedPhotosAlbum (moviePath, nil, nil, nil);
//        }
//    }
//    
//    [self dismissModalViewControllerAnimated:YES];
//}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
	//使用的檔案格式是圖片
	if ([mediaType isEqualToString:@"public.image"]){
        UIImage *image = [info objectForKey:@"UIImagePickerControllerOriginalImage"];
        PhotoViewController *photoVC = [self.storyboard instantiateViewControllerWithIdentifier:@"PhotoViewController"];
        photoVC.selectImage = image;
//        [self.navigationController pushViewController:photoVC animated:YES];
        [picker presentViewController:photoVC animated:YES completion:nil];
//        _imageView = [[UIImageView alloc]initWithImage:image];
//        [self.imageZoomView showWithDidShowHandler:^{
//            
//        } didDismissHandler:^{
//            
//        }];
        
    }
    
    //使用的檔案格式是影片
	if ([mediaType isEqualToString:@"public.movie"]){
        
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

//- (void)imageDidTouch:(UIGestureRecognizer *)recognizer
//{
////    __weak typeof(self) weakSelf = self;
//    [self.imageZoomView showWithDidShowHandler:^{
//      
//    } didDismissHandler:^{
//        
//    }];
//}
//
//- (XHMediaZoom *)imageZoomView
//{
//    if (_imageZoomView) return _imageZoomView;
//    
//    _imageZoomView = [[XHMediaZoom alloc] initWithAnimationTime:0.5 imageView:self.imageView blurEffect:NO];
//    _imageZoomView.tag = 1;
//    _imageZoomView.backgroundColor = [UIColor colorWithRed:0.141 green:0.310 blue:1.000 alpha:1.000];
//    _imageZoomView.maxAlpha = 0.75;
//    
//    
//    return _imageZoomView;
//}


#pragma mark - Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
	dispatch_async([self sessionQueue], ^{
		AVCaptureDevice *device = [[self videoDeviceInput] device];
		NSError *error = nil;
		if ([device lockForConfiguration:&error])
		{
			if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode])
			{
				[device setFocusMode:focusMode];
				[device setFocusPointOfInterest:point];
			}
			if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode])
			{
				[device setExposureMode:exposureMode];
				[device setExposurePointOfInterest:point];
			}
			[device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];
			[device unlockForConfiguration];
		}
		else
		{
			NSLog(@"%@", error);
		}
	});
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
	if ([device hasFlash] && [device isFlashModeSupported:flashMode])
	{
		NSError *error = nil;
		if ([device lockForConfiguration:&error])
		{
			[device setFlashMode:flashMode];
			[device unlockForConfiguration];
		}
		else
		{
			NSLog(@"%@", error);
		}
	}
}

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
	AVCaptureDevice *captureDevice = [devices firstObject];
	
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == position)
		{
			captureDevice = device;
			break;
		}
	}
	
	return captureDevice;
}

#pragma mark File Output Delegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
	if (error)
		NSLog(@"%@", error);
	
	[self setLockInterfaceRotation:NO];
	
	// Note the backgroundRecordingID for use in the ALAssetsLibrary completion handler to end the background task associated with this recording. This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's -isRecording is back to NO — which happens sometime after this method returns.
	UIBackgroundTaskIdentifier backgroundRecordingID = [self backgroundRecordingID];
	[self setBackgroundRecordingID:UIBackgroundTaskInvalid];
	
	[[[ALAssetsLibrary alloc] init] writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
		if (error)
			NSLog(@"%@", error);
		
		[[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
		
		if (backgroundRecordingID != UIBackgroundTaskInvalid)
			[[UIApplication sharedApplication] endBackgroundTask:backgroundRecordingID];
	}];
}

#pragma mark - UI

- (void)runStillImageCaptureAnimation
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[[self previewView] layer] setOpacity:0.0];
		[UIView animateWithDuration:1 animations:^{
			[[[self previewView] layer] setOpacity:1.0];
		}];
	});
}

- (void)checkDeviceAuthorizationStatus
{
	NSString *mediaType = AVMediaTypeVideo;
	
	[AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
		if (granted)
		{
			//Granted access to mediaType
			[self setDeviceAuthorized:YES];
		}
		else
		{
			//Not granted access to mediaType
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[UIAlertView alloc] initWithTitle:@"iSKITACam!"
											message:@"iSKITACam doesn't have permission to use Camera, please change privacy settings"
										   delegate:self
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
				[self setDeviceAuthorized:NO];
			});
		}
	}];
}


#pragma mark -
#pragma mark Listener Controls

- (void)startListener {
	[self.rioRef startListening:self];
    [array1 removeAllObjects];
    [array2 removeAllObjects];
}

- (void)stopListener {
	[self.rioRef stopListening];
    tmpCount1 = 0;
    self.currentPitchLabel.text = @"0";
//    [self removeObserver:self forKeyPath:@"currentFrequency"];
}


#pragma mark -
#pragma mark Key Management

// This method gets called by the rendering function. Update the UI with
// the character type and store it in our string.
- (void)frequencyChangedWithValue:(float)newFrequency{
	self.currentFrequency = newFrequency;
//	[self performSelectorInBackground:@selector(updateFrequencyLabel) withObject:nil];
    
    tmpCount1 = tmpCount1 + 1;
    
    if(newFrequency >= pitchLevel){
        NSDictionary *dic = @{@"time": @(tmpCount1),@"pitch":@(newFrequency)};
        [array1 addObject:dic];
    }else {
        if (array1.count > 0) {
            if (array2.count > kValue) {
                [self stopListener];
                if ([self getCommand:array1]) {
                    [self startListener];

                }else {
                    [array1 removeAllObjects];
                    [array2 removeAllObjects];
                    [self startListener];
                }
            }else {
                NSDictionary *dic = @{@"time": @(tmpCount1),@"pitch":@(newFrequency)};
                [array2 addObject:dic];
            }
        }
        
    }

	
	/*
	 * If you want to display letter values for pitches, uncomment this code and
	 * add your frequency to pitch mappings in KeyHelper.m
	 */
	
	/*
     KeyHelper *helper = [KeyHelper sharedInstance];
     NSString *closestChar = [helper closestCharForFrequency:newFrequency];
     
     // If the new sample has the same frequency as the last one, we should ignore
     // it. This is a pretty inefficient way of doing comparisons, but it works.
     if (![prevChar isEqualToString:closestChar]) {
     self.prevChar = closestChar;
     if ([closestChar isEqualToString:@"0"]) {
     //	[self toggleListening:nil];
     }
     [self performSelectorInBackground:@selector(updateFrequencyLabel) withObject:nil];
     NSString *appendedString = [key stringByAppendingString:closestChar];
     self.key = [NSMutableString stringWithString:appendedString];
     }
     */
}

//- (void)updateFrequencyLabel {
//	self.currentPitchLabel.text = [NSString stringWithFormat:@"%f", self.currentFrequency];
//	[self.currentPitchLabel setNeedsDisplay];
//}

-(BOOL) getCommand:(NSArray *) sampleAry
{
    BOOL success = NO;
    NSMutableArray *saveArray = [NSMutableArray new];
    
    for (NSDictionary *dic in sampleAry) {
        BOOL flag1 = YES;
        NSString *command = [self convertCommand:((NSNumber *)dic[@"pitch"]).floatValue];
        if (![command isEqualToString:@"X"]){
            if (saveArray.count == 0){
                [saveArray addObject:@{@"command": command,@"pitch":dic[@"pitch"]}];
            }else {
                for (NSDictionary *dic1 in saveArray) {
                    if ([command isEqualToString:dic1[@"command"]]) {
                        flag1 = NO;
                    }
                }
                if (flag1 == YES) {
                    [saveArray addObject:@{@"command": command,@"pitch":dic[@"pitch"]}];
                }
            }
        }
    }
    
    NSLog(@"--------->>%@",saveArray);
    
    if (saveArray.count == 5) {
        // learning mode
        success = YES;
//        [MMProgressHUD dismissWithSuccess:@"已經成功配對"];
        [[NSUserDefaults standardUserDefaults]setObject:saveArray forKey:@"command"];
        [[NSUserDefaults standardUserDefaults]synchronize];
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"完成" message:@"已經成功配對" delegate:self cancelButtonTitle:@"關閉" otherButtonTitles:nil];
        [alert show];
    }else if(saveArray.count == 3){
        // command mode
        success = YES;
        // 執行對應指令
        [self performCommad:saveArray];
    }else {
        success = NO;
    }
    
    return success;
}

-(void) performCommad:(NSArray *) commadArray
{
//    if ([[NSUserDefaults standardUserDefaults]objectForKey:@"command"]!=nil) {
//        NSArray *saveArray = [[NSUserDefaults standardUserDefaults]objectForKey:@"command"];
//        NSString *command1 = [NSString stringWithFormat:@"%@%@%@",saveArray[0][@"command"],saveArray[1][@"command"],saveArray[2][@"command"]];
//        NSString *command2 = [NSString stringWithFormat:@"%@%@%@",saveArray[0][@"command"],saveArray[1][@"command"],saveArray[3][@"command"]];
//        NSString *command3 = [NSString stringWithFormat:@"%@%@%@",saveArray[0][@"command"],saveArray[1][@"command"],saveArray[4][@"command"]];
        NSString *performCommand = [NSString stringWithFormat:@"%@%@%@",commadArray[0][@"command"],commadArray[1][@"command"],commadArray[2][@"command"]];
        
        if ([performCommand isEqualToString:@"01K1"]) {
            UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"" message:performCommand delegate:self cancelButtonTitle:@"關閉" otherButtonTitles:nil];
            [alert show];
        }
        
        if ([performCommand isEqualToString:@"01K2"]) {
            UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"" message:performCommand delegate:self cancelButtonTitle:@"關閉" otherButtonTitles:nil];
            [alert show];
        }
        
        if ([performCommand isEqualToString:@"01K3"]) {
            UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"" message:performCommand delegate:self cancelButtonTitle:@"關閉" otherButtonTitles:nil];
            [alert show];
        }
        
        
//    }
}


-(NSString *) convertCommand:(float) pitch
{
    float tmp = pitch/100;
    float tmp2 = floorf(tmp);
    float tmp3 = tmp2 * 100;
    
    NSString *str = [NSString new];
    str = @"X";
    
    if (tmp3 == 17700) {
        str = @"0";
    }
    
    if (tmp3 == 17400) {
        str = @"1";
    }
    
    if (tmp3 == 17100) {
        str = @"2";
    }
    
    if (tmp3 == 16800) {
        str = @"3";
    }
    
    if (tmp3 == 16500) {
        str = @"4";
    }
    
    if (tmp3 == 16200) {
        str = @"5";
    }
    
    if (tmp3 == 16000) {
        str = @"6";
    }
    
    if (tmp3 == 15700) {
        str = @"7";
    }
    
    if (tmp3 == 15500) {
        str = @"8";
    }
    
    if (tmp3 == 15200) {
        str = @"9";
    }
    
    if (tmp3 == 15000) {
        str = @"A";
    }
    
    if (tmp3 == 14800) {
        str = @"B";
    }
    
    if (tmp3 == 14600) {
        str = @"C";
    }
    
    if (tmp3 == 14300) {
        str = @"D";
    }
    
    if (tmp3 == 14100) {
        str = @"E";
    }
    
    if (tmp3 == 13900) {
        str = @"B";
    }
    
    if (tmp3 == 13700) {
        str = @"K1";
    }
    
    if (tmp3 == 13400) {
        str = @"K2";
    }
    
    if (tmp3 == 13100) {
        str = @"K3";
    }
    
    
    return str;
}


@end
