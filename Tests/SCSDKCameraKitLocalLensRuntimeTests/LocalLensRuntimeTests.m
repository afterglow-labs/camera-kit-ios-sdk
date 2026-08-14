#import <XCTest/XCTest.h>
#import <SCSDKCameraKitLocalLensRuntime.h>

@interface AGFakeLensRepository : NSObject
@property(nonatomic, copy) NSArray *registeredLenses;
@property(nonatomic, copy) NSString *registeredGroupID;
@property(nonatomic, copy) NSString *unregisteredGroupID;
@property(nonatomic) NSUInteger registrationCount;
@end

@implementation AGFakeLensRepository
- (void)registerLenses:(NSArray *)lenses groupID:(NSString *)groupID
{
    self.registeredLenses = lenses;
    self.registeredGroupID = groupID;
    self.registrationCount += 1;
}

- (void)unregisterLensesForGroupID:(NSString *)groupID
{
    self.unregisteredGroupID = groupID;
}
@end

@interface LocalLensRuntimeTests : XCTestCase
@end

@implementation LocalLensRuntimeTests

- (void)testPinnedCameraKitRuntimeMatchesExpectedABI
{
    NSError *error = nil;

    XCTAssertTrue([SCCameraKitLocalLensRuntimeExtension isSupportedRuntimeWithError:&error]);
    XCTAssertNil(error);
}

- (void)testExtensionConformsToRecoveredSideloadProtocol
{
    SCCameraKitLocalLensRuntimeExtension *extension = [self makeExtension];
    Protocol *protocol = NSProtocolFromString(@"SCCameraKitSideloadExtension");

    XCTAssertNotNil(protocol);
    XCTAssertTrue([extension conformsToProtocol:protocol]);
}

- (void)testSetRepositoryForwardsLensesWithoutChecksumBypass
{
    SCCameraKitLocalLensRuntimeExtension *extension = [self makeExtension];
    AGFakeLensRepository *repository = [AGFakeLensRepository new];

    XCTAssertFalse([repository respondsToSelector:NSSelectorFromString(@"registerLenses:groupID:skipChecksumValidation:")]);
    [extension setRepository:repository];

    XCTAssertEqual(repository.registeredLenses.count, 1);
    XCTAssertEqualObjects(repository.registeredGroupID, @"test.local");
    XCTAssertNil(extension.registrationError);
}

- (void)testUnregisterForwardsTheSameGroupIdentifier
{
    SCCameraKitLocalLensRuntimeExtension *extension = [self makeExtension];
    AGFakeLensRepository *repository = [AGFakeLensRepository new];
    [extension setRepository:repository];

    [extension unregisterLenses];

    XCTAssertEqualObjects(repository.unregisteredGroupID, @"test.local");
}

- (void)testDuplicateRepositoryInjectionIsIdempotent
{
    SCCameraKitLocalLensRuntimeExtension *extension = [self makeExtension];
    AGFakeLensRepository *repository = [AGFakeLensRepository new];

    [extension setRepository:repository];
    [extension setRepository:repository];

    XCTAssertEqual(repository.registrationCount, 1);
}

- (void)testConstructsLensAndAssetWithLocalResourcePaths
{
    SCCameraKitLocalLensRuntimeExtension *extension = [self makeExtension];
    AGFakeLensRepository *repository = [AGFakeLensRepository new];
    [extension setRepository:repository];

    id lens = repository.registeredLenses.firstObject;
    NSArray *assets = [lens valueForKey:@"assets"];
    id asset = assets.firstObject;
    XCTAssertEqualObjects(NSStringFromClass([lens class]), @"SCCameraKitLensImpl");
    XCTAssertEqualObjects([lens valueForKey:@"identifier"], @"lens-one");
    XCTAssertEqualObjects([lens valueForKey:@"resourcesPath"], @"/tmp/lens-one.lzc");
    XCTAssertEqualObjects(NSStringFromClass([asset class]), @"SCCameraKitLensAssetImpl");
    XCTAssertEqualObjects([asset valueForKey:@"identifier"], @"asset-one");
    XCTAssertEqualObjects([asset valueForKey:@"assetType"], @7);
    XCTAssertEqualObjects([asset valueForKey:@"assetTiming"], @6);
    XCTAssertEqualObjects([asset valueForKey:@"resourcesPath"], @"/tmp/asset-one.lzc");
}

- (SCCameraKitLocalLensRuntimeExtension *)makeExtension
{
    SCCameraKitLocalLensRuntimeAssetDescriptor *asset =
        [[SCCameraKitLocalLensRuntimeAssetDescriptor alloc]
            initWithIdentifier:@"asset-one"
            assetType:7
            assetTiming:6
            contentURL:[NSURL URLWithString:@"https://example.com/asset-one.lzc"]
            checksum:@"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
            resourcePath:@"/tmp/asset-one.lzc"];
    SCCameraKitLocalLensRuntimeLensDescriptor *lens =
        [[SCCameraKitLocalLensRuntimeLensDescriptor alloc]
            initWithIdentifier:@"lens-one"
            groupIdentifier:@"test.local"
            name:@"Lens One"
            iconURL:[NSURL fileURLWithPath:@"/tmp/lens-one.png"]
            contentURL:[NSURL URLWithString:@"https://example.com/lens-one.lzc"]
            checksum:@"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
            resourcePath:@"/tmp/lens-one.lzc"
            facingPreference:0
            assets:@[ asset ]];
    NSError *error = nil;
    SCCameraKitLocalLensRuntimeExtension *extension =
        [[SCCameraKitLocalLensRuntimeExtension alloc]
            initWithGroupIdentifier:@"test.local"
            lenses:@[ lens ]
            error:&error];
    XCTAssertNotNil(extension);
    XCTAssertNil(error);
    return extension;
}
@end
