package com.carplaymirror.auto

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.carplaymirror.R
import com.carplaymirror.mirror.MirrorEngine
import com.carplaymirror.mirror.MirrorProjectionService

/**
 * Tela do app no Android Auto. A imagem do celular é desenhada na superfície (embaixo do
 * template); o template só mostra um aviso enquanto o espelhamento não começa e o botão Parar.
 */
class MirrorScreen(carContext: CarContext) : Screen(carContext) {
  private val onMirrorChanged: () -> Unit = { invalidate() }

  init {
    lifecycle.addObserver(
      object : DefaultLifecycleObserver {
        override fun onCreate(owner: LifecycleOwner) {
          MirrorEngine.addListener(onMirrorChanged)
        }

        override fun onDestroy(owner: LifecycleOwner) {
          MirrorEngine.removeListener(onMirrorChanged)
        }
      }
    )
  }

  override fun onGetTemplate(): Template {
    val mirroring = MirrorEngine.isMirroring
    val action =
      if (mirroring) {
        Action.Builder()
          .setTitle(carContext.getString(R.string.auto_stop))
          .setOnClickListener {
            carContext.startService(MirrorProjectionService.stopIntent(carContext))
          }
          .build()
      } else {
        Action.Builder()
          .setTitle(carContext.getString(R.string.auto_help))
          .setOnClickListener {
            CarToast.makeText(carContext, R.string.auto_waiting_text, CarToast.LENGTH_LONG).show()
          }
          .build()
      }

    val builder = NavigationTemplate.Builder().setActionStrip(ActionStrip.Builder().addAction(action).build())
    if (!mirroring) {
      builder.setNavigationInfo(
        MessageInfo.Builder(carContext.getString(R.string.auto_waiting_title))
          .setText(carContext.getString(R.string.auto_waiting_text))
          .build()
      )
    }
    return builder.build()
  }
}
