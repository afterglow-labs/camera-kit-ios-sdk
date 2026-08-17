#import "SCSDKCameraKitCompositeLensRuntime.h"
#import <objc/runtime.h>

@protocol AGCameraKitCompositeLensApplying <NSObject>

- (void)applyLenses:(NSArray *)lenses
         launchData:(NSArray *)launchData
         completion:(void (^)(BOOL success))completion;

@end

@protocol AGCameraKitComponentManagerProviding <NSObject>

- (id)videoProcessingComponent;

@end

@protocol AGCameraKitHighDefinitionRendering <NSObject>

- (void)setYuvRenderingResolutionWidth:(NSInteger)width height:(NSInteger)height;

@end

static SEL AGCompositeApplySelector(void)
{
    return NSSelectorFromString(@"applyLenses:launchData:completion:");
}

static id AGCameraKitVideoProcessingComponent(id processor)
{
    if (processor == nil) {
        return nil;
    }

    Ivar componentManagerIvar = class_getInstanceVariable([processor class], "_componentManager");
    if (componentManagerIvar == NULL) {
        return nil;
    }

    id componentManager = object_getIvar(processor, componentManagerIvar);
    SEL componentSelector = NSSelectorFromString(@"videoProcessingComponent");
    if (![componentManager respondsToSelector:componentSelector]) {
        return nil;
    }

    return [(id<AGCameraKitComponentManagerProviding>)componentManager videoProcessingComponent];
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

BOOL SCCameraKitProcessorSupportsHighDefinitionRendering(id processor)
{
    id videoProcessor = AGCameraKitVideoProcessingComponent(processor);
    return [videoProcessor respondsToSelector:NSSelectorFromString(@"setYuvRenderingResolutionWidth:height:")];
}

BOOL SCCameraKitSetHighDefinitionRenderingResolution(
    id processor,
    NSInteger width,
    NSInteger height
)
{
    BOOL clearsOverride = width == 0 && height == 0;
    if (!clearsOverride && (width <= 0 || height <= 0)) {
        return NO;
    }

    id videoProcessor = AGCameraKitVideoProcessingComponent(processor);
    if (![videoProcessor respondsToSelector:NSSelectorFromString(@"setYuvRenderingResolutionWidth:height:")]) {
        return NO;
    }

    [(id<AGCameraKitHighDefinitionRendering>)videoProcessor
        setYuvRenderingResolutionWidth:width
        height:height];
    return YES;
}
