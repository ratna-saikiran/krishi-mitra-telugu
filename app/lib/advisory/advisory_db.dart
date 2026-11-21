// Offline, curated advisory database (assets/advisory_te.json), built by
// ml/build_advisory_db.py from TNAU / ICAR extension guidance.
import 'dart:convert';

import 'package:flutter/services.dart';

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
  String get unitTe => unit == 'g' ? 'గ్రా' : 'మి.లీ';
  String get kind => j['kind'];
  bool get liquid => j['form'] == 'liquid';
  String doseFor(double litres) {
    final v = dosePerL * litres;
    return '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} $unitTe';
  }
}

class CropInfo {
  final String key, te, en;
  final List<String> labels;
  CropInfo(this.key, this.te, this.en, this.labels);
}

class AdvisoryDb {
  late final Map<String, dynamic> _db;
  Future<void> load() async {
    _db = jsonDecode(await rootBundle.loadString('assets/advisory_te.json'));
  }

  AdvisoryEntry entry(String label) => AdvisoryEntry(_db['classes'][label]);
  String severityTe(String level) => level == 'none' ? 'ఆరోగ్యకరం' : _db['severity_te'][level];
  List<String> genericSteps(String level) =>
      level == 'none' ? const [] : List<String>.from(_db['severity_generic'][level]);
  String get verifyNote => _db['verify_note_te'];
  /// Every Telugu crop and problem name, for the LLM name guardrail.
  Set<String> get allNamesTe => {
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

  /// Deterministic Telugu advice, used as the fallback when the LLM is not
  /// installed or its output fails validation. Also the "verified steps" card.
  List<String> templateAdvice(AdvisoryEntry e, String level) {
    if (e.healthy) {
      return ['మీ ${e.cropTe} ఆకు ఆరోగ్యంగా ఉంది.', ...e.prevention, e.fertiliserIrrigation];
    }
    return [
      '${e.cropTe}: ${e.diseaseTe} — తీవ్రత: ${severityTe(level)}.',
      'కారణం: ${e.causeTe}',
      ...genericSteps(level),
      ...e.stepsFor(level),
      'నివారణ: ${e.prevention.join(' ')}',
    ];
  }
}
