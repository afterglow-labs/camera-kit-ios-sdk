#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL SCCameraKitProcessorSupportsCompositeLenses(id _Nullable processor);

FOUNDATION_EXPORT void SCCameraKitApplyCompositeLenses(
    id _Nullable processor,
    NSArray *lenses,
    NSArray *launchData,
    void (^completion)(BOOL success)
);

/// Returns whether this Camera Kit Lens processor exposes Snapchat's HD YUV-rendering path.
FOUNDATION_EXPORT BOOL SCCameraKitProcessorSupportsHighDefinitionRendering(id _Nullable processor);

/// Sets the Lens processor's internal YUV rendering size. Pass 0 x 0 to restore its automatic size.
FOUNDATION_EXPORT BOOL SCCameraKitSetHighDefinitionRenderingResolution(
    id _Nullable processor,
    NSInteger width,
    NSInteger height
);

NS_ASSUME_NONNULL_END
