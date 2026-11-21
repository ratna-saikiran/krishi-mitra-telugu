package com.krishimitra.krishi_mitra

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Point
import org.opencv.core.Rect
import org.opencv.core.Scalar
import org.opencv.imgproc.Imgproc
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.hypot
import kotlin.math.sqrt

/**
 * Severity = lesion area / leaf area, same steps as ml/severity.py:
 * GrabCut (central rect) -> component nearest centre -> fill holes ->
 * non-green pixels inside the leaf are lesions. OpenCV on the Arm CPU.
 */
class SeverityBridge(messenger: BinaryMessenger) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        OpenCVLoader.initLocal()
        MethodChannel(messenger, "krishi/severity").setMethodCallHandler { call, result ->
            if (call.method != "analyze") { result.notImplemented(); return@setMethodCallHandler }
            val rgb = call.argument<ByteArray>("rgb")!!
            val n = call.argument<Int>("n")!!
            worker.execute {
                val r = try { analyze(rgb, n) } catch (e: Throwable) { mapOf("error" to e.toString()) }
                main.post { result.success(r) }
            }
        }
    }

    private fun analyze(rgb: ByteArray, n: Int): Map<String, Any> {
        val t0 = System.nanoTime()
        val img = Mat(n, n, CvType.CV_8UC3).apply { put(0, 0, rgb) }
        val bgr = Mat(); Imgproc.cvtColor(img, bgr, Imgproc.COLOR_RGB2BGR)
        val mask = Mat.zeros(n, n, CvType.CV_8UC1)
        val m = (n * 0.12).toInt()
        Imgproc.grabCut(bgr, mask, Rect(m, m, n - 2 * m, n - 2 * m), Mat(), Mat(), 4, Imgproc.GC_INIT_WITH_RECT)
        val mb = ByteArray(n * n); mask.get(0, 0, mb)
        val fb = ByteArray(n * n) { i ->
            val v = mb[i].toInt()
            if (v == Imgproc.GC_FGD || v == Imgproc.GC_PR_FGD) 1 else 0
        }
        val fg = Mat(n, n, CvType.CV_8UC1).apply { put(0, 0, fb) }

        // Component nearest the centre (normalised by size), area >= 2%.
        val labels = Mat(); val stats = Mat(); val cents = Mat()
        val nc = Imgproc.connectedComponentsWithStats(fg, labels, stats, cents, 4, CvType.CV_32S)
        var best = -1; var bestScore = Double.MAX_VALUE
        for (i in 1 until nc) {
            val area = stats.get(i, Imgproc.CC_STAT_AREA)[0]
            if (area < 0.02 * n * n) continue
            val s = hypot(cents.get(i, 0)[0] - n / 2.0, cents.get(i, 1)[0] - n / 2.0) / sqrt(area)
            if (s < bestScore) { bestScore = s; best = i }
        }
        val lab = IntArray(n * n); labels.get(0, 0, lab)
        val leaf = ByteArray(n * n) { i -> if (best > 0 && lab[i] == best) 1 else 0 }
        // Fill holes: flood the background from the corner (outside the GrabCut rect).
        if (best > 0) {
            val ff = Mat(n, n, CvType.CV_8UC1).apply { put(0, 0, leaf) }
            Imgproc.floodFill(ff, Mat.zeros(n + 2, n + 2, CvType.CV_8UC1), Point(0.0, 0.0), Scalar(1.0))
            val fl = ByteArray(n * n); ff.get(0, 0, fl)
            for (i in 0 until n * n) if (fl[i].toInt() == 0) leaf[i] = 1
        }

        val hsv = Mat(); Imgproc.cvtColor(img, hsv, Imgproc.COLOR_RGB2HSV_FULL)
        val hb = ByteArray(n * n * 3); hsv.get(0, 0, hb)
        var nLeaf = 0; var nLes = 0
        val px = IntArray(n * n)
        for (i in 0 until n * n) {
            val r = rgb[3 * i].toInt() and 0xFF
            val g = rgb[3 * i + 1].toInt() and 0xFF
            val b = rgb[3 * i + 2].toInt() and 0xFF
            if (leaf[i].toInt() == 0) {
                px[i] = (0xFF shl 24) or ((r * 35 / 100) shl 16) or ((g * 35 / 100) shl 8) or (b * 35 / 100)
                continue
            }
            nLeaf++
            val h = (hb[3 * i].toInt() and 0xFF) * 360.0 / 256
            val s = (hb[3 * i + 1].toInt() and 0xFF) / 255.0
            val v = (hb[3 * i + 2].toInt() and 0xFF) / 255.0
            val healthy = h >= 65 && h <= 175 && s > 0.10 && v > 0.10
            px[i] = if (!healthy) {
                nLes++
                (0xFF shl 24) or (255 shl 16) or ((g * 3 / 10) shl 8) or (b * 3 / 10)
            } else (0xFF shl 24) or (r shl 16) or (g shl 8) or b
        }
        val bmp = Bitmap.createBitmap(px, n, n, Bitmap.Config.ARGB_8888)
        val png = ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        val ms = (System.nanoTime() - t0) / 1e6
        return mapOf(
            "ratio" to (if (nLeaf > 0) nLes.toDouble() / nLeaf else 0.0),
            "leafFraction" to nLeaf.toDouble() / (n * n),
            "overlay" to png,
            "ms" to ms,
        )
    }
}
