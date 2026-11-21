// Krishi Data: offline field photo collector for retraining the Krishi Mitra
// model. Each photo is saved with its crop, problem type, problem name and
// severity as  <Crop>___<Condition>/<time>.jpg  plus one row in labels.csv.
// "Export" zips everything (same folder layout the training script reads)
// and opens the Android share sheet (Drive, WhatsApp, email...).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const CollectorApp());

class CollectorApp extends StatelessWidget {
  const CollectorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Krishi Data',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0), useMaterial3: true),
        home: const CollectPage(),
      );
}

/// Folder-safe class name, same convention as the training labels.
String slug(String s) => s.trim().replaceAll(RegExp(r'[^A-Za-z0-9()]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');

String labelFor(String crop, String type, String name) {
  final c = slug(crop);
  if (type == 'healthy') return '${c}___healthy';
  final n = slug(name);
  return '${c}___${n.isEmpty ? 'Unknown_$type' : n}';
}

class CollectPage extends StatefulWidget {
  const CollectPage({super.key});
  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage> {
  Map<String, Map<String, String>> _crops = {}; // key -> {en, te}
  Map<String, List<String>> _known = {}; // crop key -> known conditions
  Directory? _root;
  final List<File> _photos = [];
  String? _crop; // crop key, or 'other'
  final _otherCrop = TextEditingController();
  String _type = 'disease';
  final _name = TextEditingController();
  String _severity = 'moderate';
  final _notes = TextEditingController();
  Map<String, int> _counts = {};
  bool _saving = false;

  static const _types = {
    'healthy': 'Healthy · ఆరోగ్యం',
    'disease': 'Disease · తెగులు',
    'pest': 'Pest · పురుగు',
    'nutrient': 'Nutrient · పోషక లోపం',
    'unknown': 'Not sure · తెలియదు',
  };
  static const _sev = {'mild': 'Mild · తక్కువ', 'moderate': 'Moderate · మధ్యస్థం', 'urgent': 'Severe · తీవ్రం'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final crops = Map<String, dynamic>.from(jsonDecode(await rootBundle.loadString('assets/crops.json')));
    final labels = (await rootBundle.loadString('assets/labels.txt')).split('\n').where((l) => l.contains('___'));
    final known = <String, List<String>>{};
    for (final l in labels) {
      final p = l.trim().split('___');
      if (p[1] != 'healthy') known.putIfAbsent(p[0], () => []).add(p[1].replaceAll('_', ' '));
    }
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/krishi_data')..createSync(recursive: true);
    setState(() {
      _crops = {for (final e in crops.entries) if (e.key != 'Pest') e.key: Map<String, String>.from(e.value)};
      _known = known;
      _root = root;
    });
    _recount();
  }

  void _recount() {
    final counts = <String, int>{};
    for (final d in _root!.listSync().whereType<Directory>()) {
      counts[d.uri.pathSegments.where((s) => s.isNotEmpty).last] = d.listSync().whereType<File>().length;
    }
    setState(() => _counts = counts);
  }

  Future<void> _add(ImageSource src) async {
    final picker = ImagePicker();
    final files = src == ImageSource.camera
        ? [if (await picker.pickImage(source: src, maxWidth: 1600, imageQuality: 90) case final x?) x]
        : await picker.pickMultiImage(maxWidth: 1600, imageQuality: 90);
    setState(() => _photos.addAll(files.map((x) => File(x.path))));
  }

  String get _cropName => _crop == 'other' ? _otherCrop.text : (_crop ?? '');

  Future<void> _save() async {
    if (_photos.isEmpty || _cropName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a photo and choose the crop · ఫోటో, పంట ఎంచుకోండి')));
      return;
    }
    setState(() => _saving = true);
    final label = labelFor(_cropName, _type, _name.text);
    final dir = Directory('${_root!.path}/$label')..createSync(recursive: true);
    final csv = File('${_root!.path}/labels.csv');
    if (!csv.existsSync()) csv.writeAsStringSync('file,label,crop,type,problem,severity,notes,time\n');
    String q(String s) => '"${s.replaceAll('"', "'")}"';
    for (final (i, f) in _photos.indexed) {
      final t = DateTime.now();
      final name = '${t.millisecondsSinceEpoch}_$i.jpg';
      await f.copy('${dir.path}/$name');
      csv.writeAsStringSync(
          '${q('$label/$name')},${q(label)},${q(_cropName)},$_type,${q(_name.text)},${_type == 'healthy' ? 'none' : _severity},${q(_notes.text)},${t.toIso8601String()}\n',
          mode: FileMode.append);
    }
    final n = _photos.length;
    setState(() {
      _photos.clear();
      _saving = false;
    });
    _recount();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $n photo(s) as $label')));
  }

  Future<void> _export() async {
    if (_counts.isEmpty) return;
    final tmp = await getTemporaryDirectory();
    final zipPath = '${tmp.path}/krishi_data_${DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-')}.zip';
    final enc = ZipFileEncoder()..create(zipPath);
    await enc.addDirectory(_root!, includeDirName: false);
    await enc.close();
    await SharePlus.instance.share(ShareParams(files: [XFile(zipPath)], text: 'Krishi Mitra field photos for training'));
  }

  @override
  Widget build(BuildContext context) {
    final total = _counts.values.fold(0, (a, b) => a + b);
    final suggestions = _crop == null || _crop == 'other' ? const <String>[] : (_known[_crop] ?? const <String>[]);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Krishi Data · ఫోటో సేకరణ'),
        actions: [
          TextButton.icon(onPressed: total == 0 ? null : _export, icon: const Icon(Icons.ios_share), label: Text('Export ($total)')),
        ],
      ),
      body: _root == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed: () => _add(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('Camera · ఫోటో'))),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: () => _add(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Gallery')),
              ]),
              const SizedBox(height: 4),
              const Text('Tip: one leaf or insect filling the frame; also add a few whole-plant photos.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 96,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final (i, f) in _photos.indexed)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Stack(children: [
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(f, width: 88, height: 88, fit: BoxFit.cover)),
                          Positioned(
                            right: 0,
                            child: InkWell(
                                onTap: () => setState(() => _photos.removeAt(i)),
                                child: const CircleAvatar(radius: 11, child: Icon(Icons.close, size: 14))),
                          ),
                        ]),
                      ),
                  ]),
                ),
              const SizedBox(height: 16),
              const Text('Crop · పంట', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in _crops.entries)
                  ChoiceChip(
                      label: Text('${e.value['en']} · ${e.value['te']}'),
                      selected: _crop == e.key,
                      onSelected: (_) => setState(() => _crop = e.key)),
                ChoiceChip(label: const Text('Other · ఇతర'), selected: _crop == 'other', onSelected: (_) => setState(() => _crop = 'other')),
              ]),
              if (_crop == 'other')
                TextField(controller: _otherCrop, decoration: const InputDecoration(labelText: 'Crop name in English (e.g. Spinach)')),
              const SizedBox(height: 16),
              const Text('Problem · సమస్య', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in _types.entries)
                  ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
              ]),
              if (_type != 'healthy') ...[
                TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Disease / pest name in English (e.g. Leaf spot, Aphids)')),
                if (suggestions.isNotEmpty)
                  Wrap(spacing: 4, children: [
                    for (final s in suggestions)
                      ActionChip(visualDensity: VisualDensity.compact, label: Text(s), onPressed: () => setState(() => _name.text = s)),
                  ]),
                const SizedBox(height: 12),
                const Text('Severity · తీవ్రత', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(spacing: 6, children: [
                  for (final e in _sev.entries)
                    ChoiceChip(label: Text(e.value), selected: _severity == e.key, onSelected: (_) => setState(() => _severity = e.key)),
                ]),
              ],
              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (village, spray used, ...)')),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Save ${_photos.length} photo(s) · భద్రపరచండి', style: const TextStyle(fontSize: 16))),
              ),
              const SizedBox(height: 20),
              Text('Collected · సేకరించినవి: $total', style: Theme.of(context).textTheme.titleMedium),
              for (final e in (_counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                ListTile(dense: true, title: Text(e.key.replaceAll('___', ' · ').replaceAll('_', ' ')), trailing: Text('${e.value}')),
              const SizedBox(height: 8),
              const Text('Export sends one .zip (folders per class + labels.csv). Share it to Google Drive or upload it in the project chat; '
                  'it is added to training as-is.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
    );
  }
}
