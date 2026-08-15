#import "SCSDKCameraKitCompositeLensRuntime.h"

@protocol AGCameraKitCompositeLensApplying <NSObject>

- (void)applyLenses:(NSArray *)lenses
         launchData:(NSArray *)launchData
         completion:(void (^)(BOOL success))completion;

@end

static SEL AGCompositeApplySelector(void)
{
    return NSSelectorFromString(@"applyLenses:launchData:completion:");
}

BOOL SCCameraKitProcessorSupportsCompositeLenses(id processor)
{
    return processor != nil && [processor respondsToSelector:AGCompositeApplySelector()];
}

void SCCameraKitApplyCompositeLenses(
    id processor,
    NSArray *lenses,
    NSArray *launchData,
    void (^completion)(BOOL success)
)
{
    if (!SCCameraKitProcessorSupportsCompositeLenses(processor) || lenses.count != launchData.count) {
        completion(NO);
        return;
    }

    [(id<AGCameraKitCompositeLensApplying>)processor
        applyLenses:lenses
        launchData:launchData
        completion:completion];
}
