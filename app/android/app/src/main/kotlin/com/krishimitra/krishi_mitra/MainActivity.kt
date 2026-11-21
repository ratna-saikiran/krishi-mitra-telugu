package com.krishimitra.krishi_mitra

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private var pendingImport: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LlmBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        SeverityBridge(flutterEngine.dartExecutor.binaryMessenger)
        VisionBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger,
            FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/models/classifier.tflite"))
        // "Import Llama model": pick the .pte and tokenizer.model from phone
        // storage (e.g. Downloads) and copy them into the app's private files.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "krishi/import").setMethodCallHandler { call, result ->
            if (call.method != "pick") { result.notImplemented(); return@setMethodCallHandler }
            pendingImport = result
            val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
            startActivityForResult(i, REQ_IMPORT)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_IMPORT) return
        val res = pendingImport ?: return
        pendingImport = null
        if (resultCode != Activity.RESULT_OK || data == null) { res.success(emptyList<String>()); return }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { c -> for (k in 0 until c.itemCount) uris.add(c.getItemAt(k).uri) }
        data.data?.let { if (uris.isEmpty()) uris.add(it) }
        thread {
            val dir = File(filesDir, "llama").apply { mkdirs() }
            val copied = mutableListOf<String>()
            for (u in uris) {
                var name = queryName(u) ?: continue
                if (!name.endsWith(".pte") && !name.startsWith("tokenizer")) continue
                if (name.startsWith("tokenizer") && !name.endsWith(".json")) name = "tokenizer.model"
                contentResolver.openInputStream(u)?.use { inp ->
                    File(dir, name).outputStream().use { out -> inp.copyTo(out, 1 shl 20) }
                }
                copied.add(name)
            }
            runOnUiThread { res.success(copied) }
        }
    }

    private fun queryName(u: Uri): String? =
        contentResolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    companion object { private const val REQ_IMPORT = 4242 }
}
