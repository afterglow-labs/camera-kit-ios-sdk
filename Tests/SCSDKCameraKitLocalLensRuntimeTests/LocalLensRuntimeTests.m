#import <XCTest/XCTest.h>
#import <SCSDKCameraKitLocalLensRuntime.h>

@interface AGFakeGroupAnnouncer : NSObject
@property(nonatomic, copy) NSArray *updatedLenses;
@property(nonatomic, copy) NSString *updatedGroupID;
@property(nonatomic) NSUInteger updateCount;
@end

@implementation AGFakeGroupAnnouncer
- (void)repository:(id)repository didUpdateLenses:(NSArray *)lenses forGroupID:(NSString *)groupID
{
    self.updatedLenses = lenses;
    self.updatedGroupID = groupID;
    self.updateCount += 1;
}
@end

@interface AGFakeLensRepository : NSObject {
@public
    NSLock *_fetchedResponsesLock;
    NSMutableDictionary *_fetchedResponses;
}
@property(nonatomic, copy) NSArray *registeredLenses;
@property(nonatomic, copy) NSString *registeredGroupID;
@property(nonatomic, copy) NSString *unregisteredGroupID;
@property(nonatomic) NSUInteger registrationCount;
@property(nonatomic, strong) AGFakeGroupAnnouncer *groupAnnouncer;
- (id)collectionForGroupID:(NSString *)groupID;
@end

@implementation AGFakeLensRepository

- (instancetype)init
{
    self = [super init];
    if (self) {
        _fetchedResponsesLock = [NSLock new];
        _fetchedResponses = [NSMutableDictionary dictionary];
        _groupAnnouncer = [AGFakeGroupAnnouncer new];
    }
    return self;
}

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

- (id)_groupAnnouncerForGroupID:(NSString *)groupID
{
    return self.groupAnnouncer;
}

- (id)collectionForGroupID:(NSString *)groupID
{
    [_fetchedResponsesLock lock];
    id collection = _fetchedResponses[groupID];
    [_fetchedResponsesLock unlock];
    return collection;
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

- (void)testSetRepositoryInstallsPrefetchedLensesWithoutUsingSerializedRegistration
{
    SCCameraKitLocalLensRuntimeExtension *extension = [self makeExtension];
    AGFakeLensRepository *repository = [AGFakeLensRepository new];

    [extension setRepository:repository];

    id collection = [repository collectionForGroupID:@"test.local"];
    NSArray *lenses = [collection valueForKey:@"lenses"];
    id lens = lenses.firstObject;
    XCTAssertEqual(repository.registrationCount, 0);
    XCTAssertEqual(lenses.count, 1);
    XCTAssertEqualObjects([lens valueForKey:@"identifier"], @"lens-one");
    XCTAssertEqualObjects([lens valueForKey:@"resourcesPath"], @"/tmp/lens-one.lzc");
    XCTAssertEqualObjects(repository.groupAnnouncer.updatedLenses, lenses);
    XCTAssertEqualObjects(repository.groupAnnouncer.updatedGroupID, @"test.local");
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

    XCTAssertEqual(repository.registrationCount, 0);
    XCTAssertEqual(repository.groupAnnouncer.updateCount, 1);
    XCTAssertNotNil([repository collectionForGroupID:@"test.local"]);
}

- (void)testConstructsLensAndAssetWithLocalResourcePaths
{
    SCCameraKitLocalLensRuntimeExtension *extension = [self makeExtension];
    id lens = extension.lenses.firstObject;
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
