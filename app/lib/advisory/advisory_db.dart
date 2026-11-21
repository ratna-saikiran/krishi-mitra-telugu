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
