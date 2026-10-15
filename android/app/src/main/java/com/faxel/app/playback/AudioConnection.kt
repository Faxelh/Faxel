package com.faxel.app.playback

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.faxel.app.data.Entry
import com.faxel.app.engine.Engine
import com.google.common.util.concurrent.ListenableFuture
import java.io.File

/** Lien entre l'interface et le lecteur de musique (service en arrière-plan). */
object AudioConnection {
    private var future: ListenableFuture<MediaController>? = null
    private lateinit var appContext: Context

    var controller by mutableStateOf<MediaController?>(null)
        private set
    var currentPath by mutableStateOf<String?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var queue by mutableStateOf<List<String>>(emptyList())
        private set
    var index by mutableStateOf(0)
        private set
    var shuffle by mutableStateOf(false)
        private set
    var repeatMode by mutableStateOf(Player.REPEAT_MODE_OFF)
        private set
    var speed by mutableStateOf(1f)
        private set

    private val titles = HashMap<String, Entry>()

    var sleepEnd by mutableStateOf<Long?>(null)
        private set
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private val sleepRunnable = Runnable {
        pause()
        sleepEnd = null
    }
    private var fadeToken = 0

    /** Fondu doux du volume (pause et reprise sans coupure sèche). */
    private fun fade(from: Float, to: Float, durationMs: Long = 220, done: () -> Unit = {}) {
        val c = controller ?: return done()
        val token = ++fadeToken
        val steps = 10
        c.volume = from
        for (i in 1..steps) {
            main.postDelayed({
                if (token != fadeToken) return@postDelayed
                controller?.volume = from + (to - from) * i / steps
                if (i == steps) done()
            }, durationMs * i / steps)
        }
    }

    private fun cancelFade() {
        fadeToken++
        controller?.volume = 1f
    }

    /** Minuterie de sommeil (minutes ; 0 = désactivée). */
    fun setSleepTimer(minutes: Int) {
        main.removeCallbacks(sleepRunnable)
        if (minutes <= 0) {
            sleepEnd = null
            return
        }
        sleepEnd = System.currentTimeMillis() + minutes * 60_000L
        main.postDelayed(sleepRunnable, minutes * 60_000L)
    }

    val current: Entry? get() = currentPath?.let { Engine.entry(it) ?: titles[it] }

    fun connect(context: Context) {
        appContext = context.applicationContext
        if (future != null) return
        val token = SessionToken(appContext, ComponentName(appContext, AudioService::class.java))
        val pending = MediaController.Builder(appContext, token).buildAsync()
        future = pending
        pending.addListener({
            val ready = runCatching { pending.get() }.getOrNull() ?: return@addListener
            controller = ready
            ready.addListener(object : Player.Listener {
                override fun onEvents(player: Player, events: Player.Events) = sync()
            })
            sync()
        }, ContextCompat.getMainExecutor(appContext))
    }

    private fun sync() {
        val c = controller ?: return
        isPlaying = c.isPlaying
        currentPath = c.currentMediaItem?.mediaId
        index = c.currentMediaItemIndex
        shuffle = c.shuffleModeEnabled
        repeatMode = c.repeatMode
        speed = c.playbackParameters.speed
        val ids = (0 until c.mediaItemCount).map { c.getMediaItemAt(it).mediaId }
        if (ids != queue) queue = ids
    }

    private fun item(entry: Entry): MediaItem {
        titles[entry.path] = entry
        val metadata = MediaMetadata.Builder()
            .setTitle(entry.title)
            .setArtist(entry.uploader.ifBlank { entry.platformName })
        entry.thumbnail?.let { metadata.setArtworkUri(Uri.parse(it)) }
        return MediaItem.Builder()
            .setMediaId(entry.path)
            .setUri(Uri.fromFile(File(entry.path)))
            .setMediaMetadata(metadata.build())
            .build()
    }

    fun play(entries: List<Entry>, start: Int = 0, shuffled: Boolean = false) {
        val c = controller ?: return
        if (entries.isEmpty()) return
        VideoState.pause()
        cancelFade()
        c.shuffleModeEnabled = shuffled
        c.setMediaItems(entries.map { item(it) }, if (shuffled) entries.indices.random() else start.coerceIn(entries.indices), 0L)
        c.prepare()
        c.play()
    }

    fun toggle() {
        val c = controller ?: return
        if (c.isPlaying) {
            // Fondu puis pause ; le volume revient à 100 % pour la prochaine lecture.
            fade(c.volume, 0f) {
                controller?.pause()
                controller?.volume = 1f
            }
        } else {
            VideoState.pause()
            if (c.playbackState == Player.STATE_IDLE) c.prepare()
            if (c.playbackState == Player.STATE_ENDED) c.seekTo(0)
            c.volume = 0f
            c.play()
            fade(0f, 1f, 260)
        }
    }

    fun pause() {
        cancelFade()
        controller?.pause()
    }
    fun next() = controller?.seekToNext()
    fun previous() = controller?.seekToPrevious()
    fun seek(ms: Long) = controller?.seekTo(ms)
    fun jump(to: Int) {
        controller?.seekTo(to, 0L)
        controller?.play()
    }

    fun toggleShuffle() {
        controller?.let { it.shuffleModeEnabled = !it.shuffleModeEnabled }
    }

    fun cycleRepeat() {
        val c = controller ?: return
        c.repeatMode = when (c.repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
    }

    @JvmName("changeSpeed")
    fun setSpeed(value: Float) {
        controller?.playbackParameters = PlaybackParameters(value)
    }

    fun playNext(entry: Entry) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) return play(listOf(entry))
        c.addMediaItem((c.currentMediaItemIndex + 1).coerceAtMost(c.mediaItemCount), item(entry))
    }

    fun addToQueue(entries: List<Entry>) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) return play(entries)
        c.addMediaItems(entries.map { item(it) })
    }

    fun removeAt(position: Int) {
        val c = controller ?: return
        if (position != c.currentMediaItemIndex && position in 0 until c.mediaItemCount) c.removeMediaItem(position)
    }

    fun stop() {
        controller?.stop()
        controller?.clearMediaItems()
    }
}
