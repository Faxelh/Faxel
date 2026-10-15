package com.faxel.app.engine

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.faxel.app.MainActivity
import com.faxel.app.R

/** Garde les imports actifs quand l'app passe en arrière-plan (notification de progression). */
class DownloadService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var idleTicks = 0

    private val tick = object : Runnable {
        override fun run() {
            if (!Engine.active) {
                idleTicks++
                if (idleTicks > 3) {
                    ServiceCompat.stopForeground(this@DownloadService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return
                }
            } else {
                idleTicks = 0
            }
            NotificationManagerCompat.from(this@DownloadService).let { manager ->
                if (canNotify(this@DownloadService)) manager.notify(ID, build())
            }
            handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        channels(this)
        val type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        runCatching { ServiceCompat.startForeground(this, ID, build(), type) }
            .onFailure { stopSelf(); return START_NOT_STICKY }
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun build(): Notification {
        val running = Engine.jobs.filter { it.active }
        val current = running.firstOrNull()
        val title = if (running.size > 1) getString(R.string.notif_many, running.size)
        else current?.title ?: getString(R.string.notif_working)
        val progress = ((current?.fraction ?: 0.0) * 100).toInt().coerceIn(0, 100)
        return NotificationCompat.Builder(this, CHANNEL_PROGRESS)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(current?.label ?: "")
            .setProgress(100, progress, current == null || progress == 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openApp(this))
            .build()
    }

    companion object {
        private const val ID = 41
        private const val CHANNEL_PROGRESS = "progress"
        private const val CHANNEL_DONE = "done"
        private var doneId = 100

        fun channels(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_PROGRESS, context.getString(R.string.notif_channel_progress), NotificationManager.IMPORTANCE_LOW),
            )
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_DONE, context.getString(R.string.notif_channel_done), NotificationManager.IMPORTANCE_DEFAULT),
            )
        }

        private fun canNotify(context: Context) = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /** Notification « Téléchargé » (seulement si l'app n'est pas à l'écran). */
        fun finished(context: Context, title: String) {
            if (MainActivity.visible || !canNotify(context)) return
            channels(context)
            val notification = NotificationCompat.Builder(context, CHANNEL_DONE)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(context.getString(R.string.notif_done))
                .setContentText(title)
                .setAutoCancel(true)
                .setContentIntent(openApp(context))
                .build()
            runCatching { NotificationManagerCompat.from(context).notify(doneId++, notification) }
        }
    }
}
