// కృషి మిత్ర (Krishi Mitra): fully offline crop disease/pest advisor in Telugu.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import 'advisory/llm_service.dart';
import 'advisory/prompt.dart';
import 'pipeline.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KrishiApp());
}

class KrishiApp extends StatelessWidget {
  const KrishiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'కృషి మిత్ర',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D32), useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

const _sevColor = {
  'none': Color(0xFF2E7D32),
  'mild': Color(0xFFF9A825),
  'moderate': Color(0xFFEF6C00),
  'urgent': Color(0xFFC62828),
};

class _HomePageState extends State<HomePage> {
  final _pipeline = Pipeline();
  final _llm = LlmService();
  final _tts = FlutterTts();
  bool _ready = false, _busy = false, _llmAvailable = false, _generating = false;
  Uint8List? _photo;
  VisionResult? _vr;
  String _advice = '';
  String? _adviceSource; // 'llm' | 'template'
  String _llmInfo = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _pipeline.init();
    try {
      _llmAvailable = await _llm.available();
    } catch (_) {
      _llmAvailable = false;
    }
    await _tts.setLanguage('te-IN');
    setState(() => _ready = true);
  }

  Future<void> _importModel() async {
    final names = await _llm.importModel();
    final ok = await _llm.available();
    if (!mounted) return;
    setState(() => _llmAvailable = ok);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Llama సిద్ధం: ${names.join(', ')}'
            : 'రెండు ఫైళ్లు ఎంచుకోండి: .pte మోడల్ మరియు tokenizer.model')));
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 92);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _busy = true;
      _photo = bytes;
      _vr = null;
      _advice = '';
      _adviceSource = null;
      _llmInfo = '';
    });
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let spinner paint
    final vr = _pipeline.runVision(bytes); // stage 1+2 (vision), sequential
    setState(() {
      _vr = vr;
      _busy = false;
    });
    await _advise(vr); // stage 3 (advisory) only after vision is done
  }

  Future<void> _advise(VisionResult vr) async {
    final db = _pipeline.db;
    final e = vr.entry;
    final level = vr.severity.level;
    final template = db.templateAdvice(e, level);
    if (!_llmAvailable || e.healthy || !vr.confident) {
      setState(() {
        _advice = template.map((s) => '• $s').join('\n');
        _adviceSource = 'template';
      });
      return;
    }
    final verified = [...db.genericSteps(level), ...e.stepsFor(level)];
    final prompt = buildPrompt(
        e: e,
        level: level,
        levelTe: db.severityTe(level),
        lesionPct: vr.severity.lesionRatio * 100,
        confidence: vr.best.score,
        verifiedSteps: verified);
    setState(() {
      _generating = true;
      _adviceSource = 'llm';
      _llmInfo = 'Llama 3.2 1B లోడ్ అవుతోంది…';
    });
    try {
      var loadMs = 0;
      if (!_llm.loaded) loadMs = await _llm.load();
      final sw = Stopwatch()..start();
      int? firstTokMs;
      var n = 0;
      final buf = StringBuffer();
      await for (final t in _llm.generate(prompt)) {
        firstTokMs ??= sw.elapsedMilliseconds;
        n++;
        buf.write(t);
        setState(() {
          _advice = buf.toString();
          _llmInfo = 'Llama 3.2 1B (ExecuTorch, INT4) రాస్తోంది…';
        });
      }
      final total = sw.elapsedMilliseconds;
      final ok = validateAdvice(buf.toString(), prompt);
      setState(() {
        _generating = false;
        final tps = n / ((total - (firstTokMs ?? 0)) / 1000).clamp(0.001, 1e9);
        _llmInfo = 'LLM: ${loadMs > 0 ? 'load ${loadMs}ms, ' : ''}first token ${firstTokMs ?? 0}ms, '
            '$n tokens, ${tps.toStringAsFixed(1)} tok/s';
        if (ok != null) {
          _advice = ok;
        } else {
          _advice = template.map((s) => '• $s').join('\n');
          _adviceSource = 'template';
          _llmInfo += ' · AI జవాబు ధృవీకరణలో విఫలమైంది, ధృవీకరించిన సలహా చూపుతున్నాం';
        }
      });
    } catch (err) {
      setState(() {
        _generating = false;
        _advice = template.map((s) => '• $s').join('\n');
        _adviceSource = 'template';
        _llmInfo = 'LLM error: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('కృషి మిత్ర · పంట వైద్యుడు'),
        actions: [
          IconButton(
            tooltip: 'Llama మోడల్ దిగుమతి',
            icon: const Icon(Icons.download_for_offline),
            onPressed: _busy || _generating ? null : _importModel,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: const Icon(Icons.wifi_off, size: 16),
              label: Text(_llmAvailable ? 'ఆఫ్‌లైన్ · Llama' : 'ఆఫ్‌లైన్'),
            ),
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || _generating ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14), child: Text('ఫోటో తీయండి', style: TextStyle(fontSize: 18))),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy || _generating ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('గ్యాలరీ')),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('ఒక ఆకును దగ్గరగా, వెలుతురులో, స్పష్టంగా ఫోటో తీయండి.', style: TextStyle(color: Colors.black54)),
              if (_busy) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (_vr != null) ..._result(_vr!),
            ]),
    );
  }

  List<Widget> _result(VisionResult vr) {
    final db = _pipeline.db;
    final e = vr.entry;
    final sev = vr.severity;
    final color = _sevColor[sev.level]!;
    return [
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_photo!, height: 160, fit: BoxFit.cover))),
        const SizedBox(width: 8),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(sev.overlayPng, height: 160, fit: BoxFit.cover))),
      ]),
      const SizedBox(height: 4),
      const Text('కుడి: ఎరుపు = దెబ్బతిన్న భాగం', style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 12),
      if (!sev.leafFound || !vr.confident)
        Card(
          color: Colors.amber.shade50,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('ఖచ్చితంగా గుర్తించలేకపోయాం. ఒకే ఆకును దగ్గరగా, నీడ లేకుండా మళ్ళీ ఫోటో తీయండి. క్రింది ఫలితం అంచనా మాత్రమే.'),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.cropTe} · ${e.diseaseTe}', style: Theme.of(context).textTheme.titleLarge),
            Text('${e.cropEn} · ${e.diseaseEn}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                backgroundColor: color.withValues(alpha: 0.15),
                side: BorderSide(color: color),
                label: Text('తీవ్రత: ${db.severityTe(sev.level)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
              Chip(label: Text('నమ్మకం ${(vr.best.score * 100).toStringAsFixed(0)}%')),
              if (!e.healthy) Chip(label: Text('దెబ్బతిన్న భాగం ${(sev.lesionRatio * 100).toStringAsFixed(0)}%')),
            ]),
            if (!vr.confident)
              Text('ఇతర అవకాశాలు: ${vr.top.skip(1).map((p) => '${db.entry(p.label).diseaseTe} ${(p.score * 100).toStringAsFixed(0)}%').join(', ')}',
                  style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text('లక్షణాలు: ${e.symptomsTe}'),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_adviceSource == 'llm' ? Icons.auto_awesome : Icons.verified, color: Colors.green.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_adviceSource == 'llm' ? 'AI సలహా (Llama 3.2, ఆఫ్‌లైన్)' : 'సలహా (ధృవీకరించిన సమాచారం)',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'వినండి',
                onPressed: _advice.isEmpty ? null : () => _tts.speak(_advice.replaceAll('•', '')),
                icon: const Icon(Icons.volume_up),
              ),
            ]),
            if (_generating) const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_advice, style: const TextStyle(fontSize: 16, height: 1.5)),
            if (_llmInfo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_llmInfo, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          ]),
        ),
      ),
      if (_adviceSource == 'llm' && !_generating)
        ExpansionTile(
          title: const Text('ధృవీకరించిన చర్యలు (మూలం)'),
          children: [
            for (final s in [...db.genericSteps(sev.level), ...e.stepsFor(sev.level)])
              ListTile(dense: true, leading: const Icon(Icons.check, size: 18), title: Text(s)),
          ],
        ),
      ExpansionTile(
        title: const Text('ఎరువులు, నీటి యాజమాన్యం, కోత తర్వాత'),
        children: [
          ListTile(leading: const Icon(Icons.water_drop), title: Text(e.fertiliserIrrigation)),
          ListTile(leading: const Icon(Icons.inventory_2), title: Text(e.postHarvest)),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('⚠ ${db.verifyNote}\nమూలం: ${e.source}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ),
      Text('సమయం: decode ${vr.decodeMs}ms · వ్యాధి గుర్తింపు ${vr.classifyMs}ms · తీవ్రత ${vr.severityMs}ms',
          style: const TextStyle(fontSize: 12, color: Colors.black45)),
    ];
  }
}
