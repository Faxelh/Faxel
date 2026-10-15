package com.faxel.app.engine

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.ContextCompat
import java.io.File

/**
 * Où Faxel range ses fichiers.
 *
 * Avec l'accès aux fichiers : dossier « Faxel » à la racine du téléphone, visible
 * dans le gestionnaire de fichiers, sur l'ordinateur (câble USB) et dans les autres
 * apps de musique ou de vidéo. Sinon : dossier privé de l'app.
 */
object Storage {
    fun hasFullAccess(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager()
        else ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    fun publicRoot(): File = File(Environment.getExternalStorageDirectory(), "Faxel")

    fun privateRoot(context: Context): File = File(context.getExternalFilesDir(null) ?: context.filesDir, "Faxel")

    fun root(context: Context): File {
        if (hasFullAccess(context)) {
            val folder = publicRoot()
            if ((folder.isDirectory || folder.mkdirs()) && folder.canWrite()) return folder
        }
        return privateRoot(context).apply { mkdirs() }
    }

    val isPublic: Boolean get() = Engine.root?.absolutePath == publicRoot().absolutePath

    /** Écran d'Android « Accès à tous les fichiers » (Android 11 et plus). */
    fun accessIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT < 30) return null
        return Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${context.packageName}"))
    }

    /** Fait apparaître le fichier dans les autres apps (Galerie, Musique…). */
    fun scan(context: Context, path: String) {
        if (path.isBlank()) return
        val file = File(path)
        val paths = if (file.isDirectory) file.listFiles()?.map { it.absolutePath } ?: emptyList() else listOf(path)
        if (paths.isNotEmpty()) MediaScannerConnection.scanFile(context, paths.toTypedArray(), null, null)
    }

    /**
     * Si l'accès complet vient d'être donné : déplace les fichiers du dossier privé
     * vers le dossier public, et met à jour les chemins gardés par le moteur.
     */
    fun migrate(context: Context, dataDir: File, target: File) {
        val old = privateRoot(context)
        if (old.absolutePath == target.absolutePath || !old.isDirectory) return
        val children = old.listFiles() ?: return
        if (children.isEmpty()) return
        children.forEach { moveInto(it, target) }
        listOf("history.json", "playlists.json", "queue.json").forEach { name ->
            val file = File(dataDir, name)
            if (file.exists()) runCatching {
                val text = file.readText()
                file.writeText(text.replace(old.absolutePath, target.absolutePath).replace(old.absolutePath.replace("/", "\\/"), target.absolutePath.replace("/", "\\/")))
            }
        }
    }

    private fun moveInto(source: File, folder: File) {
        val destination = File(folder, source.name)
        if (source.isDirectory) {
            destination.mkdirs()
            source.listFiles()?.forEach { moveInto(it, destination) }
            source.delete()
        } else if (!destination.exists()) {
            if (!source.renameTo(destination)) {
                runCatching {
                    source.copyTo(destination)
                    source.delete()
                }
            }
        }
    }
}
