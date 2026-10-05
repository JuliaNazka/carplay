// Módulo nativo (TurboModule) "ScreenMirror" usado pela interface em React Native.
// A especificação fica em specs/NativeScreenMirror.ts; o codegen gera o protocolo
// NativeScreenMirrorSpec durante o `pod install`.

#import <UIKit/UIKit.h>

#import <AppSpecs/AppSpecs.h>

#import "CarPlayMirror-Swift.h"

@interface RCTScreenMirror : NSObject <NativeScreenMirrorSpec>
@end

@implementation RCTScreenMirror

+ (NSString *)moduleName
{
  return @"ScreenMirror";
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeScreenMirrorSpecJSI>(params);
}

- (void)getStatus:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  dispatch_async(dispatch_get_main_queue(), ^{
    resolve([MirrorSession.shared statusDictionary]);
  });
}

- (void)showBroadcastPicker
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [MirrorSession.shared showBroadcastPicker];
  });
}

- (void)stopBroadcast
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [MirrorSession.shared stopBroadcast];
  });
}

- (void)setSettings:(double)maxFps
        jpegQuality:(double)jpegQuality
       maxDimension:(double)maxDimension
           fillMode:(NSString *)fillMode
{
  if (!isfinite(maxFps) || !isfinite(jpegQuality) || !isfinite(maxDimension)) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [MirrorSession.shared updateSettingsWithMaxFPS:(NSInteger)maxFps
                                       jpegQuality:jpegQuality
                                      maxDimension:(NSInteger)maxDimension
                                          fillMode:fillMode];
  });
}

- (void)setDemoMode:(BOOL)enabled
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [MirrorSession.shared setDemoModeEnabled:enabled];
  });
}

@end
