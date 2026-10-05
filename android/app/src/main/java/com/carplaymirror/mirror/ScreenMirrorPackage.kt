package com.carplaymirror.mirror

import com.carplaymirror.NativeScreenMirrorSpec
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class ScreenMirrorPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
    if (name == NativeScreenMirrorSpec.NAME) ScreenMirrorModule(reactContext) else null

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
    mapOf(
      NativeScreenMirrorSpec.NAME to
        ReactModuleInfo(
          name = NativeScreenMirrorSpec.NAME,
          className = NativeScreenMirrorSpec.NAME,
          canOverrideExistingModule = false,
          needsEagerInit = false,
          isCxxModule = false,
          isTurboModule = true,
        )
    )
  }
}
