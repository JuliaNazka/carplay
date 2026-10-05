package com.carplaymirror.auto

import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/** Ponto de entrada do Android Auto (categoria navegação, que dá acesso à superfície da tela). */
class MirrorCarAppService : CarAppService() {
  override fun createHostValidator(): HostValidator =
    if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
      HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    } else {
      // Só aceita o Android Auto oficial (e o Desktop Head Unit) como host.
      HostValidator.Builder(applicationContext)
        .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
        .build()
    }

  override fun onCreateSession(): Session = MirrorCarSession()
}
