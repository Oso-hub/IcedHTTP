#import "IHTTPRequest.h"

@interface IHTTPRequest ()
@property(nonatomic, readonly) CFHTTPMessageRef messageRef;
@property(nonatomic, retain) id messageRefStorage;
@property(nonatomic, retain) NSDate* requestTimeStorage;

@end

#pragma mark -

@implementation IHTTPRequest

+ (IHTTPRequest*) requestWithMessageRef:(CFHTTPMessageRef) messageRef
{
    return [[IHTTPRequest alloc] initWithMessageRef:messageRef];
}

#pragma mark - Initilizers

- (id)init
{
    if ((self = super.init)) {
        self.requestTimeStorage = NSDate.date;
    }
    return self;
}

- (id) initWithMessageRef:(CFHTTPMessageRef) mRef
{
    if ((self = self.init)) {
        self.messageRefStorage = CFBridgingRelease(mRef);
    }
    return self;
}

#pragma mark - Properties

- (CFHTTPMessageRef) messageRef
{
    return (__bridge CFHTTPMessageRef)self.messageRefStorage;
}

- (NSString*) requestMethod
{
    return (self.messageRef ? CFBridgingRelease(CFHTTPMessageCopyRequestMethod(self.messageRef)) : nil);
}

- (NSDictionary*) requestHeaders
{
    return (self.messageRef ? CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(self.messageRef)) : nil);
}

- (NSURL*) requestURL
{
    return (self.messageRef ? CFBridgingRelease(CFHTTPMessageCopyRequestURL(self.messageRef)) : nil);
}

- (NSDate*) requestTime
{
    return self.requestTimeStorage;
}

#pragma mark -

+ (IHTTPRequest*) requestWithInput:(NSFileHandle*) input
{
    IHTTPRequest* request = IHTTPRequest.new;
    request.input = input;
    return request;
}

#pragma mark -

- (void) readHeaders
{
    if (!self.didReadHeaders) {
        self.messageRefStorage = CFBridgingRelease(CFHTTPMessageCreateEmpty(kCFAllocatorDefault, YES));
		[NSNotificationCenter.defaultCenter
			addObserver:self
			selector:@selector(receiveIncomingDataNotification:)
			name:NSFileHandleDataAvailableNotification
			object:self.input];
		
        [self.input waitForDataInBackgroundAndNotify];
        self.didReadHeaders = YES;
    }
}

- (NSData*) readBody
{
    if (self.didReadHeaders) {
        return [self.input readDataToEndOfFile];
    }
    else {
        [self readHeaders];
        return nil;
    }
}

- (void) completeRequest
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleDataAvailableNotification object:self.input];
    [self.input closeFile];
}

#pragma mark -

- (void)receiveIncomingDataNotification:(NSNotification *)notification
{
	NSFileHandle *incomingFileHandle = [notification object];
	NSData *data = [incomingFileHandle availableData];
	
	if ([data length] == 0) { // EoF
		[self completeRequest];
		return;
	}

    CFHTTPMessageAppendBytes(self.messageRef, [data bytes], [data length]);
    
	if (CFHTTPMessageIsHeaderComplete(self.messageRef)) {
        if ([self.delegate respondsToSelector:@selector(request:parsedHeaders:)]) {
            [self.delegate request:self parsedHeaders:self.requestHeaders];
            self.didReadHeaders = YES;
        }

        [NSNotificationCenter.defaultCenter removeObserver:self name:NSFileHandleDataAvailableNotification object:self.input];
    }
    else {
        [incomingFileHandle waitForDataInBackgroundAndNotify];
    }
}

#pragma mark - NSObject

- (NSString*)description
{
    return [NSString stringWithFormat:@"<%@:%p on: %@ headers: %@>",
        NSStringFromClass([self class]), self, self.requestTime, self.requestHeaders];
}

@end

//  Copyright © 2016-2019 Alf Watt. Available under MIT License (MIT) in README.md
