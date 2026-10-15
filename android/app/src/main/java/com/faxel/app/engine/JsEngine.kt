package com.faxel.app.engine

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.WebView
import androidx.javascriptengine.IsolateStartupParameters
import androidx.javascriptengine.JavaScriptSandbox
import org.json.JSONObject
import org.json.JSONTokener
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Moteur JavaScript pour les défis YouTube de yt-dlp (appelé depuis Python, faxel/engine/jsc.py).
 *
 * 1. JavaScriptSandbox (V8 de WebView, isolé, rapide) quand le téléphone le permet ;
 * 2. sinon une WebView invisible (fonctionne sur tous les Android).
 *
 * Le script écrit son résultat avec console.log ; le prélude le récupère dans __player_out.
 */
object JsEngine {
    private const val TAG = "FaxelJs"
    private const val ERROR = "\u0000ERR:"
    private lateinit var appContext: Context
    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())
    private var sandbox: JavaScriptSandbox? = null
    private var sandboxBroken = false
    private var webView: WebView? = null

    @JvmStatic
    fun init(context: Context) {
        appContext = context.applicationContext
        main.post { ensureWebView() }
    }

    @JvmStatic
    fun available(): Boolean = ::appContext.isInitialized

    @JvmStatic
    fun run(prelude: String, script: String): String = synchronized(lock) {
        val first = runCatching { runSandbox(prelude, script) }
        first.getOrNull()?.let { return it }
        first.exceptionOrNull()?.let { Log.i(TAG, "JavaScriptSandbox indisponible : ${it.message}") }
        runCatching { runWebView(prelude, script) }.getOrElse { error ->
            ERROR + (error.message ?: error.javaClass.simpleName)
        }
    }

    private fun runSandbox(prelude: String, script: String): String {
        if (Build.VERSION.SDK_INT < 26 || sandboxBroken) error("non pris en charge")
        if (!JavaScriptSandbox.isSupported()) {
            sandboxBroken = true
            error("non pris en charge")
        }
        val box = sandbox ?: JavaScriptSandbox.createConnectedInstanceAsync(appContext).get(15, TimeUnit.SECONDS)
            .also { sandbox = it }
        // Le script du lecteur YouTube est gros : sans cette option, Android refuse de le transmettre.
        if (!box.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_EVALUATE_WITHOUT_TRANSACTION_LIMIT)) {
            sandboxBroken = true
            error("scripts volumineux non pris en charge")
        }
        val isolate = try {
            if (box.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_ISOLATE_MAX_HEAP_SIZE)) {
                box.createIsolate(IsolateStartupParameters().apply { maxHeapSizeBytes = 512L * 1024 * 1024 })
            } else {
                box.createIsolate()
            }
        } catch (error: Throwable) {
            runCatching { box.close() }
            sandbox = null
            throw error
        }
        try {
            val code = prelude + "\n" + script + "\n;__player_out.join('\\n')"
            return isolate.evaluateJavaScriptAsync(code).get(120, TimeUnit.SECONDS) ?: ""
        } finally {
            runCatching { isolate.close() }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun ensureWebView(): WebView {
        webView?.let { return it }
        val view = WebView(appContext)
        view.settings.javaScriptEnabled = true
        view.loadDataWithBaseURL("https://faxel.local/", "<html><body></body></html>", "text/html", "utf-8", null)
        webView = view
        return view
    }

    private fun runWebView(prelude: String, script: String): String {
        if (Looper.myLooper() == Looper.getMainLooper()) error("appel depuis le fil principal")
        val latch = CountDownLatch(1)
        var result: String? = null
        main.post {
            try {
                val view = ensureWebView()
                view.evaluateJavascript(prelude) {}
                view.evaluateJavascript(script) {}
                view.evaluateJavascript("__player_out.join('\\n')") { value ->
                    result = decode(value)
                    latch.countDown()
                }
            } catch (error: Throwable) {
                result = ERROR + (error.message ?: "WebView")
                latch.countDown()
            }
        }
        if (!latch.await(120, TimeUnit.SECONDS)) return ERROR + "délai dépassé"
        return result ?: ""
    }

    private fun decode(value: String?): String {
        if (value.isNullOrEmpty() || value == "null") return ""
        return runCatching {
            when (val parsed = JSONTokener(value).nextValue()) {
                is String -> parsed
                JSONObject.NULL -> ""
                else -> parsed.toString()
            }
        }.getOrDefault(value)
    }
}
