package app.deliveria.deliveria

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class OrderAlertService : Service() {
    private val running = AtomicBoolean(false)
    private var socket: WebSocket? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutdown()
            return START_NOT_STICKY
        }
        ensureChannels()
        try {
            startForeground(ONGOING_ID, ongoing())
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (running.compareAndSet(false, true)) {
            Thread({ loop() }, "deliveria-alerts").start()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }

    private fun shutdown() {
        running.set(false)
        socket?.close(1000, "stop")
        socket = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun loop() {
        val client = OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).build()
        while (running.get()) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val token = prefs.getString("flutter.alert_access", null)
            val base = prefs.getString("flutter.alert_base", null)
            val url = socketUrl(base, token)
            if (url == null) break
            val closed = CountDownLatch(1)
            val request = Request.Builder().url(url).build()
            socket = client.newWebSocket(request, object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    showIfOrder(text)
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    closed.countDown()
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    closed.countDown()
                }
            })
            closed.await(25, TimeUnit.MINUTES)
            socket?.close(1000, null)
            if (running.get()) Thread.sleep(4000)
        }
        running.set(false)
    }

    private fun showIfOrder(text: String) {
        val json = runCatching { JSONObject(text) }.getOrNull() ?: return
        if (json.optString("type") != "notification") return
        val notice = json.optJSONObject("notification") ?: return
        val title = notice.optString("title").ifBlank { "دليفريه" }
        val body = notice.optString("body").ifBlank { "فيه تحديث على طلب." }
        alert(title, body)
    }

    private fun alert(title: String, body: String) {
        ensureChannels()
        val tap = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarm = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setSound(alarm)
            .setContentIntent(tap)
            .build()
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }

    private fun ongoing(): Notification {
        return NotificationCompat.Builder(this, ONGOING_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("دليفريه")
            .setContentText("تنبيهات الطلبات شغالة")
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(ALERT_CHANNEL) == null) {
            val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audio = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(ALERT_CHANNEL, "طلبات دليفريه", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "تنبيه عند طلب جديد أو قبول أو استلام أو تسليم"
                enableVibration(true)
                setSound(sound, audio)
            }
            manager.createNotificationChannel(channel)
        }
        if (manager.getNotificationChannel(ONGOING_CHANNEL) == null) {
            val channel = NotificationChannel(ONGOING_CHANNEL, "اتصال دليفريه", NotificationManager.IMPORTANCE_MIN)
            manager.createNotificationChannel(channel)
        }
    }

    private fun socketUrl(base: String?, token: String?): String? {
        if (base.isNullOrBlank() || token.isNullOrBlank()) return null
        val ws = if (base.startsWith("https://")) "wss://${base.removePrefix("https://")}" else "ws://${base.removePrefix("http://")}"
        return "$ws/v1/realtime?token=${URLEncoder.encode(token, "UTF-8")}"
    }

    companion object {
        const val ACTION_STOP = "app.deliveria.deliveria.STOP_ALERTS"
        private const val ALERT_CHANNEL = "deliveria_orders_alarm_v1"
        private const val ONGOING_CHANNEL = "deliveria_connection"
        private const val ONGOING_ID = 7101
    }
}
