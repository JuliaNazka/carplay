package com.carplaymirror.car

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.carplaymirror.R
import com.carplaymirror.mirror.MirrorEngine
import com.carplaymirror.mirror.MirrorProjectionService

/**
 * Tela do app no carro. É uma Activity comum marcada com a categoria CAR_LAUNCHER: o Android
 * Auto (Android 15+) a abre na tela do carro como "app para carro parado". A imagem do celular
 * é desenhada no SurfaceView pelo VirtualDisplay da captura (veja MirrorEngine).
 */
class MirrorCarActivity : Activity() {
  private lateinit var surfaceView: SurfaceView
  private lateinit var waitingPanel: LinearLayout
  private lateinit var stopButton: Button
  private var onCarDisplay = false
  private val onMirrorChanged: () -> Unit = { updateOverlay() }

  private val surfaceCallback =
    object : SurfaceHolder.Callback {
      override fun surfaceCreated(holder: SurfaceHolder) = Unit

      override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        MirrorEngine.onCarSurfaceAvailable(holder.surface, width, height, resources.displayMetrics.densityDpi)
      }

      override fun surfaceDestroyed(holder: SurfaceHolder) {
        MirrorEngine.onCarSurfaceDestroyed()
      }
    }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(buildLayout())

    // Nunca espelhar o celular nele mesmo: esta tela só funciona no display do carro.
    onCarDisplay = currentDisplayId() != Display.DEFAULT_DISPLAY
    if (!onCarDisplay) {
      waitingPanel.findViewById<TextView>(R.id.car_mirror_text).setText(R.string.car_open_from_auto)
      waitingPanel.visibility = View.VISIBLE
      stopButton.visibility = View.GONE
      return
    }

    surfaceView.holder.addCallback(surfaceCallback)
    MirrorEngine.addListener(onMirrorChanged)
    MirrorEngine.onCarConnected()
    updateOverlay()
  }

  override fun onDestroy() {
    if (onCarDisplay) {
      MirrorEngine.removeListener(onMirrorChanged)
      surfaceView.holder.removeCallback(surfaceCallback)
      MirrorEngine.onCarDisconnected()
    }
    super.onDestroy()
  }

  private fun updateOverlay() {
    val mirroring = MirrorEngine.isMirroring
    waitingPanel.visibility = if (mirroring) View.GONE else View.VISIBLE
    stopButton.visibility = if (mirroring) View.VISIBLE else View.GONE
  }

  private fun currentDisplayId(): Int =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      display?.displayId ?: Display.DEFAULT_DISPLAY
    } else {
      @Suppress("DEPRECATION") windowManager.defaultDisplay.displayId
    }

  private fun buildLayout(): FrameLayout {
    val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }

    surfaceView = SurfaceView(this)
    root.addView(surfaceView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

    // Aviso exibido enquanto o espelhamento não começa.
    waitingPanel =
      LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setBackgroundColor(Color.BLACK)
        val padding = dp(32)
        setPadding(padding, padding, padding, padding)
        addView(
          TextView(context).apply {
            setText(R.string.car_waiting_title)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            gravity = Gravity.CENTER
          }
        )
        addView(
          TextView(context).apply {
            id = R.id.car_mirror_text
            setText(R.string.car_waiting_text)
            setTextColor(Color.argb(190, 255, 255, 255))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
          }
        )
      }
    root.addView(waitingPanel, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

    stopButton =
      Button(this).apply {
        setText(R.string.car_stop)
        setOnClickListener { startService(MirrorProjectionService.stopIntent(this@MirrorCarActivity)) }
      }
    root.addView(
      stopButton,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END)
        .apply { setMargins(dp(12), dp(12), dp(12), dp(12)) },
    )
    return root
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
