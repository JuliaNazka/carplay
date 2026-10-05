package com.carplaymirror.mirror

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.carplaymirror.NativeScreenMirrorSpec
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext

/**
 * Implementação Android do módulo "ScreenMirror" (mesma especificação do iOS em
 * specs/NativeScreenMirror.ts). FPS/qualidade/modo demonstração não se aplicam aqui: a
 * imagem vai direto da GPU para a tela do carro.
 */
class ScreenMirrorModule(reactContext: ReactApplicationContext) :
  NativeScreenMirrorSpec(reactContext), ActivityEventListener {

  private val mainHandler = Handler(Looper.getMainLooper())
  private var fillMode = "fit"

  init {
    reactContext.addActivityEventListener(this)
  }

  override fun invalidate() {
    reactApplicationContext.removeActivityEventListener(this)
    super.invalidate()
  }

  override fun getStatus(promise: Promise) {
    mainHandler.post {
      val status = MirrorEngine.status()
      val map =
        Arguments.createMap().apply {
          putBoolean("carPlayConnected", status.carConnected)
          putBoolean("broadcasting", status.mirroring)
          putBoolean("demoMode", false)
          putInt("fps", 0)
          putInt("frameWidth", status.width)
          putInt("frameHeight", status.height)
          putInt("framesReceived", 0)
          putInt("lastFrameAgeMs", -1)
          putInt("maxFps", 60)
          putDouble("jpegQuality", 1.0)
          putInt("maxDimension", 0)
          putString("fillMode", fillMode)
          putString("error", status.error)
        }
      promise.resolve(map)
    }
  }

  /** Abre o diálogo do sistema para permitir a captura da tela. */
  override fun showBroadcastPicker() {
    mainHandler.post {
      val activity = reactApplicationContext.currentActivity ?: return@post
      val manager = activity.getSystemService(MediaProjectionManager::class.java) ?: return@post
      val intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
          // Tela inteira (e não um app só): é o celular todo que vai para o carro.
          manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
          manager.createScreenCaptureIntent()
        }
      activity.startActivityForResult(intent, REQUEST_CAPTURE)
    }
  }

  override fun stopBroadcast() {
    mainHandler.post {
      val context = reactApplicationContext
      context.startService(MirrorProjectionService.stopIntent(context))
    }
  }

  override fun setSettings(maxFps: Double, jpegQuality: Double, maxDimension: Double, fillMode: String) {
    this.fillMode = fillMode
  }

  override fun setDemoMode(enabled: Boolean) = Unit

  override fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode != REQUEST_CAPTURE) return
    if (resultCode != Activity.RESULT_OK || data == null) {
      MirrorEngine.reportError("Permissão para capturar a tela não concedida.")
      return
    }
    val intent = MirrorProjectionService.startIntent(activity, resultCode, data)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      activity.startForegroundService(intent)
    } else {
      activity.startService(intent)
    }
  }

  override fun onNewIntent(intent: Intent) = Unit

  private companion object {
    const val REQUEST_CAPTURE = 47210
  }
}
