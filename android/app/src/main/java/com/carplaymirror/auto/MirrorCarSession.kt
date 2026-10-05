package com.carplaymirror.auto

import android.content.Intent
import android.graphics.Rect
import androidx.car.app.AppManager
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.carplaymirror.mirror.MirrorEngine

/** Sessão do Android Auto: entrega a superfície da tela do carro ao MirrorEngine. */
class MirrorCarSession : Session() {
  private val surfaceCallback =
    object : SurfaceCallback {
      override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        val surface = surfaceContainer.surface ?: return
        MirrorEngine.onCarSurfaceAvailable(
          surface,
          surfaceContainer.width,
          surfaceContainer.height,
          surfaceContainer.dpi,
        )
      }

      override fun onVisibleAreaChanged(visibleArea: Rect) = Unit

      override fun onStableAreaChanged(stableArea: Rect) = Unit

      override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        MirrorEngine.onCarSurfaceDestroyed()
      }
    }

  override fun onCreateScreen(intent: Intent): Screen {
    lifecycle.addObserver(
      object : DefaultLifecycleObserver {
        override fun onCreate(owner: LifecycleOwner) {
          MirrorEngine.onCarConnected()
          carContext.getCarService(AppManager::class.java).setSurfaceCallback(surfaceCallback)
        }

        override fun onDestroy(owner: LifecycleOwner) {
          MirrorEngine.onCarDisconnected()
        }
      }
    )
    return MirrorScreen(carContext)
  }
}
