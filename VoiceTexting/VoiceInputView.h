//
//  VoiceInputView.h
//  VoiceTexting
//
//  Created by Johnil on 13-5-20.
//  Copyright (c) 2013年 Johnil. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AQRecorder.h"

@interface VoiceInputView : UIView {
    AQRecorder *recorder;
}
@property (readonly) AQRecorder *recorder;
@property (nonatomic, strong) id delegate;
- (void)show;
- (void)hide;
@end

@protocol VoiceInputDelegate <NSObject>

- (void)voiceInputDidFinished:(NSString *)str;
- (void)voiceInputBeginRequest;

@end
