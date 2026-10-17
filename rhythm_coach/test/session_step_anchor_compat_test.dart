import 'dart:convert';
import 'dart:io';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preuve de compatibilité du chantier aimant (étape 3, cf. rapport
/// chantier-aimant-étape-3) : aucun step des 20 fichiers de
/// `assets/sessions/` ni des 37 paliers de `assets/career/milestones.json`
/// ne porte encore les clés `anchor`/`ratio`. Leur absence doit retomber sur
/// les valeurs par défaut qui reproduisent le geste d'avant le chantier
/// (`BeatAnchor.none`, `ratio` 1) — c'est par cette absence que la
/// compatibilité se règle, pas par un code de migration.
///
/// Lit directement les fichiers d'assets (cwd = racine du package en
/// `flutter test`), comme `test/milestone_unlock_invariants_test.dart`.
void main() {
  final repoRoot = Directory.current.path;

  void expectUnanchored(SessionStep step, String origin) {
    expect(step.anchor, BeatAnchor.none,
        reason: '$origin : anchor devrait défaut à none (JSON sans la clé)');
    expect(step.ratio, 1,
        reason: '$origin : ratio devrait défaut à 1 (JSON sans la clé)');
    final chain = step.chainAction;
    if (chain != null) expectUnanchored(chain, '$origin > chainAction');
  }

  test(
      'assets/sessions/*.json : tous les steps rejouent le geste d\'avant '
      'le chantier aimant', () {
    final dir = Directory('$repoRoot/assets/sessions');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(20),
        reason: 'la surface couverte ne doit pas rétrécir en silence');

    var total = 0;
    for (final file in files) {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final rawSteps = (data['steps'] as List).cast<Map<String, dynamic>>();
      for (final raw in rawSteps) {
        final step = SessionStep.fromJson(raw);
        expectUnanchored(step, '${file.path} t=${step.time}');
        total++;
      }
    }
    expect(total, greaterThanOrEqualTo(430),
        reason: 'la surface couverte ne doit pas rétrécir en silence');
  });

  test(
      'assets/career/milestones.json : tous les steps des paliers rejouent '
      'le geste d\'avant le chantier aimant', () {
    final data = jsonDecode(
      File('$repoRoot/assets/career/milestones.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final milestones =
        (data['milestones'] as List).cast<Map<String, dynamic>>();
    expect(milestones.length, greaterThanOrEqualTo(37),
        reason: 'la surface couverte ne doit pas rétrécir en silence');

    var total = 0;
    for (final m in milestones) {
      final id = m['id'] as String;
      final rawSteps =
          (m['sequence'] as List? ?? const []).cast<Map<String, dynamic>>();
      for (final raw in rawSteps) {
        final step = SessionStep.fromJson(raw);
        expectUnanchored(step, '$id t=${step.time}');
        total++;
      }
    }
    expect(total, greaterThanOrEqualTo(202),
        reason: 'la surface couverte ne doit pas rétrécir en silence');
  });

  test(
      'assets/punishments*.json : tous les steps rejouent le geste d\'avant '
      'le chantier aimant', () {
    final files = Directory('$repoRoot/assets')
        .listSync()
        .whereType<File>()
        .where(
            (f) => RegExp(r'punishments(_[a-z]{2})?\.json$').hasMatch(f.path))
        .toList();
    expect(files.length, greaterThanOrEqualTo(4),
        reason: 'la surface couverte ne doit pas rétrécir en silence');

    var total = 0;
    for (final file in files) {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final raw
          in (data['punishments'] as List).cast<Map<String, dynamic>>()) {
        for (final rawStep
            in (raw['steps'] as List).cast<Map<String, dynamic>>()) {
          final step = SessionStep.fromJson(rawStep);
          expectUnanchored(step, '${file.path} ${raw['id']} t=${step.time}');
          total++;
        }
      }
    }
    expect(total, greaterThanOrEqualTo(76),
        reason: 'la surface couverte ne doit pas rétrécir en silence');
  });

  // Les fichiers JSON règlent leur compatibilité par l'absence des clés, donc
  // par les replis de `fromJson`. Tout le reste du code construit un
  // `SessionStep` sans les nommer et dépend du défaut du constructeur, que
  // `fromJson` n'emprunte jamais : sans cette sonde, le renverser ne casse
  // aucun test.
  test('le défaut du constructeur reproduit lui aussi le geste d\'avant', () {
    const step = SessionStep(time: 0, mode: SessionMode.rhythm);
    expect(step.anchor, BeatAnchor.none);
    expect(step.ratio, 1);
  });
}
