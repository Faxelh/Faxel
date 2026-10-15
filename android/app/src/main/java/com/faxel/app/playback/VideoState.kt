package com.faxel.app.playback

import android.content.Context
import android.net.Uri
import android.util.Rational
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import com.faxel.app.data.Prefs
import com.faxel.app.data.Subtitles
import java.io.File
import java.util.Locale

/** Lecteur vidéo (plein écran, image dans l'image, sous-titres automatiques, reprise). */
object VideoState {
    var player: ExoPlayer? = null
        private set
    var open by mutableStateOf(false)
        private set
    var title by mutableStateOf("")
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var inPip by mutableStateOf(false)
    var aspect by mutableStateOf(Rational(16, 9))
        private set

    /** Fichiers de la liste en cours (pour « épisode suivant », filigrane…). */
    var files by mutableStateOf<List<File>>(emptyList())
        private set
    var index by mutableStateOf(0)
        private set
    var speed by mutableStateOf(1f)
        private set
    var repeatOne by mutableStateOf(false)
        private set
    /** « Épisode suivant » annulé pour cette vidéo. */
    var cancelAutoNext by mutableStateOf(false)
        private set
    var sleepEnd by mutableStateOf<Long?>(null)
        private set
    var sleepAtEnd by mutableStateOf(false)
        private set
    /** Appui long : ×2 tant que le doigt reste posé. */
    var boosted by mutableStateOf(false)
        private set
    /** 0 = image entière, 1 = remplir l'écran, 2 = étirer. */
    var resize by mutableStateOf(0)
    /** Pistes de sous-titres et audio de la vidéo en cours. */
    var tracksVersion by mutableStateOf(0)
        private set
    var notice by mutableStateOf<String?>(null)

    val current: File? get() = files.getOrNull(index)
    val hasNext: Boolean get() = index + 1 < files.size

    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private val sleepRunnable = Runnable {
        player?.pause()
        sleepEnd = null
        notice = "sleep"
    }

    private lateinit var appContext: Context
    private val positions by lazy { appContext.getSharedPreferences("positions", Context.MODE_PRIVATE) }

    fun play(context: Context, files: List<File>, start: Int) {
        appContext = context.applicationContext
        if (files.isEmpty()) return
        AudioConnection.pause()
        val exo = player ?: ExoPlayer.Builder(appContext)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
            .setHandleAudioBecomingNoisy(true)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
            .build().also { created ->
                player = created
                created.addListener(listener)
            }
        exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
            .setPreferredTextLanguage(if (Prefs.autoSubtitles.value) Locale.getDefault().language else null)
            .setPreferredAudioLanguage(Locale.getDefault().language)
            .build()
        val items = files.map { item(it) }
        val index = start.coerceIn(items.indices)
        val saved = positions.getLong(files[index].absolutePath, 0L)
        exo.setMediaItems(items, index, if (saved > 10_000) saved else 0L)
        exo.repeatMode = if (repeatOne) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
        exo.pauseAtEndOfMediaItems = false
        exo.setPlaybackSpeed(speed)
        exo.prepare()
        exo.play()
        this.files = files
        this.index = index
        cancelAutoNext = false
        title = files[index].nameWithoutExtension
        open = true
    }

    private fun item(file: File): MediaItem {
        val subtitles = Subtitles.find(file)
        val configs = subtitles.mapIndexed { i, sub ->
            MediaItem.SubtitleConfiguration.Builder(Uri.fromFile(sub.file))
                .setMimeType(sub.mime)
                .setLanguage(sub.language)
                .setLabel(sub.label)
                .setSelectionFlags(if (i == 0 && Prefs.autoSubtitles.value) C.SELECTION_FLAG_DEFAULT else 0)
                .build()
        }
        return MediaItem.Builder()
            .setUri(Uri.fromFile(file))
            .setMediaId(file.absolutePath)
            .setMediaMetadata(MediaMetadata.Builder().setTitle(file.nameWithoutExtension).build())
            .setSubtitleConfigurations(configs)
            .build()
    }

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(playing: Boolean) {
            isPlaying = playing
            if (!playing) savePosition()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            title = mediaItem?.mediaMetadata?.title?.toString() ?: ""
            index = player?.currentMediaItemIndex ?: index
            if (reason != Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT) {
                cancelAutoNext = false
                player?.pauseAtEndOfMediaItems = sleepAtEnd
            }
        }

        override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
            tracksVersion++
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (videoSize.width > 0 && videoSize.height > 0) {
                val ratio = videoSize.width.toFloat() * videoSize.pixelWidthHeightRatio / videoSize.height
                // Android n'accepte que des proportions entre 1:2,39 et 2,39:1 pour l'image dans l'image.
                val clamped = ratio.coerceIn(0.42f, 2.38f)
                aspect = Rational((clamped * 1000).toInt(), 1000)
            }
        }

        override fun onPlaybackStateChanged(state: Int) {
            if (state == Player.STATE_ENDED) {
                player?.currentMediaItem?.mediaId?.let { positions.edit().remove(it).apply() }
            }
        }
    }

    fun savePosition() {
        val exo = player ?: return
        val id = exo.currentMediaItem?.mediaId ?: return
        if (!::appContext.isInitialized) return
        val position = exo.currentPosition
        val duration = exo.duration
        val editor = positions.edit()
        if (duration > 0 && position > duration - 30_000) editor.remove(id) else editor.putLong(id, position)
        editor.apply()
    }

    fun pause() {
        player?.pause()
    }

    fun toggle() {
        val exo = player ?: return
        if (exo.isPlaying) exo.pause() else {
            if (exo.playbackState == Player.STATE_ENDED) exo.seekTo(0)
            exo.play()
        }
    }

    fun seekBy(ms: Long) {
        val exo = player ?: return
        val duration = exo.duration.takeIf { it > 0 } ?: Long.MAX_VALUE
        exo.seekTo((exo.currentPosition + ms).coerceIn(0, duration))
    }

    fun seekTo(ms: Long) {
        player?.seekTo(ms.coerceAtLeast(0))
    }

    fun next() {
        val exo = player ?: return
        if (exo.hasNextMediaItem()) exo.seekToNextMediaItem()
    }

    fun previous() {
        val exo = player ?: return
        if (exo.currentPosition > 5_000 || !exo.hasPreviousMediaItem()) exo.seekTo(0) else exo.seekToPreviousMediaItem()
    }

    @JvmName("changeSpeed")
    fun setSpeed(value: Float) {
        speed = value
        if (!boosted) player?.setPlaybackSpeed(value)
    }

    @JvmName("changeBoost")
    fun setBoost(on: Boolean) {
        if (on == boosted) return
        boosted = on
        player?.setPlaybackSpeed(if (on) maxOf(2f, speed) else speed)
    }

    fun toggleRepeat() {
        repeatOne = !repeatOne
        player?.repeatMode = if (repeatOne) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    /** « Épisode suivant » annulé : la vidéo s'arrête à la fin au lieu d'enchaîner. */
    fun cancelNext() {
        cancelAutoNext = true
        player?.pauseAtEndOfMediaItems = true
    }

    /** Minuterie : 0 = désactivée, -1 = fin de la vidéo. */
    fun setSleep(minutes: Int) {
        handler.removeCallbacks(sleepRunnable)
        sleepEnd = null
        sleepAtEnd = minutes == -1
        player?.pauseAtEndOfMediaItems = sleepAtEnd || cancelAutoNext
        if (minutes > 0) {
            sleepEnd = System.currentTimeMillis() + minutes * 60_000L
            handler.postDelayed(sleepRunnable, minutes * 60_000L)
        }
    }

    // Pistes : sous-titres et audio

    data class TrackChoice(val label: String, val group: androidx.media3.common.TrackGroup, val index: Int, val selected: Boolean)

    fun choices(type: Int): List<TrackChoice> {
        val exo = player ?: return emptyList()
        val out = ArrayList<TrackChoice>()
        for (group in exo.currentTracks.groups) {
            if (group.type != type) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val format = group.getTrackFormat(i)
                val label = format.label
                    ?: format.language?.let { Locale(it).getDisplayLanguage(Locale.getDefault()).replaceFirstChar { c -> c.titlecase() } }
                    ?: "#${out.size + 1}"
                out += TrackChoice(label, group.mediaTrackGroup, i, group.isTrackSelected(i))
            }
        }
        return out
    }

    fun select(type: Int, choice: TrackChoice?) {
        val exo = player ?: return
        val builder = exo.trackSelectionParameters.buildUpon()
        if (choice == null) {
            builder.setTrackTypeDisabled(type, true)
        } else {
            builder.setTrackTypeDisabled(type, false)
                .setOverrideForType(androidx.media3.common.TrackSelectionOverride(choice.group, choice.index))
        }
        exo.trackSelectionParameters = builder.build()
    }

    fun close() {
        savePosition()
        player?.run {
            removeListener(listener)
            release()
        }
        player = null
        isPlaying = false
        open = false
        inPip = false
        boosted = false
        handler.removeCallbacks(sleepRunnable)
        sleepEnd = null
        sleepAtEnd = false
    }
}
