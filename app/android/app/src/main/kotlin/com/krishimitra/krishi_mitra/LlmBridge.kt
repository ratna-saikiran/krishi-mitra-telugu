package com.krishimitra.krishi_mitra

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.pytorch.executorch.extension.llm.LlmCallback
import org.pytorch.executorch.extension.llm.LlmModule
import java.io.File
import java.util.concurrent.Executors

/**
 * Flutter <-> ExecuTorch bridge for Llama 3.2 1B Instruct (.pte exported with
 * XNNPACK + 8da4w, see llm/export_llama.sh). Runs on one background thread so
 * the vision stage and LLM never compete for cores (sequential pipeline).
 */
class LlmBridge(private val ctx: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var module: LlmModule? = null
    private var sink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, "krishi/llm").setMethodCallHandler(this)
        EventChannel(messenger, "krishi/llm_tokens").setStreamHandler(this)
    }

    private fun searchDirs(): List<File> = listOfNotNull(
        File("/data/local/tmp/llama"),
        ctx.getExternalFilesDir(null)?.let { File(it, "llama") },
        File(ctx.filesDir, "llama"),
    )

    private fun findFiles(): Pair<File?, File?> {
        for (d in searchDirs()) {
            val files = d.listFiles() ?: continue
            val pte = files.filter { it.name.endsWith(".pte") }.maxByOrNull { it.length() }
            val tok = files.firstOrNull { it.name == "tokenizer.model" || it.name == "tokenizer.bin" || it.name == "tokenizer.json" }
            if (pte != null && tok != null) return pte to tok
        }
        return null to null
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "find" -> {
                val (pte, tok) = findFiles()
                result.success(mapOf("model" to pte?.absolutePath, "tokenizer" to tok?.absolutePath))
            }
            "load" -> worker.execute {
                val (pte, tok) = findFiles()
                val rc = if (pte == null || tok == null) -1 else try {
                    module = LlmModule(pte.absolutePath, tok.absolutePath, 0.2f)
                    module!!.load()
                } catch (e: Throwable) { -2 }
                main.post { result.success(rc) }
            }
            "generate" -> {
                val prompt = call.argument<String>("prompt")!!
                val seqLen = call.argument<Int>("seqLen") ?: 1536
                result.success(null)
                worker.execute {
                    val m = module
                    if (m == null) { emit(mapOf("error" to "not loaded", "done" to true)); return@execute }
                    m.resetContext()
                    m.generate(prompt, seqLen, object : LlmCallback {
                        override fun onResult(token: String) {
                            if (token == "<|eot_id|>" || token == "<|end_of_text|>") return
                            emit(mapOf("token" to token))
                        }
                        override fun onStats(stats: String) { emit(mapOf("stats" to stats)) }
                    }, false)
                    emit(mapOf("done" to true))
                }
            }
            "stop" -> { module?.stop(); result.success(null) }
            "unload" -> worker.execute {
                module?.resetNative(); module = null
                main.post { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    private fun emit(m: Map<String, Any>) = main.post { sink?.success(m) }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }
}
