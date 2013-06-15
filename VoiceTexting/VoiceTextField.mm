//
//  VoiceTextField.m
//  VoiceTexting
//
//  Created by Johnil on 13-5-20.
//  Copyright (c) 2013年 Johnil. All rights reserved.
//

#import "VoiceTextField.h"
#define BLANK @"           "
@implementation VoiceTextField {
    UIImageView *p1;
    UIImageView *p2;
    UIImageView *p3;
    UIImageView *pA;

    VoiceInputView *voiceInputView;
    NSTimer *waitTimer;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = NO;
        UIImage *searchBg = [imageNamed(@"searchInput.png") resizableImageWithCapInsets:UIEdgeInsetsMake(5,5,5,5)];
        
        UIImageView *inputBG = [[UIImageView alloc] initWithImage:searchBg];
        [inputBG setFrame:CGRectMake(-2, -3, self.frame.size.width+4, self.frame.size.height+6)];
        [self addSubview:inputBG];
        
        
        [self addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        [self addTarget:self action:@selector(closeKeyBoard) forControlEvents:UIControlEventEditingDidEndOnExit];
    }
    return self;
}

- (BOOL)resignFirstResponder{
    [voiceInputView hide];
    return [super resignFirstResponder];
}

- (BOOL)becomeFirstResponder{
    self.tag = 0;
    return [super becomeFirstResponder];
}

- (void)voiceMode{
    if (self.tag<0) {
        return;
    }
    self.tag = -1;
    [super resignFirstResponder];
    voiceInputView = [[VoiceInputView alloc] init];
    voiceInputView.delegate = self;
    [self.window addSubview:voiceInputView];
    [voiceInputView show];
}

- (void)textMode{
    self.tag = 0;
    [self voiceInputDidFinished:@""];
    [self resignFirstResponder];
    [super becomeFirstResponder];
}

#pragma mark VoiceInputView delegate method

- (void)voiceInputBeginRequest{
    [self becomeFirstResponder];
    if (waitTimer) {
        return;
    }
    p1 = [[UIImageView alloc] initWithImage:imageNamed(@"uploading_icon_style1.png")];
    p2 = [[UIImageView alloc] initWithImage:imageNamed(@"uploading_icon_style1.png")];
    p3 = [[UIImageView alloc] initWithImage:imageNamed(@"uploading_icon_style1.png")];
    pA = [[UIImageView alloc] initWithImage:imageNamed(@"uploading_icon_style2.png")];
    p1.center = CGPointMake(p1.frame.size.width/2+5, self.frame.size.height/2);
    p2.center = CGPointMake(p1.center.x+(p1.frame.size.width+5), self.frame.size.height/2);
    p3.center = CGPointMake(p1.center.x+(p1.frame.size.width+5)*2, self.frame.size.height/2);
    pA.center = CGPointMake(p1.center.x, self.frame.size.height/2);
    [self addSubview:p1];
    [self addSubview:p2];
    [self addSubview:p3];
    [self addSubview:pA];
    self.text = @"           ";
    waitTimer = [NSTimer scheduledTimerWithTimeInterval:.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:waitTimer forMode:NSRunLoopCommonModes];
}

- (void)tick{
    int index = (pA.center.x-p1.center.x) / (p1.frame.size.width+5);
    index++;
    index = index>=3?0:index;
    pA.center = CGPointMake(p1.center.x+(p1.frame.size.width+5)*index, self.frame.size.height/2);
}

- (void)voiceInputDidFinished:(NSString *)str{
    [p1 removeFromSuperview];
    [p2 removeFromSuperview];
    [p3 removeFromSuperview];
    [pA removeFromSuperview];
    p1 = nil;
    p2 = nil;
    p3 = nil;
    pA = nil;
    [waitTimer invalidate];
    waitTimer = nil;
    if (str == nil) {
        self.text = [self.text stringByReplacingOccurrencesOfString:BLANK withString:@""];
    } else {
        if ([self.text rangeOfString:BLANK].length>0) {
            self.text = [NSString stringWithFormat:@"%@%@", str, [self.text stringByReplacingOccurrencesOfString:BLANK withString:@""]];
        }
    }
    [self sendActionsForControlEvents:UIControlEventEditingChanged];
}


#pragma mark Target

- (void)textFieldDidChange:(UITextField *)text{
    if (text.markedTextRange == nil) {
        if ([self.text stringByTrimmingCharactersInSet:[NSCharacterSet  whitespaceAndNewlineCharacterSet]].length==0
            && self.text.length < BLANK.length) {
            if (p1 && p1.superview) {
                self.text = BLANK;
                [self voiceInputDidFinished:@""];
            }
        }
    }
}

- (void)closeKeyBoard{
    [self resignFirstResponder];
}

- (void)dealloc{
    voiceInputView.delegate = nil;
    voiceInputView = nil;
    NSLog(@"voice textfield dealloc");
}

@end
