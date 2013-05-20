/*
 
    File: AQRecorder.mm
Abstract: n/a
 Version: 2.4

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
Inc. ("Apple") in consideration of your agreement to the following
terms, and your use, installation, modification or redistribution of
this Apple software constitutes acceptance of these terms.  If you do
not agree with these terms, please do not use, install, modify or
redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may
be used to endorse or promote products derived from the Apple Software
without specific prior written permission from Apple.  Except as
expressly stated in this notice, no other rights or licenses, express or
implied, are granted by Apple herein, including but not limited to any
patent rights that may be infringed by your derivative works or by other
works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2009 Apple Inc. All Rights Reserved.

 
*/

#include "AQRecorder.h"
#include "flac_encoder.c"
#define kBufferDurationSeconds .5
// 采样频率
#define SAMPLE_RATE 16000
static Boolean  g_bIsHead;  //  判断是否为录音的头
static NSInteger g_nLength = 0; //  音频长度

// ____________________________________________________________________________________
// Determine the size, in bytes, of a buffer necessary to represent the supplied number
// of seconds of audio data.
int AQRecorder::ComputeRecordBufferSize(const AudioStreamBasicDescription *format, float seconds)
{
	int packets, frames, bytes = 0;
	try {
		frames = (int)ceil(seconds * format->mSampleRate);
		
		if (format->mBytesPerFrame > 0)
			bytes = frames * format->mBytesPerFrame;
		else {
			UInt32 maxPacketSize;
			if (format->mBytesPerPacket > 0)
				maxPacketSize = format->mBytesPerPacket;	// constant packet size
			else {
				UInt32 propertySize = sizeof(maxPacketSize);
				XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize,
												 &propertySize), "couldn't get queue's maximum output packet size");
			}
			if (format->mFramesPerPacket > 0)
				packets = frames / format->mFramesPerPacket;
			else
				packets = frames;	// worst-case scenario: 1 frame in a packet
			if (packets == 0)		// sanity check
				packets = 1;
			bytes = packets * maxPacketSize;
		}
	} catch (CAXException e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		return 0;
	}	
	return bytes;
}

// ____________________________________________________________________________________
// AudioQueue callback function, called when an input buffers has been filled.
void AQRecorder::MyInputBufferHandler(	void *								inUserData,
										AudioQueueRef						inAQ,
										AudioQueueBufferRef					inBuffer,
										const AudioTimeStamp *				inStartTime,
										UInt32								inNumPackets,
										const AudioStreamPacketDescription*	inPacketDesc)
{
	AQRecorder *aqr = (AQRecorder *)inUserData;
	try {
		if (inNumPackets > 0) {
			// write packets to file
            
            UInt32 length = inBuffer->mAudioDataByteSize;
			XThrowIfError(AudioFileWritePackets(aqr->mRecordFile, FALSE, length,
											 inPacketDesc, aqr->mRecordPacket, &inNumPackets, inBuffer->mAudioData),
					   "AudioFileWritePackets failed");
			aqr->mRecordPacket += inNumPackets;
            g_nLength += length;
		}
		
		// if we're not stopping, re-enqueue the buffe so that it gets filled again
		if (aqr->IsRunning())
			XThrowIfError(AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL), "AudioQueueEnqueueBuffer failed");
	} catch (CAXException e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
}

AQRecorder::AQRecorder()
{
	mIsRunning = false;
	mRecordPacket = 0;
    g_bIsHead = YES;
}

AQRecorder::~AQRecorder()
{
	AudioQueueDispose(mQueue, TRUE);
	AudioFileClose(mRecordFile);
	if (mFileName) CFRelease(mFileName);
}

// ____________________________________________________________________________________
// Copy a queue's encoder's magic cookie to an audio file.
void AQRecorder::CopyEncoderCookieToFile()
{
	UInt32 propertySize;
	// get the magic cookie, if any, from the converter		
	OSStatus err = AudioQueueGetPropertySize(mQueue, kAudioQueueProperty_MagicCookie, &propertySize);
	
	// we can get a noErr result and also a propertySize == 0
	// -- if the file format does support magic cookies, but this file doesn't have one.
	if (err == noErr && propertySize > 0) {
		Byte *magicCookie = new Byte[propertySize];
		UInt32 magicCookieSize;
		XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize), "get audio converter's magic cookie");
		magicCookieSize = propertySize;	// the converter lies and tell us the wrong size
		
		// now set the magic cookie on the output file
		UInt32 willEatTheCookie = false;
		// the converter wants to give us one; will the file take it?
		err = AudioFileGetPropertyInfo(mRecordFile, kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
		if (err == noErr && willEatTheCookie) {
			err = AudioFileSetProperty(mRecordFile, kAudioFilePropertyMagicCookieData, magicCookieSize, magicCookie);
			XThrowIfError(err, "set audio file's magic cookie");
		}
		delete[] magicCookie;
	}
}

void AQRecorder::SetupAudioFormat(UInt32 inFormatID)
{
	memset(&mRecordFormat, 0, sizeof(mRecordFormat));

	UInt32 size = sizeof(mRecordFormat.mSampleRate);
	XThrowIfError(AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareSampleRate,
										&size, 
										&mRecordFormat.mSampleRate), "couldn't get hardware sample rate");

	size = sizeof(mRecordFormat.mChannelsPerFrame);
	XThrowIfError(AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareInputNumberChannels, 
										&size, 
										&mRecordFormat.mChannelsPerFrame), "couldn't get input channel count");
			
	mRecordFormat.mFormatID = inFormatID;
	if (inFormatID == kAudioFormatLinearPCM)
	{
		// if we want pcm, default to signed 16-bit little-endian
        mRecordFormat.mSampleRate = SAMPLE_RATE;
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFramesPerPacket = 1;
		mRecordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
		mRecordFormat.mBitsPerChannel = 16;
		mRecordFormat.mBytesPerPacket = mRecordFormat.mBytesPerFrame = (mRecordFormat.mBitsPerChannel / 8) * mRecordFormat.mChannelsPerFrame;
		
	}
}

void AQRecorder::StartRecord(CFStringRef inRecordFile)
{
	int i, bufferByteSize;
	UInt32 size;
	CFURLRef url;
	
	try {		
		mFileName = CFStringCreateCopy(kCFAllocatorDefault, inRecordFile);

		// specify the recording format
		SetupAudioFormat(kAudioFormatLinearPCM);
		
		// create the queue
		XThrowIfError(AudioQueueNewInput(
									  &mRecordFormat,
									  MyInputBufferHandler,
									  this /* userData */,
									  NULL /* run loop */, NULL /* run loop mode */,
									  0 /* flags */, &mQueue), "AudioQueueNewInput failed");
		
		// get the record format back from the queue's audio converter --
		// the file may require a more specific stream description than was necessary to create the encoder.
		mRecordPacket = 0;

		size = sizeof(mRecordFormat);
		XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,	
										 &mRecordFormat, &size), "couldn't get queue's format");
			
		NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)inRecordFile];	
			
		url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)recordFile, NULL);
		
		// create the audio file
		XThrowIfError(AudioFileCreateWithURL(url, kAudioFileWAVEType, &mRecordFormat, kAudioFileFlags_EraseFile,
										  &mRecordFile), "AudioFileCreateWithURL failed");
		CFRelease(url);
		
		// copy the cookie first to give the file object as much info as we can about the data going in
		// not necessary for pcm, but required for some compressed audio
		CopyEncoderCookieToFile();
		
		// allocate and enqueue buffers
		bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);	// enough bytes for half a second
		for (i = 0; i < kNumberRecordBuffers; ++i) {
			XThrowIfError(AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]),
					   "AudioQueueAllocateBuffer failed");
			XThrowIfError(AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL),
					   "AudioQueueEnqueueBuffer failed");
		}
		// start the queue
		mIsRunning = true;
		XThrowIfError(AudioQueueStart(mQueue, NULL), "AudioQueueStart failed");
	}
	catch (CAXException &e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
	catch (...) {
		fprintf(stderr, "An unknown error occurred\n");
	}	

}

typedef struct { 
    unsigned short  format_tag; 
    unsigned short  channels;           /* 1 = mono, 2 = stereo */ 
    unsigned long   samplerate;         /* typically: 44100, 32000, 22050, 11025 or 8000*/ 
    unsigned long   bytes_per_second;   /* SamplesPerSec * BlockAlign*/ 
    unsigned short  blockalign;         /* Channels * (BitsPerSample / 8)*/ 
    unsigned short  bits_per_sample;    /* 16 or 8 */ 
} WAVEAUDIOFORMAT; 

typedef struct { 
    char info[4]; 
    unsigned long length; 
} RIFF_CHUNK;
int CreateWavHeader(FILE *file, int channels, int samplerate, int resolution)   
{   
    int length;
    
    /* Use a zero length for the chunk sizes for now, then modify when finished */   
    WAVEAUDIOFORMAT format;   
    
    format.format_tag = 1;   
    format.channels = channels;   
    format.samplerate = samplerate;   
    format.bits_per_sample = resolution;   
    format.blockalign = channels * (resolution/8);   
    format.bytes_per_second = format.samplerate * format.blockalign;   
    
    fseek(file, 0, SEEK_SET);
    
    fwrite("RIFF\0\0\0\0WAVEfmt ", sizeof(char), 16, file); /* Write RIFF, WAVE, and fmt  headers */   
    
    length = 16;   
    fwrite(&length, 1, sizeof(long), file); /* Length of Format (always 16) */   
    fwrite(&format, 1, sizeof(format), file);   
    
    fwrite("data\0\0\0\0", sizeof(char), 8, file); /* Write data chunk */   
    
    return 0;   
}

int UpdateWavHeader(FILE *file)   
{   
    /*fpos_t*/int filelen, riff_length, data_length;   
    
    /* Get the length of the file */   
    
    if(!file)   
        return -1;   
    
    fseek( file, 0, SEEK_END );   
    filelen = ftell( file );   
    
    if(filelen == 0)   
        return -1;   
    
    riff_length = filelen - 8;   
    data_length = filelen - 44;   
    
    fseek(file, 4, SEEK_SET);   
    fwrite(&riff_length, 1, sizeof(long), file);   
    
    fseek(file, 40, SEEK_SET);   
    fwrite(&data_length, 1, sizeof(long), file);   
    
    /* reset file position for appending data */   
    fseek(file, 0, SEEK_END);   
    
    return 0;   
} 

void AQRecorder::StopRecord()
{
	// end recording
	mIsRunning = false;
	XThrowIfError(AudioQueueStop(mQueue, true), "AudioQueueStop failed");	
	// a codec may update its cookie at the end of an encoding session, so reapply it to the file now
	CopyEncoderCookieToFile();
	if (mFileName)
	{
		CFRelease(mFileName);
		mFileName = NULL;
	}
    AudioQueueDispose(mQueue, true);
	AudioFileClose(mRecordFile);

    // 此处将PCM音频添加head，编码成wav格式
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingFormat:@"recordedFile.caf"];
    NSString *filePath2 = [NSTemporaryDirectory() stringByAppendingFormat:@"recordedFile2.caf"];
    const char *pFilePath = [filePath UTF8String];
    const char *pFilePath2 = [filePath2 UTF8String];
    FILE *sndfile;
    FILE *infile;
    long fileread;
 
    infile=fopen(pFilePath,"r");
    sndfile=fopen(pFilePath2,"wb");
    
    fseek(infile, 0, SEEK_END);
    fileread = ftell(infile);
    printf("%ld",fileread);
    fseek(infile,0, SEEK_SET);
    CreateWavHeader(sndfile, 2, SAMPLE_RATE, 16); // 谷歌识别的sample rate必须为16000的因此此处设置

    while( !feof(infile))
    {
        char readBuf[4096];
        int nRead = fread(readBuf, 1, 4096, infile);    //将pcm文件读到readBuf
        if (nRead > 0)
        {
            fwrite(readBuf, 1, nRead, sndfile);      //将readBuf文件的数据写到wav文件
        }
    }
    UpdateWavHeader(sndfile);
    fclose(sndfile);
    fclose(infile);
    
    NSString *filePath_dest = [NSTemporaryDirectory() stringByAppendingFormat:@"voice.flac"];
    startEncode(pFilePath2, [filePath_dest UTF8String], g_nLength);
}
