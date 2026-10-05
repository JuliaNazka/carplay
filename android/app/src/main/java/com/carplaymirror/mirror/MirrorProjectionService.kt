package com.carplaymirror.mirror

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.carplaymirror.R

/**
 * Serviço em primeiro plano exigido pelo Android para capturar a tela (tipo mediaProjection).
 * Ele recebe o resultado do diálogo de permissão e mantém o espelhamento vivo enquanto
 * você usa outros apps.
 */
class MirrorProjectionService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        startInForeground()
        // Um novo início substitui a captura anterior sem derrubar o serviço.
        MirrorEngine.removeListener(stopWhenProjectionEnds)
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val data = permissionData(intent)
        if (data == null || !MirrorEngine.startProjection(this, resultCode, data)) {
          stopSelf()
        } else {
          MirrorEngine.addListener(stopWhenProjectionEnds)
        }
      }
      ACTION_STOP -> {
        MirrorEngine.stopProjection()
        stopSelf()
      }
      else -> stopSelf()
    }
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    MirrorEngine.removeListener(stopWhenProjectionEnds)
    MirrorEngine.stopProjection()
    super.onDestroy()
  }

  private val stopWhenProjectionEnds: () -> Unit = {
    if (!MirrorEngine.isMirroring) stopSelf()
  }

  private fun startInForeground() {
    val manager = getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel =
        NotificationChannel(CHANNEL_ID, getString(R.string.mirror_channel_name), NotificationManager.IMPORTANCE_LOW)
      manager.createNotificationChannel(channel)
    }

    val stopIntent =
      PendingIntent.getService(
        this,
        0,
        Intent(this, MirrorProjectionService::class.java).setAction(ACTION_STOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
      )

    @Suppress("DEPRECATION")
    val builder =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID)
      else Notification.Builder(this)
    val notification =
      builder
        .setSmallIcon(R.drawable.ic_stat_mirror)
        .setContentTitle(getString(R.string.mirror_notification_title))
        .setContentText(getString(R.string.mirror_notification_text))
        .setOngoing(true)
        .addAction(
          Notification.Action.Builder(null, getString(R.string.mirror_notification_stop), stopIntent).build()
        )
        .build()

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }
  }

  companion object {
    const val ACTION_START = "com.carplaymirror.action.START"
    const val ACTION_STOP = "com.carplaymirror.action.STOP"
    const val EXTRA_RESULT_CODE = "resultCode"
    const val EXTRA_DATA = "data"
    private const val CHANNEL_ID = "mirror"
    private const val NOTIFICATION_ID = 1

    fun startIntent(context: Context, resultCode: Int, data: Intent): Intent =
      Intent(context, MirrorProjectionService::class.java)
        .setAction(ACTION_START)
        .putExtra(EXTRA_RESULT_CODE, resultCode)
        .putExtra(EXTRA_DATA, data)

    fun stopIntent(context: Context): Intent =
      Intent(context, MirrorProjectionService::class.java).setAction(ACTION_STOP)

    private fun permissionData(intent: Intent): Intent? =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
      } else {
        @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
      }
  }
}
