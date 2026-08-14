#import "SCSDKCameraKitLocalLensRuntime.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

NSErrorDomain const SCCameraKitLocalLensRuntimeErrorDomain = @"SCSDKCameraKitLocalLensRuntimeErrorDomain";

static NSString *const AGSideloadProtocolName = @"SCCameraKitSideloadExtension";
static NSString *const AGLensClassName = @"SCCameraKitLensImpl";
static NSString *const AGAssetClassName = @"SCCameraKitLensAssetImpl";
static NSString *const AGPreviewClassName = @"SCCameraKitLensPreviewImpl";
static NSString *const AGSnapcodesClassName = @"SCCameraKitLensSnapcodesImpl";
static NSString *const AGRepositoryClassName = @"SCCameraKitLensRepositoryImpl";

static SEL AGAssetInitializer(void)
{
    return NSSelectorFromString(@"initWithIdentifier:assetType:assetTiming:contentUrl:checksum:encryptionKey:resourcesPath:");
}

static SEL AGLensInitializer(void)
{
    return NSSelectorFromString(@"initWithIdentifier:groupIdentifier:name:iconUrl:preview:vendorData:hintTranslations:defaultHintId:resourcesPath:contentUrl:checksum:assets:isThirdParty:facingPreference:featureMetadata:snapcodes:");
}

static SEL AGRegisterSelector(void)
{
    return NSSelectorFromString(@"registerLenses:groupID:");
}

static SEL AGUnregisterSelector(void)
{
    return NSSelectorFromString(@"unregisterLensesForGroupID:");
}

static BOOL AGFail(NSError **error, SCCameraKitLocalLensRuntimeErrorCode code, NSString *message)
{
    if (error != NULL) {
        *error = [NSError errorWithDomain:SCCameraKitLocalLensRuntimeErrorDomain
                                     code:code
                                 userInfo:@{ NSLocalizedDescriptionKey: message }];
    }
    return NO;
}

static const char *AGSkipTypeQualifiers(const char *encoding)
{
    while (encoding != NULL && strchr("rnNoORV", encoding[0]) != NULL) {
        encoding += 1;
    }
    return encoding;
}

static BOOL AGTypeMatches(const char *actual, const char *expected)
{
    actual = AGSkipTypeQualifiers(actual);
    expected = AGSkipTypeQualifiers(expected);
    if (actual == NULL || expected == NULL) {
        return NO;
    }
    if (expected[0] == '@') {
        return actual[0] == '@';
    }
    return strcmp(actual, expected) == 0;
}

static BOOL AGValidateMethod(
    Class cls,
    SEL selector,
    const char *expectedReturnType,
    const char *const *expectedArgumentTypes,
    unsigned int expectedArgumentCount,
    NSError **error
)
{
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) {
        return AGFail(
            error,
            SCCameraKitLocalLensRuntimeErrorMissingRuntimeSymbol,
            [NSString stringWithFormat:@"Missing -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(selector)]
        );
    }

    unsigned int actualArgumentCount = method_getNumberOfArguments(method);
    if (actualArgumentCount != expectedArgumentCount) {
        return AGFail(
            error,
            SCCameraKitLocalLensRuntimeErrorABIMismatch,
            [NSString stringWithFormat:@"Argument count changed for -[%@ %@]: expected %u, received %u",
                NSStringFromClass(cls), NSStringFromSelector(selector), expectedArgumentCount, actualArgumentCount]
        );
    }

    char *returnType = method_copyReturnType(method);
    BOOL returnMatches = AGTypeMatches(returnType, expectedReturnType);
    free(returnType);
    if (!returnMatches) {
        return AGFail(
            error,
            SCCameraKitLocalLensRuntimeErrorABIMismatch,
            [NSString stringWithFormat:@"Return type changed for -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(selector)]
        );
    }

    for (unsigned int index = 0; index < expectedArgumentCount; index += 1) {
        char *argumentType = method_copyArgumentType(method, index);
        BOOL argumentMatches = AGTypeMatches(argumentType, expectedArgumentTypes[index]);
        free(argumentType);
        if (!argumentMatches) {
            return AGFail(
                error,
                SCCameraKitLocalLensRuntimeErrorABIMismatch,
                [NSString stringWithFormat:@"Argument %u changed for -[%@ %@]",
                    index, NSStringFromClass(cls), NSStringFromSelector(selector)]
            );
        }
    }
    return YES;
}

static id AGCreateEmptyObject(Class cls)
{
    typedef id (*AGObjectMessage)(id, SEL);
    AGObjectMessage send = (AGObjectMessage)objc_msgSend;
    id allocated = send((id)cls, @selector(alloc));
    return send(allocated, @selector(init));
}

static id AGAllocateObject(Class cls)
{
    typedef id (*AGObjectMessage)(id, SEL);
    AGObjectMessage send = (AGObjectMessage)objc_msgSend;
    return send((id)cls, @selector(alloc));
}

@interface SCCameraKitLocalLensRuntimeAssetDescriptor ()
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic) NSInteger assetType;
@property(nonatomic) NSInteger assetTiming;
@property(nonatomic, copy) NSURL *contentURL;
@property(nonatomic, copy) NSString *checksum;
@property(nonatomic, copy) NSString *resourcePath;
@end

@implementation SCCameraKitLocalLensRuntimeAssetDescriptor

- (instancetype)initWithIdentifier:(NSString *)identifier
                          assetType:(NSInteger)assetType
                        assetTiming:(NSInteger)assetTiming
                         contentURL:(NSURL *)contentURL
                           checksum:(NSString *)checksum
                       resourcePath:(NSString *)resourcePath
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _assetType = assetType;
        _assetTiming = assetTiming;
        _contentURL = [contentURL copy];
        _checksum = [checksum copy];
        _resourcePath = [resourcePath copy];
    }
    return self;
}

@end


@interface SCCameraKitLocalLensRuntimeLensDescriptor ()
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *groupIdentifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSURL *iconURL;
@property(nonatomic, copy) NSURL *contentURL;
@property(nonatomic, copy) NSString *checksum;
@property(nonatomic, copy) NSString *resourcePath;
@property(nonatomic) NSInteger facingPreference;
@property(nonatomic, copy) NSArray<SCCameraKitLocalLensRuntimeAssetDescriptor *> *assets;
@end

@implementation SCCameraKitLocalLensRuntimeLensDescriptor

- (instancetype)initWithIdentifier:(NSString *)identifier
                    groupIdentifier:(NSString *)groupIdentifier
                               name:(NSString *)name
                            iconURL:(NSURL *)iconURL
                         contentURL:(NSURL *)contentURL
                           checksum:(NSString *)checksum
                       resourcePath:(NSString *)resourcePath
                   facingPreference:(NSInteger)facingPreference
                             assets:(NSArray<SCCameraKitLocalLensRuntimeAssetDescriptor *> *)assets
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _groupIdentifier = [groupIdentifier copy];
        _name = [name copy];
        _iconURL = [iconURL copy];
        _contentURL = [contentURL copy];
        _checksum = [checksum copy];
        _resourcePath = [resourcePath copy];
        _facingPreference = facingPreference;
        _assets = [assets copy];
    }
    return self;
}

@end


@interface SCCameraKitLocalLensRuntimeExtension ()
@property(nonatomic, copy, readwrite) NSString *groupIdentifier;
@property(nonatomic, copy, readwrite) NSArray *lenses;
@property(nonatomic, strong, readwrite, nullable) NSError *registrationError;
@property(nonatomic, weak, nullable) id registeredRepository;
@property(nonatomic) BOOL registered;
@end

@implementation SCCameraKitLocalLensRuntimeExtension

+ (BOOL)isSupportedRuntimeWithError:(NSError **)error
{
    Protocol *sideloadProtocol = NSProtocolFromString(AGSideloadProtocolName);
    if (sideloadProtocol == nil) {
        return AGFail(error, SCCameraKitLocalLensRuntimeErrorMissingRuntimeSymbol, @"Missing SCCameraKitSideloadExtension protocol");
    }

    Class lensClass = NSClassFromString(AGLensClassName);
    Class assetClass = NSClassFromString(AGAssetClassName);
    Class previewClass = NSClassFromString(AGPreviewClassName);
    Class snapcodesClass = NSClassFromString(AGSnapcodesClassName);
    Class repositoryClass = NSClassFromString(AGRepositoryClassName);
    NSArray<NSString *> *classNames = @[
        AGLensClassName,
        AGAssetClassName,
        AGPreviewClassName,
        AGSnapcodesClassName,
        AGRepositoryClassName,
    ];
    Class classes[] = { lensClass, assetClass, previewClass, snapcodesClass, repositoryClass };
    for (NSUInteger index = 0; index < classNames.count; index += 1) {
        if (classes[index] == Nil) {
            return AGFail(
                error,
                SCCameraKitLocalLensRuntimeErrorMissingRuntimeSymbol,
                [NSString stringWithFormat:@"Missing %@ class", classNames[index]]
            );
        }
    }

    const char *assetArguments[] = { @encode(id), @encode(SEL), @encode(id), @encode(NSInteger), @encode(NSInteger), @encode(id), @encode(id), @encode(id), @encode(id) };
    if (!AGValidateMethod(assetClass, AGAssetInitializer(), @encode(id), assetArguments, 9, error)) {
        return NO;
    }

    const char *lensArguments[] = {
        @encode(id), @encode(SEL),
        @encode(id), @encode(id), @encode(id), @encode(id),
        @encode(id), @encode(id), @encode(id), @encode(id),
        @encode(id), @encode(id), @encode(id), @encode(id),
        @encode(BOOL), @encode(NSInteger), @encode(id), @encode(id),
    };
    if (!AGValidateMethod(lensClass, AGLensInitializer(), @encode(id), lensArguments, 18, error)) {
        return NO;
    }

    const char *registerArguments[] = { @encode(id), @encode(SEL), @encode(id), @encode(id) };
    if (!AGValidateMethod(repositoryClass, AGRegisterSelector(), @encode(void), registerArguments, 4, error)) {
        return NO;
    }

    const char *unregisterArguments[] = { @encode(id), @encode(SEL), @encode(id) };
    if (!AGValidateMethod(repositoryClass, AGUnregisterSelector(), @encode(void), unregisterArguments, 3, error)) {
        return NO;
    }

    Class extensionClass = self;
    if (!class_conformsToProtocol(extensionClass, sideloadProtocol)
        && !class_addProtocol(extensionClass, sideloadProtocol)) {
        return AGFail(error, SCCameraKitLocalLensRuntimeErrorABIMismatch, @"Could not adopt SCCameraKitSideloadExtension");
    }

    if (error != NULL) {
        *error = nil;
    }
    return YES;
}

- (nullable instancetype)initWithGroupIdentifier:(NSString *)groupIdentifier
                                          lenses:(NSArray<SCCameraKitLocalLensRuntimeLensDescriptor *> *)descriptors
                                           error:(NSError **)error
{
    if (groupIdentifier.length == 0) {
        AGFail(error, SCCameraKitLocalLensRuntimeErrorInvalidDescriptor, @"Local Lens group identifier is empty");
        return nil;
    }
    self = [super init];
    if (self == nil) {
        return nil;
    }
    if (![[self class] isSupportedRuntimeWithError:error]) {
        return nil;
    }

    Class assetClass = NSClassFromString(AGAssetClassName);
    Class lensClass = NSClassFromString(AGLensClassName);
    Class previewClass = NSClassFromString(AGPreviewClassName);
    Class snapcodesClass = NSClassFromString(AGSnapcodesClassName);
    NSMutableArray *runtimeLenses = [NSMutableArray arrayWithCapacity:descriptors.count];

    typedef id (*AGAssetInitializerIMP)(id, SEL, id, NSInteger, NSInteger, id, id, id, id);
    AGAssetInitializerIMP initializeAsset = (AGAssetInitializerIMP)objc_msgSend;
    typedef id (*AGLensInitializerIMP)(
        id, SEL,
        id, id, id, id, id, id, id, id,
        id, id, id, id, BOOL, NSInteger, id, id
    );
    AGLensInitializerIMP initializeLens = (AGLensInitializerIMP)objc_msgSend;

    for (SCCameraKitLocalLensRuntimeLensDescriptor *descriptor in descriptors) {
        if (![descriptor.groupIdentifier isEqualToString:groupIdentifier]) {
            AGFail(
                error,
                SCCameraKitLocalLensRuntimeErrorInvalidDescriptor,
                [NSString stringWithFormat:@"Lens %@ belongs to unexpected group %@", descriptor.identifier, descriptor.groupIdentifier]
            );
            return nil;
        }

        NSMutableArray *runtimeAssets = [NSMutableArray arrayWithCapacity:descriptor.assets.count];
        for (SCCameraKitLocalLensRuntimeAssetDescriptor *asset in descriptor.assets) {
            id allocatedAsset = AGAllocateObject(assetClass);
            id runtimeAsset = initializeAsset(
                allocatedAsset,
                AGAssetInitializer(),
                asset.identifier,
                asset.assetType,
                asset.assetTiming,
                asset.contentURL,
                asset.checksum,
                nil,
                asset.resourcePath
            );
            if (runtimeAsset == nil) {
                AGFail(
                    error,
                    SCCameraKitLocalLensRuntimeErrorInvalidDescriptor,
                    [NSString stringWithFormat:@"Camera Kit rejected local asset %@", asset.identifier]
                );
                return nil;
            }
            [runtimeAssets addObject:runtimeAsset];
        }

        id preview = AGCreateEmptyObject(previewClass);
        id snapcodes = AGCreateEmptyObject(snapcodesClass);
        id allocatedLens = AGAllocateObject(lensClass);
        id runtimeLens = initializeLens(
            allocatedLens,
            AGLensInitializer(),
            descriptor.identifier,
            descriptor.groupIdentifier,
            descriptor.name,
            descriptor.iconURL,
            preview,
            @{},
            @{},
            nil,
            descriptor.resourcePath,
            descriptor.contentURL,
            descriptor.checksum,
            runtimeAssets,
            NO,
            descriptor.facingPreference,
            @{},
            snapcodes
        );
        if (runtimeLens == nil) {
            AGFail(
                error,
                SCCameraKitLocalLensRuntimeErrorInvalidDescriptor,
                [NSString stringWithFormat:@"Camera Kit rejected local Lens %@", descriptor.identifier]
            );
            return nil;
        }
        [runtimeLenses addObject:runtimeLens];
    }

    _groupIdentifier = [groupIdentifier copy];
    _lenses = [runtimeLenses copy];
    if (error != NULL) {
        *error = nil;
    }
    return self;
}

- (BOOL)registerWithRepository:(id)repository error:(NSError **)error
{
    @synchronized (self) {
        if (self.registered && self.registeredRepository == repository) {
            if (error != NULL) {
                *error = nil;
            }
            return YES;
        }
        if (self.registered) {
            return AGFail(error, SCCameraKitLocalLensRuntimeErrorRepositoryUnavailable, @"Local Lenses are already registered with another repository");
        }
        if (![repository respondsToSelector:AGRegisterSelector()]
            || ![repository respondsToSelector:AGUnregisterSelector()]) {
            return AGFail(error, SCCameraKitLocalLensRuntimeErrorRepositoryUnavailable, @"Camera Kit repository registration API is unavailable");
        }

        typedef void (*AGRepositoryMessage)(id, SEL, id, id);
        AGRepositoryMessage send = (AGRepositoryMessage)objc_msgSend;
        send(repository, AGRegisterSelector(), self.lenses, self.groupIdentifier);
        self.registeredRepository = repository;
        self.registered = YES;
        self.registrationError = nil;
        if (error != NULL) {
            *error = nil;
        }
        return YES;
    }
}

- (void)setRepository:(id)repository
{
    NSError *error = nil;
    [self registerWithRepository:repository error:&error];
    self.registrationError = error;
}

- (void)unregisterLenses
{
    @synchronized (self) {
        id repository = self.registeredRepository;
        if (!self.registered || repository == nil) {
            self.registered = NO;
            self.registeredRepository = nil;
            return;
        }

        typedef void (*AGRepositoryMessage)(id, SEL, id);
        AGRepositoryMessage send = (AGRepositoryMessage)objc_msgSend;
        send(repository, AGUnregisterSelector(), self.groupIdentifier);
        self.registered = NO;
        self.registeredRepository = nil;
    }
}

- (void)dealloc
{
    [self unregisterLenses];
}

@end
