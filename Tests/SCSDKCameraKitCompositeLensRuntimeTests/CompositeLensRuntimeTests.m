#import <XCTest/XCTest.h>
#import <SCSDKCameraKitCompositeLensRuntime.h>

@interface AGFakeCompositeProcessor : NSObject
@property(nonatomic, copy) NSArray *receivedLenses;
@property(nonatomic, copy) NSArray *receivedLaunchData;
@end

@implementation AGFakeCompositeProcessor

- (void)applyLenses:(NSArray *)lenses
         launchData:(NSArray *)launchData
         completion:(void (^)(BOOL))completion
{
    self.receivedLenses = lenses;
    self.receivedLaunchData = launchData;
    completion(YES);
}

@end

@interface CompositeLensRuntimeTests : XCTestCase
@end

@implementation CompositeLensRuntimeTests

- (void)testSupportedProcessorReceivesOrderedArrays
{
    AGFakeCompositeProcessor *processor = [AGFakeCompositeProcessor new];
    NSArray *lenses = @[ @"base", @"top" ];
    NSArray *launchData = @[ [NSNull null], @"top-data" ];
    __block NSUInteger completionCount = 0;

    SCCameraKitApplyCompositeLenses(processor, lenses, launchData, ^(BOOL success) {
        completionCount += 1;
        XCTAssertTrue(success);
    });

    XCTAssertTrue(SCCameraKitProcessorSupportsCompositeLenses(processor));
    XCTAssertEqualObjects(processor.receivedLenses, lenses);
    XCTAssertEqualObjects(processor.receivedLaunchData, launchData);
    XCTAssertEqual(completionCount, 1u);
}

- (void)testUnsupportedProcessorFailsExactlyOnce
{
    __block NSUInteger completionCount = 0;

    SCCameraKitApplyCompositeLenses(
        [NSObject new],
        @[ @"base", @"top" ],
        @[ [NSNull null], [NSNull null] ],
        ^(BOOL success) {
            completionCount += 1;
            XCTAssertFalse(success);
        }
    );

    XCTAssertEqual(completionCount, 1u);
}

- (void)testMismatchedLaunchDataFailsWithoutCallingProcessor
{
    AGFakeCompositeProcessor *processor = [AGFakeCompositeProcessor new];
    __block NSUInteger completionCount = 0;

    SCCameraKitApplyCompositeLenses(processor, @[ @"base", @"top" ], @[ [NSNull null] ], ^(BOOL success) {
        completionCount += 1;
        XCTAssertFalse(success);
    });

    XCTAssertNil(processor.receivedLenses);
    XCTAssertNil(processor.receivedLaunchData);
    XCTAssertEqual(completionCount, 1u);
}

@end
