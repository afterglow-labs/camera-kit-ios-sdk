#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL SCCameraKitProcessorSupportsCompositeLenses(id _Nullable processor);

FOUNDATION_EXPORT void SCCameraKitApplyCompositeLenses(
    id _Nullable processor,
    NSArray *lenses,
    NSArray *launchData,
    void (^completion)(BOOL success)
);

NS_ASSUME_NONNULL_END
