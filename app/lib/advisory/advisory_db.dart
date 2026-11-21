// Offline, curated advisory database (assets/advisory_<lang>.json), built by
// ml/build_advisory_db.py (Telugu) and ml/build_i18n.py (English, Hindi) from
// TNAU / ICAR extension guidance. Field names keep the _te suffix but hold the
// text of the loaded language.
import 'dart:convert';

import 'package:flutter/services.dart';

import '../l10n.dart';

class AdvisoryEntry {
  final Map<String, dynamic> j;
  AdvisoryEntry(this.j);
  String get cropTe => j['crop_te'];
  String get cropEn => j['crop_en'];
  String get diseaseTe => j['disease_te'];
  String get diseaseEn => j['disease_en'];
  String get type => j['type'];
  String get symptomsTe => j['symptoms_te'];
  String get causeTe => j['cause_te'];
  String get source => j['source'];
  bool get highRisk => j['high_risk'] == true;
  bool get healthy => type == 'healthy';
  List<String> stepsFor(String level) =>
      level == 'none' ? const [] : List<String>.from(j['steps'][level] ?? const []);
  List<String> get prevention => List<String>.from(j['prevention_te']);
  String get fertiliserIrrigation => j['fertiliser_irrigation_te'];
  String get postHarvest => j['post_harvest_te'];
  List<Spray> spraysFor(String level) => level == 'none'
      ? const []
      : [for (final m in (j['sprays'][level] as List)) Spray(Map<String, dynamic>.from(m))];
}

class Spray {
  final Map<String, dynamic> j;
  Spray(this.j);
  String get nameTe => j['name_te'];
  String get nameEn => j['name_en'];
  double get dosePerL => (j['dose_per_l'] as num).toDouble();
  String get unit => j['unit']; // g | ml
  String get kind => j['kind'];
  bool get liquid => j['form'] == 'liquid';
  String doseFor(double litres, [L l = const L(Lang.te)]) {
    final v = dosePerL * litres;
    return '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${unit == 'g' ? l.gram : l.ml}';
  }
}

class CropInfo {
  final String key, te, en;
  final List<String> labels;
  CropInfo(this.key, this.te, this.en, this.labels);
}

class AdvisoryDb {
  late Map<String, dynamic> _db;
  L l = const L(Lang.te);
  Future<void> load([Lang lang = Lang.te]) async {
    _db = jsonDecode(await rootBundle.loadString('assets/advisory_${lang.code}.json'));
    l = L(lang);
  }

  AdvisoryEntry entry(String label) => AdvisoryEntry(_db['classes'][label]);
  String severityTe(String level) => level == 'none' ? l.healthyLevel : _db['severity_te'][level];
  List<String> genericSteps(String level) =>
      level == 'none' ? const [] : List<String>.from(_db['severity_generic'][level]);
  String get verifyNote => _db['verify_note_te'];
  /// Every crop and problem name in the loaded language, for the LLM name guardrail.
  Set<String> get allNames => {
        for (final c in (_db['classes'] as Map<String, dynamic>).values) ...[c['disease_te'] as String, c['crop_te'] as String],
      };
  List<CropInfo> get crops => [
        for (final e in (_db['crops'] as Map<String, dynamic>).entries)
          CropInfo(e.key, e.value['te'], e.value['en'], List<String>.from(e.value['labels']))
      ];
  List<List<String>> get howToSpray =>
      [for (final r in _db['how_to_spray_te'] as List) List<String>.from(r)];
  List<(String, double)> get tankSizes =>
      [for (final r in _db['tank_sizes'] as List) (r[0] as String, (r[1] as num).toDouble())];

  /// Deterministic advice in the loaded language, used as the fallback when the LLM is not
  /// installed or its output fails validation. Also the "verified steps" card.
  List<String> templateAdvice(AdvisoryEntry e, String level) {
    if (e.healthy) {
      return [l.healthyLeaf(e.cropTe), ...e.prevention, e.fertiliserIrrigation];
    }
    return [
      '${e.cropTe}: ${e.diseaseTe} — ${l.severity(severityTe(level))}.',
      '${l.cause}: ${e.causeTe}',
      ...genericSteps(level),
      ...e.stepsFor(level),
      '${l.prevention}: ${e.prevention.join(' ')}',
    ];
  }
}
