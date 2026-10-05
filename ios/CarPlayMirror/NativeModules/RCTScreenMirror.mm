// Módulo nativo (TurboModule) "ScreenMirror" usado pela interface em React Native.
// A especificação fica em specs/NativeScreenMirror.ts; o codegen gera o protocolo
// NativeScreenMirrorSpec durante o `pod install`.

#import <Foundation/Foundation.h>

#import <AppSpecs/AppSpecs.h>

// Métodos de MirrorSession (Swift, @objc(MirrorSession)). Declarados aqui em vez de importar
// CarPlayMirror-Swift.h, que também expõe classes que dependem dos headers do CarPlay e do React.
@protocol CPMMirrorSession <NSObject>
+ (id<CPMMirrorSession>)shared;
- (NSDictionary<NSString *, id> *)statusDictionary;
- (void)showBroadcastPicker;
- (void)stopBroadcast;
- (void)updateSettingsWithMaxFPS:(NSInteger)maxFPS
                     jpegQuality:(double)jpegQuality
                    maxDimension:(NSInteger)maxDimension
                        fillMode:(NSString *)fillMode;
- (void)setDemoModeEnabled:(BOOL)enabled;
@end

static id<CPMMirrorSession> MirrorSessionShared(void)
{
  Class<CPMMirrorSession> sessionClass = (Class<CPMMirrorSession>)NSClassFromString(@"MirrorSession");
  return [sessionClass shared];
}

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
    resolve([MirrorSessionShared() statusDictionary]);
  });
}

- (void)showBroadcastPicker
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [MirrorSessionShared() showBroadcastPicker];
  });
}

- (void)stopBroadcast
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [MirrorSessionShared() stopBroadcast];
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
    [MirrorSessionShared() updateSettingsWithMaxFPS:(NSInteger)maxFps
                                       jpegQuality:jpegQuality
                                      maxDimension:(NSInteger)maxDimension
                                          fillMode:fillMode];
  });
}

- (void)setDemoMode:(BOOL)enabled
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [MirrorSessionShared() setDemoModeEnabled:enabled];
  });
}

@end
