#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const SCCameraKitLocalLensRuntimeErrorDomain;

typedef NS_ERROR_ENUM(SCCameraKitLocalLensRuntimeErrorDomain, SCCameraKitLocalLensRuntimeErrorCode) {
    SCCameraKitLocalLensRuntimeErrorMissingRuntimeSymbol = 1,
    SCCameraKitLocalLensRuntimeErrorABIMismatch = 2,
    SCCameraKitLocalLensRuntimeErrorInvalidDescriptor = 3,
    SCCameraKitLocalLensRuntimeErrorRepositoryUnavailable = 4,
};

@interface SCCameraKitLocalLensRuntimeAssetDescriptor : NSObject

- (instancetype)initWithIdentifier:(NSString *)identifier
                          assetType:(NSInteger)assetType
                        assetTiming:(NSInteger)assetTiming
                         contentURL:(NSURL *)contentURL
                           checksum:(NSString *)checksum
                       resourcePath:(NSString *)resourcePath NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end


@interface SCCameraKitLocalLensRuntimeLensDescriptor : NSObject

- (instancetype)initWithIdentifier:(NSString *)identifier
                    groupIdentifier:(NSString *)groupIdentifier
                               name:(NSString *)name
                            iconURL:(NSURL *)iconURL
                         contentURL:(NSURL *)contentURL
                           checksum:(NSString *)checksum
                       resourcePath:(NSString *)resourcePath
                   facingPreference:(NSInteger)facingPreference
                             assets:(NSArray<SCCameraKitLocalLensRuntimeAssetDescriptor *> *)assets NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end


@interface SCCameraKitLocalLensRuntimeExtension : NSObject

@property(nonatomic, copy, readonly) NSString *groupIdentifier;
@property(nonatomic, copy, readonly) NSArray *lenses;
@property(nonatomic, strong, readonly, nullable) NSError *registrationError;

+ (BOOL)isSupportedRuntimeWithError:(NSError * _Nullable * _Nullable)error;

- (nullable instancetype)initWithGroupIdentifier:(NSString *)groupIdentifier
                                          lenses:(NSArray<SCCameraKitLocalLensRuntimeLensDescriptor *> *)lenses
                                           error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (BOOL)registerWithRepository:(id)repository error:(NSError * _Nullable * _Nullable)error;
- (void)setRepository:(id)repository;
- (void)unregisterLenses;

@end


NS_ASSUME_NONNULL_END
