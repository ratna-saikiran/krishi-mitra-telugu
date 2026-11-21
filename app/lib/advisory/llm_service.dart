// Dart side of the ExecuTorch bridge (android/.../LlmBridge.kt).
// Llama 3.2 1B Instruct, 8da4w (INT4 weights / INT8 dyn. activations), XNNPACK.
import 'dart:async';

import 'package:flutter/services.dart';

class LlmStats {
  final int tokens;
  final double tokPerSec;
  final int ttftMs;
  LlmStats(this.tokens, this.tokPerSec, this.ttftMs);
}

class LlmService {
  static const _ch = MethodChannel('krishi/llm');
  static const _ev = EventChannel('krishi/llm_tokens');
  static const _import = MethodChannel('krishi/import');
  bool loaded = false;
  String? modelPath;

  /// Looks for *.pte + tokenizer in /data/local/tmp/llama or the app's files dir.
  Future<bool> available() async {
    final r = await _ch.invokeMapMethod<String, dynamic>('find');
    modelPath = r?['model'];
    return modelPath != null && r?['tokenizer'] != null;
  }

  Future<int> load() async {
    final sw = Stopwatch()..start();
    final rc = await _ch.invokeMethod<int>('load');
    if (rc != 0) throw Exception('Llama load failed (code $rc)');
    loaded = true;
    return sw.elapsedMilliseconds;
  }

  /// Streams tokens; completes with stats when generation ends.
  Stream<String> generate(String prompt, {int seqLen = 1536}) {
    final ctrl = StreamController<String>();
    late StreamSubscription sub;
    sub = _ev.receiveBroadcastStream().listen((e) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m.containsKey('token')) ctrl.add(m['token'] as String);
      if (m.containsKey('stats')) lastStatsJson = m['stats'] as String;
      if (m['done'] == true) {
        sub.cancel();
        ctrl.close();
      }
    }, onError: (Object err) {
      ctrl.addError(err);
      ctrl.close();
    });
    _ch.invokeMethod('generate', {'prompt': prompt, 'seqLen': seqLen});
    return ctrl.stream;
  }

  String? lastStatsJson;

  /// Opens the system file picker; copies the chosen .pte / tokenizer.model
  /// into app storage. Returns the copied file names.
  Future<List<String>> importModel() async =>
      List<String>.from(await _import.invokeMethod<List<dynamic>>('pick') ?? const []);

  Future<void> stop() => _ch.invokeMethod('stop');
  Future<void> unload() async {
    await _ch.invokeMethod('unload');
    loaded = false;
  }
}
