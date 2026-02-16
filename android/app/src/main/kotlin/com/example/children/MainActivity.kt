package com.example.children

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // ── Channel 1: Background service channel (must match background_service.dart) ──
            val serviceChannel = NotificationChannel(
                "sharogai_monitor_01",          // <-- matches notificationChannelId in Dart
                "ShaRogai Monitor",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "ShaRogai background monitoring service"
                enableVibration(false)
                setSound(null, null)
            }
            notificationManager.createNotificationChannel(serviceChannel)

            // ── Channel 2: Alerts channel (for flutter_local_notifications) ──
            val alertsChannel = NotificationChannel(
                "sharogai_alerts",
                "ShaRogai Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Motion alerts and Brain notifications"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(alertsChannel)
        }
    }
}
