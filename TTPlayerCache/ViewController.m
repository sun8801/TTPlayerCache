//
//  ViewController.m
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/9.
//  Copyright © 2017年 szt. All rights reserved.
//

#import "ViewController.h"

#import "TTPlayerCacheMacro.h"
#import "TTResourceLoaderDelegate.h"
#import <AVFoundation/AVFoundation.h>

#import "TTPlayerView.h"

@interface ViewController ()

@property (strong, nonatomic) IBOutlet UIView *playerBGView;
@property (weak, nonatomic) IBOutlet UIButton *playBtn;
@property (weak, nonatomic) IBOutlet UIButton *pauseBtn;

@property (weak, nonatomic) IBOutlet UITextField *jumpTextField;


@property (nonatomic, strong) TTPlayerView *playerView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self setupPlayer];
}

- (void)setupPlayer {
    
    self.playerView = [TTPlayerView playerViewWith:[NSURL URLWithString:self.url]];
    [self.playerBGView addSubview:self.playerView];
    
    [self.playerView prepareToPlay];
}

#pragma mark -action method
- (IBAction)playBtnAction:(UIButton *)sender {
    [self.playerView play];
}
- (IBAction)pauseBtnAction:(UIButton *)sender {
    [self.playerView pause];
}
- (IBAction)seekNext10BtnAction:(UIButton *)sender {
    [self.playerView seekNextTime];
}

- (IBAction)jumpBtnAction:(UIButton *)sender {
    if (self.jumpTextField.text.length <= 0) {
        [self.playerView seekToTime:0];
        return;
    }
    [self.playerView seekToTime:[self.jumpTextField.text floatValue]];
}

@end
