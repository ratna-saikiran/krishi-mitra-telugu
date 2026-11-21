package com.krishimitra.krishi_mitra

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

/**
 * Runs the INT8 TFLite classifier on the Arm CPU (XNNPACK delegate, 4 threads).
 * Dart sends 224x224 RGB bytes; we return softmax probabilities.
 */
class VisionBridge(private val ctx: Context, messenger: BinaryMessenger, private val assetKey: String) {
    private var interp: Interpreter? = null
    private val input = ByteBuffer.allocateDirect(224 * 224 * 3 * 4).order(ByteOrder.nativeOrder())

    init {
        MethodChannel(messenger, "krishi/vision").setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> try {
                    val opts = Interpreter.Options().setNumThreads(4).setUseXNNPACK(true)
                    interp = Interpreter(loadAsset(), opts)
                    result.success(interp!!.getOutputTensor(0).shape()[1])
                } catch (e: Throwable) { result.error("load", e.toString(), null) }
                "classify" -> {
                    val rgb = call.arguments as ByteArray
                    val it = interp ?: return@setMethodCallHandler result.error("classify", "not loaded", null)
                    input.rewind()
                    for (b in rgb) input.putFloat((b.toInt() and 0xFF).toFloat())
                    input.rewind()
                    val n = it.getOutputTensor(0).shape()[1]
                    val out = Array(1) { FloatArray(n) }
                    val t0 = System.nanoTime()
                    it.run(input, out)
                    val ms = (System.nanoTime() - t0) / 1e6
                    result.success(mapOf("probs" to out[0].map { v -> v.toDouble() }, "ms" to ms))
                }
                "close" -> { interp?.close(); interp = null; result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun loadAsset(): MappedByteBuffer {
        val fd = ctx.assets.openFd(assetKey)
        FileInputStream(fd.fileDescriptor).channel.use { ch ->
            return ch.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
        }
    }
}
