//
//  VoiceInputView.m
//  VoiceTexting
//
//  Created by Johnil on 13-5-20.
//  Copyright (c) 2013年 Johnil. All rights reserved.
//

#import "VoiceInputView.h"
#import "AQRecorder.h"
#import <AudioToolbox/AudioQueue.h>
#include "MeterTable.h"
#import "CAXException.h"
#import "AFHTTPRequestOperation.h"
#import "JSONKit.h"
#import "AFHTTPClient.h"
#define kPeakFalloffPerSec	.7
#define kLevelFalloffPerSec .8
#define kMinDBvalue -80.0

@implementation VoiceInputView {
    AudioQueueRef				_aq;
	AudioQueueLevelMeterState	*_chan_lvls;
	NSArray						*_channelNumbers;
	NSArray						*_subLevelMeters;
	MeterTable					*_meterTable;
	NSTimer						*_updateTimer;
	CGFloat						_refreshHz;
	CFAbsoluteTime				_peakFalloffLastFire;

    
    UIImageView *highVoice;
}
@synthesize recorder;

char *OSTypeToStr(char *buf, OSType t)
{
	char *p = buf;
	char str[4], *q = str;
	*(UInt32 *)str = CFSwapInt32(t);
	for (int i = 0; i < 4; ++i) {
		if (isprint(*q) && *q != '\\')
			*p++ = *q++;
		else {
			sprintf(p, "\\x%02x", *q++);
			p += 4;
		}
	}
	*p = '\0';
	return buf;
}

- (id)init
{
    self = [super initWithFrame:CGRectMake(0, HEIGHT, 320, 219)];
    if (self) {
        UIImageView *bg = [[UIImageView alloc] initWithImage:imageNamed(@"voiceBG.png")];
        [self addSubview:bg];
        
        highVoice = [[UIImageView alloc] initWithImage:imageNamed(@"voiceHigh.png")];
        highVoice.alpha = 0;
        [self addSubview:highVoice];
        
        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        doneBtn.frame = CGRectMake(0, 219-64-20, 320, 64);
        [doneBtn setImage:imageNamed(@"voiceBtn.png") forState:UIControlStateNormal];
        [doneBtn setImage:imageNamed(@"voiceBtnA.png") forState:UIControlStateHighlighted];
        [doneBtn addTarget:self action:@selector(stopRecord) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:doneBtn];
        
        recorder = new AQRecorder();
		_channelNumbers = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
		_chan_lvls = (AudioQueueLevelMeterState*)malloc(sizeof(AudioQueueLevelMeterState) * [_channelNumbers count]);
		_meterTable = new MeterTable(kMinDBvalue);
        
        OSStatus error = AudioSessionInitialize(NULL, NULL, interruptionListener,  (__bridge void*)self);
        if (error) printf("ERROR INITIALIZING AUDIO SESSION! %ld\n", error);
        else
        {
            UInt32 category = kAudioSessionCategory_PlayAndRecord;
            error = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
            if (error) printf("couldn't set audio category!");
            
            error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, propListener,  (__bridge void*)self);
            if (error) printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %ld\n", error);
            UInt32 inputAvailable = 0;
            UInt32 size = sizeof(inputAvailable);
            
            // we do not want to allow recording if input is not available
            error = AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &size, &inputAvailable);
            if (error) printf("ERROR GETTING INPUT AVAILABILITY! %ld\n", error);
            
            // we also need to listen to see if input availability changes
            error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioInputAvailable, propListener,  (__bridge void*)self);
            if (error) printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %ld\n", error);
            
            error = AudioSessionSetActive(true); 
            if (error) printf("AudioSessionSetActive (true) failed");
        }
    }
    return self;
}

- (void)show{
    [UIView animateWithDuration:.3 animations:^{
        self.frame = CGRectMake(0, HEIGHT-219, 320, 219);
    } completion:^(BOOL finished) {
        [self record];
    }];
}

- (void)hide{
    [UIView animateWithDuration:.3 animations:^{
        self.frame = CGRectMake(0, HEIGHT, 320, 219);
    } completion:^(BOOL finished) {
        if (recorder) {
            delete recorder;
            recorder = nil;
        }
        if (_updateTimer) {
            [_updateTimer invalidate];
            _updateTimer = nil;
        }
        [self removeFromSuperview];
    }];
}

#pragma mark - voice

- (void)stopRecord{
	recorder->StopRecord();
    [self hide];
    if (_delegate && [_delegate respondsToSelector:@selector(voiceInputBeginRequest)]) {
        [_delegate voiceInputBeginRequest];
    }
    
    NSURL *url = [NSURL URLWithString:@"http://www.google.com"];
    AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:url];
    NSMutableURLRequest *request = [httpClient multipartFormRequestWithMethod:@"POST"
                                                                         path:@"/speech-api/v1/recognize?xjerr=1&client=chromium&lang=zh-CN"
                                                                   parameters:nil
                                                    constructingBodyWithBlock: ^(id <AFMultipartFormData>formData) {
                                                           NSString *filePath_voice = [NSTemporaryDirectory() stringByAppendingFormat:@"voice.flac"];
                                                           [formData appendPartWithFileData:[NSData dataWithContentsOfFile:filePath_voice] name:@"file" fileName:@"voice.flac" mimeType:@"audio/x-flac"];
                                                    }];
    [request setValue:@"audio/x-flac; rate=16000" forHTTPHeaderField:@"Content-Type"];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [httpClient enqueueHTTPRequestOperation:operation];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (_delegate && [_delegate respondsToSelector:@selector(voiceInputDidFinished:)]) {
            [_delegate voiceInputDidFinished:[[[[operation.responseString objectFromJSONString] valueForKey:@"hypotheses"] valueForKey:@"utterance"] lastObject]];
            _delegate = nil;
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"%@", error);
    }];
}

- (void)record{
    recorder->StartRecord(CFSTR("recordedFile.caf"));
    [self setAq:recorder->Queue()];
}

#pragma mark - meter

- (void)setAq:(AudioQueueRef)v
{
	if ((_aq == NULL) && (v != NULL))
	{
		if (_updateTimer) [_updateTimer invalidate];
		
		_updateTimer = [NSTimer
						scheduledTimerWithTimeInterval:1.0/30.0
						target:self
						selector:@selector(_refresh)
						userInfo:nil
						repeats:YES
						];
	} else if ((_aq != NULL) && (v == NULL)) {
		_peakFalloffLastFire = CFAbsoluteTimeGetCurrent();
	}
	
	_aq = v;
	
	if (_aq){
		try {
			UInt32 val = 1;
			XThrowIfError(AudioQueueSetProperty(_aq, kAudioQueueProperty_EnableLevelMetering, &val, sizeof(UInt32)), "couldn't enable metering");
			
			// now check the number of channels in the new queue, we will need to reallocate if this has changed
			CAStreamBasicDescription queueFormat;
			UInt32 data_sz = sizeof(queueFormat);
			XThrowIfError(AudioQueueGetProperty(_aq, kAudioQueueProperty_StreamDescription, &queueFormat, &data_sz), "couldn't get stream description");
            
			if (queueFormat.NumberChannels() != [_channelNumbers count])
			{
				NSArray *chan_array;
				if (queueFormat.NumberChannels() < 2)
					chan_array = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
				else
					chan_array = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:1], nil];
                
                _channelNumbers = chan_array;
				
				_chan_lvls = (AudioQueueLevelMeterState*)realloc(_chan_lvls, queueFormat.NumberChannels() * sizeof(AudioQueueLevelMeterState));
			}
		}
		catch (CAXException e) {
			char buf[256];
			fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		}
	}
}

- (void)_refresh
{
	// if we have no queue, but still have levels, gradually bring them down
    UInt32 data_sz = sizeof(AudioQueueLevelMeterState) * [_channelNumbers count];
    OSErr status = AudioQueueGetProperty(_aq, kAudioQueueProperty_CurrentLevelMeterDB, _chan_lvls, &data_sz);
    if (status != noErr) goto bail;
    
    if (_channelNumbers.count>0) {
        NSInteger channelIdx = [(NSNumber *)[_channelNumbers objectAtIndex:0] intValue];
        if (channelIdx >= [_channelNumbers count]) goto bail;
        if (channelIdx > 127) goto bail;
        
        if (_chan_lvls)
        {
            highVoice.alpha = _meterTable->ValueAt((float)(_chan_lvls[channelIdx].mAveragePower));
        }
    }
    
bail:
    {}
//	NSLog(@"bail");
}

#pragma mark AudioSession listeners
void interruptionListener(	void *	inClientData,
                          UInt32	inInterruptionState)
{
	VoiceInputView *THIS = (__bridge VoiceInputView *)inClientData;
	if (inInterruptionState == kAudioSessionBeginInterruption)
	{
		if (THIS->recorder->IsRunning()) {
			[THIS stopRecord];
		}
	}
}

void propListener(	void *                  inClientData,
                  AudioSessionPropertyID	inID,
                  UInt32                  inDataSize,
                  const void *            inData)
{
	VoiceInputView *THIS = (__bridge VoiceInputView *)inClientData;
	if (inID == kAudioSessionProperty_AudioRouteChange)
	{
		CFDictionaryRef routeDictionary = (CFDictionaryRef)inData;
		//CFShow(routeDictionary);
		CFNumberRef reason = (CFNumberRef)CFDictionaryGetValue(routeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
		SInt32 reasonVal;
		CFNumberGetValue(reason, kCFNumberSInt32Type, &reasonVal);
		if (reasonVal != kAudioSessionRouteChangeReason_CategoryChange)
		{
			// stop the queue if we had a non-policy route change
			if (THIS->recorder->IsRunning()) {
				[THIS stopRecord];
			}
		}
	}
}

@end
