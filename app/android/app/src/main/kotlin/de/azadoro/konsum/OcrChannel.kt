package de.azadoro.konsum

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Texterkennung für Kassenbons mit Tesseract4Android.
 *
 * `recognize` bekommt ein Graustufenbild (ein Byte je Pixel) und liefert den
 * Text. Jeder Aufruf läuft auf einem eigenen Thread mit eigener
 * Tesseract-Instanz, damit die Dart-Seite mehrere Läufe parallel starten kann.
 */
class OcrChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "de.azadoro.konsum/ocr")
    private val pool: ExecutorService = Executors.newFixedThreadPool(
        maxOf(1, minOf(4, Runtime.getRuntime().availableProcessors() / 2))
    )
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pool.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognize") {
            result.notImplemented()
            return
        }
        val pixels = call.argument<ByteArray>("pixels")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val psm = call.argument<Int>("psm") ?: TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK
        if (pixels == null || width == null || height == null) {
            result.error("args", "pixels, width und height fehlen", null)
            return
        }
        pool.execute {
            try {
                val text = recognize(pixels, width, height, psm)
                main.post { result.success(text) }
            } catch (e: Throwable) {
                main.post { result.error("ocr", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun recognize(pixels: ByteArray, width: Int, height: Int, psm: Int): String {
        val api = TessBaseAPI()
        try {
            if (!api.init(dataPath(), "deu", TessBaseAPI.OEM_LSTM_ONLY)) {
                throw IllegalStateException("Tesseract-Modell nicht ladbar")
            }
            api.pageSegMode = psm
            api.setImage(pixels, width, height, 1, width)
            return api.utF8Text ?: ""
        } finally {
            api.recycle()
        }
    }

    /**
     * Verzeichnis, das `tessdata/deu.traineddata` enthält. Das Modell wird aus
     * den Assets kopiert, nach jedem App-Update neu (Stempel: Zeitpunkt der
     * Installation).
     */
    private fun dataPath(): String = synchronized(OcrChannel::class.java) {
        val dir = File(context.filesDir, "ocr")
        val model = File(dir, "tessdata/deu.traineddata")
        val stamp = File(dir, "stamp")
        @Suppress("DEPRECATION")
        val installed = context.packageManager
            .getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
        if (!model.exists() || !stamp.exists() || stamp.readText() != installed) {
            model.parentFile!!.mkdirs()
            val key = FlutterInjector.instance().flutterLoader()
                .getLookupKeyForAsset("assets/tessdata/deu.traineddata")
            val tmp = File(model.parentFile, "deu.traineddata.tmp")
            context.assets.open(key).use { input ->
                tmp.outputStream().use { input.copyTo(it) }
            }
            if (!tmp.renameTo(model)) throw IllegalStateException("Modell nicht kopierbar")
            stamp.writeText(installed)
        }
        dir.absolutePath
    }
}
