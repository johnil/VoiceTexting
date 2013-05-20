//
//  ViewController.m
//  VoiceTexting
//
//  Created by Johnil on 13-5-20.
//  Copyright (c) 2013年 Johnil. All rights reserved.
//

#import "ViewController.h"
#import "VoiceTextField.h"
@interface ViewController ()

@end

@implementation ViewController {
    VoiceTextField *textField;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    textField = [[VoiceTextField alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
    textField.center = CGPointMake(self.view.frame.size.width/2, 50);
    textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    [textField setClearButtonMode:UITextFieldViewModeWhileEditing];
    [textField setReturnKeyType:UIReturnKeyDone];
    textField.placeholder = @"Please enter text";
    textField.textColor = [UIColor blackColor];
    [self.view addSubview:textField];
    [textField becomeFirstResponder];
    
    UIButton *btnTalk = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *imgIcon = imageNamed(@"icon_mircophone2.png");
    [btnTalk setImage:imgIcon forState:UIControlStateNormal];
    [btnTalk setFrame:CGRectMake(0, 0, imgIcon.size.width, imgIcon.size.height)];
    btnTalk.center = CGPointMake(textField.frame.size.width+textField.frame.origin.x+btnTalk.frame.size.width/2, textField.frame.origin.y+textField.frame.size.height/2);
    [btnTalk addTarget:textField action:@selector(voiceMode) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btnTalk];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event{
    [textField textMode];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
