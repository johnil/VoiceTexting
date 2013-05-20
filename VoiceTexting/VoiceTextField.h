//
//  VoiceTextField.h
//  VoiceTexting
//
//  Created by Johnil on 13-5-20.
//  Copyright (c) 2013年 Johnil. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "VoiceInputView.h"

@interface VoiceTextField : UITextField <VoiceInputDelegate>

- (void)voiceMode;
- (void)textMode;

@end
