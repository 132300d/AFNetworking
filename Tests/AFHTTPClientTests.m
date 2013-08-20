// AFHTTPClientTests.m
//
// Copyright (c) 2013 AFNetworking (http://afnetworking.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFNetworkingTests.h"

@interface AFBufferedInputStreamProvider : NSObject <NSStreamDelegate>
@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, readonly) NSUInteger bytesWritten;

- (id)initWithData:(NSData *)data;
@end

@implementation AFBufferedInputStreamProvider

- (id)initWithData:(NSData *)data {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.data = data;

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreateBoundPair(NULL, &readStream, &writeStream, 16);
    
    self.inputStream = CFBridgingRelease(readStream);
    
    self.outputStream = CFBridgingRelease(writeStream);
    self.outputStream.delegate = self;
    [self.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    [self.outputStream open];

    return self;
}

- (void)dealloc {
    [self cleanup];
}

- (void)cleanup {
    [self.outputStream close];
    self.outputStream.delegate = nil;
    [self.outputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    _outputStream = nil;

    [self.inputStream close];
    _inputStream = nil;
}

- (void)writeBytesIfPossible {
    while ([self.outputStream hasSpaceAvailable] && self.bytesWritten < [self.data length]) {
        const uint8_t *bytes = [self.data bytes];
        NSInteger bytesWritten = [self.outputStream write:bytes maxLength:[self.data length] - self.bytesWritten];

        if (bytesWritten < 0) {
            [self cleanup];
            return;
        }

        _bytesWritten += bytesWritten;
    }

    if (self.bytesWritten >= [self.data length]) {
        [self cleanup];
    }
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)stream
   handleEvent:(NSStreamEvent)eventCode
{
    if (stream == self.outputStream && (eventCode & NSStreamEventHasSpaceAvailable)) {
        [self writeBytesIfPossible];
    } else if (eventCode & NSStreamEventErrorOccurred || eventCode & NSStreamEventEndEncountered) {
        [self cleanup];
    }
}

@end

#pragma mark -

@interface AFHTTPClientTests : SenTestCase
@property (readwrite, nonatomic, strong) AFHTTPClient *client;
@end

@implementation AFHTTPClientTests
@synthesize client = _client;

- (void)setUp {
    self.client = [AFHTTPClient clientWithBaseURL:[NSURL URLWithString:AFNetworkingTestsBaseURLString]];
}

#pragma mark -

- (void)testInitRaisesException {
    expect(^{ (void)[[AFHTTPClient alloc] init]; }).to.raiseAny();
}

- (void)testInitAppendsTerminatingSlashToPath {
    AFHTTPClient *client = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:@"http://httpbin.org/test"]];
    expect([[client baseURL] absoluteString]).to.equal(@"http://httpbin.org/test/");
}

- (void)testDefaultStringEncoding {
    expect([[self client] stringEncoding]).to.equal(NSUTF8StringEncoding);
}

- (void)testDefaultParameterEncoding {
    expect([[self client] parameterEncoding]).to.equal(AFFormURLParameterEncoding);
}

- (void)testDefaultHeaders {
    [self.client setDefaultHeader:@"x-some-key" value:@"SomeValue"];
    expect([self.client defaultValueForHeader:@"x-some-key"]).to.equal(@"SomeValue");

    NSMutableURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/path" parameters:nil];
    expect([request valueForHTTPHeaderField:@"x-some-key"]).to.equal(@"SomeValue");

    expect(^{ [self.client setDefaultHeader:@"x-some-key" value:nil]; }).toNot.raise(nil);
}

- (void)testReachabilityStatus {
    [Expecta setAsynchronousTestTimeout:5.0];

    expect(self.client.networkReachabilityStatus).to.equal(@(AFNetworkReachabilityStatusUnknown));

    __block AFNetworkReachabilityStatus reachabilityStatus = self.client.networkReachabilityStatus;

    [self.client setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        reachabilityStatus = status;
    }];

    expect(reachabilityStatus).will.equal(@(AFNetworkReachabilityStatusReachableViaWiFi));
}

- (void)testJSONRequestOperationContruction {
    NSMutableURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/path" parameters:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    expect([AFJSONRequestOperation canProcessRequest:request]).to.beTruthy();

    AFHTTPRequestOperation *operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect([operation class]).to.equal([AFHTTPRequestOperation class]);

    [self.client registerHTTPOperationClass:[AFJSONRequestOperation class]];
    operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect([operation class]).to.equal([AFJSONRequestOperation class]);

    [self.client unregisterHTTPOperationClass:[AFJSONRequestOperation class]];
    operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect([operation class]).to.equal([AFHTTPRequestOperation class]);
}

- (void)testXMLRequestOperationContruction {
    NSMutableURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/path" parameters:nil];
    [request setValue:@"application/xml" forHTTPHeaderField:@"Accept"];

    expect([AFXMLRequestOperation canProcessRequest:request]).to.beTruthy();

    AFHTTPRequestOperation *operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect([operation class]).to.equal([AFHTTPRequestOperation class]);

    [self.client registerHTTPOperationClass:[AFXMLRequestOperation class]];
    operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect([operation class]).to.equal([AFXMLRequestOperation class]);
}

- (void)testImageRequestOperationContruction {
    NSMutableURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/path" parameters:nil];
    [request setValue:@"image/png" forHTTPHeaderField:@"Accept"];

    expect([AFImageRequestOperation canProcessRequest:request]).to.beTruthy();

    AFHTTPRequestOperation *operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect([operation class]).to.equal([AFHTTPRequestOperation class]);

    [self.client registerHTTPOperationClass:[AFImageRequestOperation class]];
    operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect([operation class]).to.equal([AFImageRequestOperation class]);
}

- (void)testThatEnqueueBatchOfHTTPRequestOperationsFiresCompletionBlockAfterEveryRequestCompleted {
    [Expecta setAsynchronousTestTimeout:5.0];

    __block NSDate *firstCallbackTime = nil;
    __block NSDate *secondCallbackTime = nil;
    __block NSDate *batchCallbackTime = nil;

    NSMutableURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/" parameters:nil];
    AFHTTPRequestOperation *firstOperation = [self.client HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        firstCallbackTime = [NSDate date];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        firstCallbackTime = [NSDate date];
    }];

    AFHTTPRequestOperation *secondOperation = [self.client HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        secondCallbackTime = [NSDate date];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        secondCallbackTime = [NSDate date];
    }];

    [self.client enqueueBatchOfHTTPRequestOperations:@[ firstOperation, secondOperation ] progressBlock:nil completionBlock:^(NSArray *operations) {
        batchCallbackTime = [NSDate date];
    }];

    expect(self.client.operationQueue.operationCount).will.equal(0);
    expect(firstCallbackTime).willNot.beNil();
    expect(secondCallbackTime).willNot.beNil();
    expect(batchCallbackTime).willNot.beNil();
    expect(batchCallbackTime).beGreaterThan(firstCallbackTime);
    expect(batchCallbackTime).beGreaterThan(secondCallbackTime);
}

- (void)testAuthorizationHeaderWithInvalidUsernamePassword {
    [Expecta setAsynchronousTestTimeout:5.0];

    __block NSHTTPURLResponse *response = nil;
    [self.client getPath:@"/basic-auth/username/password" parameters:nil success:nil failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        response = operation.response;
    }];

    expect(response.statusCode).will.equal(401);
}

- (void)testAuthorizationHeaderWithValidUsernamePassword {
    [Expecta setAsynchronousTestTimeout:5.0];

    __block NSHTTPURLResponse *response = nil;
    [self.client setAuthorizationHeaderWithUsername:@"username" password:@"password"];
    [self.client getPath:@"/basic-auth/username/password" parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        response = operation.response;
    } failure:nil];

    expect(response.statusCode).will.equal(200);
}

- (void)testThatClientClearsAuthorizationHeader {
    [self.client setAuthorizationHeaderWithUsername:@"username" password:@"password"];
    [self.client clearAuthorizationHeader];

    NSMutableURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/path" parameters:nil];
    expect([request valueForHTTPHeaderField:@"Authorization"]).to.beNil();
}

- (void)testThatClientUsesDefaultCredential {
    NSURLCredential *credential = [NSURLCredential credentialWithUser:@"username" password:@"password" persistence:NSURLCredentialPersistenceNone];
    [self.client setDefaultCredential:credential];

    NSURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/basic-auth/username/password" parameters:nil];
    AFHTTPRequestOperation *operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    expect(operation.credential).will.equal(credential);
}

- (void)testAFQueryStringFromParametersWithEncodingWithPlainDictionary {
    NSString *query = AFQueryStringFromParametersWithEncoding(@{ @"key": @"value" }, NSUTF8StringEncoding);
    expect(query).to.equal(@"key=value");
}

- (void)testAFQueryStringFromParametersWithEncodingWithComplexNestedParameters {
    NSString *query = AFQueryStringFromParametersWithEncoding(@{ @"key1": @"value1", @"key2": @{ @"key": @[ @1, @"value" ] } }, NSUTF8StringEncoding);
    expect(query).to.equal(@"key1=value1&key2[key][]=1&key2[key][]=value");
}

- (void)testThatAFQueryStringFromParametersWithEncodingAppliesPercentEscapes {
    NSString *query = AFQueryStringFromParametersWithEncoding(@{ @"key1": @"ä" }, NSUTF8StringEncoding);
    expect(query).to.equal([@"key1=ä" stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testThatCancelAllHTTPOperationsWithMethodPathCancelsOnlyMatchingOperations {
    [self.client registerHTTPOperationClass:[AFJSONRequestOperation class]];
    [self.client registerHTTPOperationClass:[AFImageRequestOperation class]];

    NSMutableURLRequest *firstRequest = [self.client requestWithMethod:@"GET" path:@"/ip" parameters:nil];
    NSMutableURLRequest *secondRequest = [self.client requestWithMethod:@"GET" path:@"/path" parameters:nil];
    NSMutableURLRequest *thirdRequest = [self.client requestWithMethod:@"POST" path:@"/path" parameters:nil];

    [self.client enqueueBatchOfHTTPRequestOperationsWithRequests:@[ firstRequest, secondRequest, thirdRequest ] progressBlock:nil completionBlock:nil];
    [self.client.operationQueue setSuspended:YES];

    [self.client cancelAllHTTPOperationsWithMethod:@"GET" path:@"/path"];

    NSUInteger numberOfCancelledOperations = [[self.client.operationQueue.operations indexesOfObjectsPassingTest:^BOOL(NSOperation *operation, NSUInteger idx, BOOL *stop) {
        return [operation isCancelled];
    }] count];
    expect(numberOfCancelledOperations).to.equal(1);
}

- (void)testThatTheDefaultStringEncodingIsUTF8 {
    expect(self.client.stringEncoding).to.equal(NSUTF8StringEncoding);
}

- (void)testConstructingPOSTRequestWithParametersInFormURLParameterEncoding {
    self.client.parameterEncoding = AFFormURLParameterEncoding;

    NSMutableURLRequest *request = [self.client requestWithMethod:@"POST" path:@"/post" parameters:@{ @"key": @"value" }];
    NSString *requestBody = [[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding];
    expect(requestBody).to.equal(@"key=value");
}

- (void)testConstructingPOSTRequestWithParametersInJSONParameterEncoding {
    self.client.parameterEncoding = AFJSONParameterEncoding;

    NSMutableURLRequest *request = [self.client requestWithMethod:@"POST" path:@"/post" parameters:@{ @"key": @"value" }];
    NSString *requestBody = [[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding];
    expect(requestBody).to.equal(@"{\"key\":\"value\"}");
}

- (void)testConstructingPOSTRequestWithParametersInPropertyListParameterEncoding {
    self.client.parameterEncoding = AFPropertyListParameterEncoding;

    NSMutableURLRequest *request = [self.client requestWithMethod:@"POST" path:@"/post" parameters:@{ @"key": @"value" }];
    NSString *requestBody = [[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding];
    expect(requestBody).to.equal(@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n	<key>key</key>\n	<string>value</string>\n</dict>\n</plist>\n");
}

- (void)testPostWithParameters {
    [Expecta setAsynchronousTestTimeout:5.0];

    __block id blockResponseObject = nil;
    [self.client postPath:@"/post" parameters:@{ @"key": @"value" } success:^(AFHTTPRequestOperation *operation, id responseObject) {
        blockResponseObject = responseObject;
    } failure:nil];

    expect([self.client.operationQueue operationCount]).will.equal(0);
    expect(blockResponseObject).willNot.beNil();
    expect(blockResponseObject).to.beKindOf([NSData class]);

    NSError *error = nil;
    NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:blockResponseObject options:0 error:&error];
    expect([responseDictionary valueForKey:@"form"]).to.equal(@{ @"key": @"value" });
}

- (void)testThatEnqueueBatchOfHTTPRequestOperationsConstructsOperationsWithAppropriateRegisteredHTTPRequestOperationClasses {
    [self.client registerHTTPOperationClass:[AFJSONRequestOperation class]];
    [self.client registerHTTPOperationClass:[AFImageRequestOperation class]];

    NSMutableURLRequest *firstRequest = [self.client requestWithMethod:@"GET" path:@"/" parameters:nil];
    [firstRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSMutableURLRequest *secondRequest = [self.client requestWithMethod:@"GET" path:@"/" parameters:nil];
    [secondRequest setValue:@"image/png" forHTTPHeaderField:@"Accept"];

    __block NSArray *operations = nil;
    id mockClient = [OCMockObject partialMockForObject:self.client];
    void (^block)(NSInvocation *) = ^(NSInvocation *invocation) {
        __unsafe_unretained id argument = nil;
        [invocation getArgument:&argument atIndex:2];

        operations = argument;
    };
    [[[mockClient stub] andDo:block] enqueueBatchOfHTTPRequestOperations:[OCMArg any] progressBlock:nil completionBlock:nil];
    [mockClient enqueueBatchOfHTTPRequestOperationsWithRequests:@[ firstRequest, secondRequest ] progressBlock:nil completionBlock:nil];

    expect(operations).notTo.beNil();
    expect(operations).to.haveCountOf(2);

    expect([[operations objectAtIndex:0] class]).to.equal([AFJSONRequestOperation class]);
    expect([[operations objectAtIndex:1] class]).to.equal([AFImageRequestOperation class]);
}

- (void)testThatEnqueueBatchOfHTTPRequestOperationsEnqueuesOperationsInTheCorrectOrder {
    NSMutableURLRequest *request = [self.client requestWithMethod:@"GET" path:@"/" parameters:nil];
    AFHTTPRequestOperation *firstOperation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];
    AFHTTPRequestOperation *secondOperation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];

    id mockClient = [OCMockObject partialMockForObject:self.client];
    id mockOperationQueue = [OCMockObject mockForClass:[NSOperationQueue class]];
    [[[mockClient stub] andReturn:mockOperationQueue] operationQueue];

    __block NSArray *operations = nil;
    [[[mockOperationQueue stub] andDo:^(NSInvocation *invocation) {
        __unsafe_unretained id argument = nil;
        [invocation getArgument:&argument atIndex:2];

        operations = argument;
    }] addOperations:OCMOCK_ANY waitUntilFinished:NO];

    __block NSBlockOperation *batchedOperation = nil;
    [[[mockOperationQueue stub] andDo:^(NSInvocation *invocation) {
        __unsafe_unretained id argument = nil;
        [invocation getArgument:&argument atIndex:2];

        batchedOperation = argument;
    }] addOperation:OCMOCK_ANY];
    [mockClient enqueueBatchOfHTTPRequestOperations:@[ firstOperation, secondOperation ] progressBlock:nil completionBlock:nil];

    expect(operations).to.haveCountOf(2);

    expect([operations objectAtIndex:0]).to.equal(firstOperation);
    expect([operations objectAtIndex:1]).to.equal(secondOperation);

    expect(batchedOperation).notTo.beNil();
    expect(batchedOperation).to.beKindOf([NSBlockOperation class]);
}

- (void)testMultipartUploadDoesNotFailDueToStreamSentAnEventBeforeBeingOpenedError {
    NSString *pathToImage = [[NSBundle bundleForClass:[AFHTTPClient class]] pathForResource:@"Icon" ofType:@"png"];
    NSData *imageData = [NSData dataWithContentsOfFile:pathToImage];
    NSMutableURLRequest *request = [self.client multipartFormRequestWithMethod:@"POST" path:@"/post" parameters:@{ @"foo": @"bar" } constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFileData:imageData name:@"icon[image]" fileName:@"icon.png" mimeType:@"image/png"];
    }];
    AFHTTPRequestOperation *operation = [self.client HTTPRequestOperationWithRequest:request success:nil failure:nil];

    [self.client enqueueHTTPRequestOperation:operation];
    expect(operation.isFinished).will.beTruthy();
    expect(operation.error).notTo.equal(NSURLErrorTimedOut);
}

- (void)testMultipartUploadDoesNotPrematurelyCloseInputStream {
    NSMutableString *mutableString = [NSMutableString string];
    for (NSUInteger i = 0; i < 10; i++) {
        [mutableString appendString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"];
    }

    NSData *data = [mutableString dataUsingEncoding:NSUTF8StringEncoding];
    __block AFBufferedInputStreamProvider *streamProvider = [[AFBufferedInputStreamProvider alloc] initWithData:data];
    __block NSUInteger bytesWritten = 0;
    NSInputStream *inputStream = streamProvider.inputStream;

    NSMutableURLRequest *request = [self.client multipartFormRequestWithMethod:@"POST" path:@"/post" parameters:@{ @"foo": @"bar" } constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithInputStream:inputStream name:@"data" fileName:@"string.txt" length:[data length] mimeType:@"text/plain"];
    }];
    
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    operation.completionBlock = ^{
        bytesWritten = streamProvider.bytesWritten;
        streamProvider = nil;
    };
    
    [self.client enqueueHTTPRequestOperation:operation];
    expect(operation.isFinished).will.beTruthy();
    expect(bytesWritten).will.equal([data length]);
}

@end
