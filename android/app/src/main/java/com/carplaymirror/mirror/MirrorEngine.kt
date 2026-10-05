package com.carplaymirror.mirror

import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Estado central do espelhamento no Android (use somente na main thread).
 *
 * A tela do celular é capturada com MediaProjection e espelhada num VirtualDisplay cujo
 * destino é a própria superfície do Android Auto: a GPU desenha direto na tela do carro,
 * sem codificar nem copiar quadros.
 */
object MirrorEngine {
  private const val TAG = "MirrorEngine"

  data class Status(
    val carConnected: Boolean,
    val mirroring: Boolean,
    val width: Int,
    val height: Int,
    val error: String,
  )

  private data class CarSurface(val surface: Surface, val width: Int, val height: Int, val dpi: Int)

  private val mainHandler = Handler(Looper.getMainLooper())
  private val listeners = CopyOnWriteArraySet<() -> Unit>()

  private var projection: MediaProjection? = null
  private var virtualDisplay: VirtualDisplay? = null
  private var carSurface: CarSurface? = null
  private var carConnected = false
  private var lastError = ""

  val isMirroring: Boolean
    get() = projection != null

  fun status(): Status {
    val target = carSurface
    return Status(
      carConnected = carConnected,
      mirroring = isMirroring,
      width = if (isMirroring && target != null) target.width else 0,
      height = if (isMirroring && target != null) target.height else 0,
      error = lastError,
    )
  }

  /** Avisa quando o espelhamento liga/desliga (a tela do Android Auto se atualiza). */
  fun addListener(listener: () -> Unit) {
    listeners.add(listener)
  }

  fun removeListener(listener: () -> Unit) {
    listeners.remove(listener)
  }

  fun reportError(message: String) {
    lastError = message
  }

  // MARK: - Captura (MediaProjection)

  /**
   * Inicia a captura com o resultado do diálogo de permissão. Precisa ser chamado pelo
   * serviço em primeiro plano, depois de `startForeground` (exigência do Android 14+).
   */
  fun startProjection(context: Context, resultCode: Int, data: Intent): Boolean {
    stopProjection()
    val manager = context.getSystemService(MediaProjectionManager::class.java)
    val newProjection =
      try {
        manager.getMediaProjection(resultCode, data)
      } catch (e: Exception) {
        Log.e(TAG, "getMediaProjection falhou", e)
        null
      }
    if (newProjection == null) {
      lastError = "Não foi possível iniciar a captura da tela."
      return false
    }

    // O callback precisa ser registrado antes de criar o VirtualDisplay (Android 14+).
    newProjection.registerCallback(
      object : MediaProjection.Callback() {
        override fun onStop() {
          mainHandler.post { handleProjectionStopped(newProjection) }
        }
      },
      mainHandler,
    )
    projection = newProjection

    // A partir do Android 14, cada permissão só permite criar UM VirtualDisplay: ele é criado
    // agora (mesmo sem carro conectado) e depois só tem a superfície trocada.
    val target = carSurface
    virtualDisplay =
      try {
        newProjection.createVirtualDisplay(
          "CarMirror",
          target?.width ?: 1280,
          target?.height ?: 720,
          target?.dpi ?: 160,
          DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
          target?.surface,
          null,
          mainHandler,
        )
      } catch (e: Exception) {
        Log.e(TAG, "createVirtualDisplay falhou", e)
        null
      }
    if (virtualDisplay == null) {
      lastError = "Não foi possível espelhar a tela."
      newProjection.stop()
      return false
    }

    lastError = ""
    notifyListeners()
    return true
  }

  fun stopProjection() {
    projection?.stop() // dispara onStop -> handleProjectionStopped
    projection?.let { handleProjectionStopped(it) }
  }

  private fun handleProjectionStopped(stopped: MediaProjection) {
    if (projection !== stopped) return
    virtualDisplay?.release()
    virtualDisplay = null
    projection = null
    notifyListeners()
  }

  // MARK: - Android Auto

  fun onCarConnected() {
    carConnected = true
    notifyListeners()
  }

  fun onCarDisconnected() {
    carConnected = false
    onCarSurfaceDestroyed()
    notifyListeners()
  }

  fun onCarSurfaceAvailable(surface: Surface, width: Int, height: Int, dpi: Int) {
    carSurface = CarSurface(surface, width, height, dpi)
    virtualDisplay?.let {
      it.resize(width, height, dpi)
      it.surface = surface
    }
  }

  fun onCarSurfaceDestroyed() {
    carSurface = null
    virtualDisplay?.surface = null
  }

  private fun notifyListeners() {
    listeners.forEach { it() }
  }
}
