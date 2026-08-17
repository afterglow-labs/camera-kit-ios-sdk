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

@interface AGFakeVideoProcessingComponent : NSObject
@property(nonatomic) NSInteger renderingWidth;
@property(nonatomic) NSInteger renderingHeight;
@end

@implementation AGFakeVideoProcessingComponent

- (void)setYuvRenderingResolutionWidth:(NSInteger)width height:(NSInteger)height
{
    self.renderingWidth = width;
    self.renderingHeight = height;
}

@end

@interface AGFakeComponentManager : NSObject
@property(nonatomic, strong) AGFakeVideoProcessingComponent *videoProcessingComponent;
@end

@implementation AGFakeComponentManager
@end

@interface AGFakeHighDefinitionProcessor : NSObject {
@public
    AGFakeComponentManager *_componentManager;
}
@end

@implementation AGFakeHighDefinitionProcessor
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

- (void)testHighDefinitionRenderingRequestReachesLensVideoProcessor
{
    AGFakeVideoProcessingComponent *videoProcessor = [AGFakeVideoProcessingComponent new];
    AGFakeComponentManager *componentManager = [AGFakeComponentManager new];
    componentManager.videoProcessingComponent = videoProcessor;
    AGFakeHighDefinitionProcessor *processor = [AGFakeHighDefinitionProcessor new];
    processor->_componentManager = componentManager;

    XCTAssertTrue(SCCameraKitProcessorSupportsHighDefinitionRendering(processor));
    XCTAssertTrue(SCCameraKitSetHighDefinitionRenderingResolution(processor, 1920, 1080));
    XCTAssertEqual(videoProcessor.renderingWidth, 1920);
    XCTAssertEqual(videoProcessor.renderingHeight, 1080);
}

- (void)testHighDefinitionRenderingRejectsMissingRuntimeAndInvalidSize
{
    XCTAssertFalse(SCCameraKitProcessorSupportsHighDefinitionRendering([NSObject new]));
    XCTAssertFalse(SCCameraKitSetHighDefinitionRenderingResolution([NSObject new], 1920, 1080));

    AGFakeHighDefinitionProcessor *processor = [AGFakeHighDefinitionProcessor new];
    XCTAssertFalse(SCCameraKitSetHighDefinitionRenderingResolution(processor, 0, 1080));
}

@end
