package com.faxel.app

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.decode.VideoFrameDecoder
import com.faxel.app.data.Prefs
import com.faxel.app.engine.DownloadService
import com.faxel.app.engine.Engine

class FaxelApplication : Application(), ImageLoaderFactory {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        com.faxel.app.playback.AudioFx.init(this)
        DownloadService.channels(this)
        Engine.start(this, AppCompatDelegate.getApplicationLocales().toLanguageTags())
    }

    /** Miniatures : images en ligne et première image des vidéos du téléphone. */
    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .components { add(VideoFrameDecoder.Factory()) }
        .crossfade(true)
        .build()
}
