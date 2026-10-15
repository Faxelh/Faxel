package com.faxel.app

import android.Manifest
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.faxel.app.data.Prefs
import com.faxel.app.engine.Engine
import com.faxel.app.playback.AudioConnection
import com.faxel.app.playback.VideoState
import com.faxel.app.ui.FaxelRoot
import com.faxel.app.ui.FaxelTheme

class MainActivity : AppCompatActivity() {
    private val askPermissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        AudioConnection.connect(this)
        val wanted = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
        if (Build.VERSION.SDK_INT < 30) wanted += Manifest.permission.WRITE_EXTERNAL_STORAGE
        if (wanted.isNotEmpty() && savedInstanceState == null) askPermissions.launch(wanted.toTypedArray())
        handle(intent)
        setContent {
            FaxelTheme {
                FaxelRoot()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** Lien partagé depuis YouTube, TikTok, Instagram… (« Partager » → Faxel). */
    private fun handle(intent: Intent?) {
        intent ?: return
        val text = when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT) ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        } ?: return
        val link = Regex("""https?://\S+""").find(text)?.value ?: return
        Engine.pendingAutoDownload = Prefs.oneTapShare.value
        Engine.pendingLink = link
        intent.action = null
    }

    override fun onStart() {
        super.onStart()
        visible = true
    }

    override fun onStop() {
        super.onStop()
        visible = false
        VideoState.savePosition()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (VideoState.open && VideoState.isPlaying && Prefs.autoPip.value) enterPip()
    }

    fun enterPip() {
        if (Build.VERSION.SDK_INT < 26) return
        runCatching {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(VideoState.aspect).build())
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        VideoState.inPip = isInPictureInPictureMode
        // Fenêtre fermée depuis l'image dans l'image : on arrête la vidéo.
        if (!isInPictureInPictureMode && lifecycle.currentState == androidx.lifecycle.Lifecycle.State.CREATED) {
            VideoState.close()
        }
    }

    companion object {
        @Volatile
        var visible = false
    }
}
