import 'dart:convert';
import 'dart:io';

import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:flutter_test/flutter_test.dart';

/// Garde-fous structurels sur le couplage milestone → unlock (cf. doc de
/// `UnlockKey`) : chaque milestone du catalogue accorde **exactement une**
/// `UnlockKey`, chaque `requires` se résout, aucun double-grant, et chaque
/// unlock accordé est consommé quelque part (gate de step / runtime / filtre
/// de contenu / prérequis d'une autre milestone). Empêche de re-créer des
/// milestones « décoratives » dont le déblocage ne fait rien.
///
/// Lit directement les assets/source files (cwd = racine du package en
/// `flutter test`) — pas de chargement Flutter.
void main() {
  // Exception déclarée : aucune pour l'instant. `intro_basics` accorde la
  // clé `basics`, consommée comme prérequis des milestones racines.
  const milestonesWithoutSingleUnlock = <String>{};

  final repoRoot = Directory.current.path;
  final milestonesJson = jsonDecode(
    File('$repoRoot/assets/career/milestones.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final milestones =
      (milestonesJson['milestones'] as List).cast<Map<String, dynamic>>();

  // unlock serialisé -> liste des milestones qui l'accordent
  final granters = <String, List<String>>{};
  for (final m in milestones) {
    for (final u in (m['unlocks'] as List? ?? const []).cast<String>()) {
      granters.putIfAbsent(u, () => []).add(m['id'] as String);
    }
  }

  test('chaque milestone accorde exactement 1 unlock', () {
    for (final m in milestones) {
      final id = m['id'] as String;
      if (milestonesWithoutSingleUnlock.contains(id)) continue;
      final unlocks = (m['unlocks'] as List? ?? const []).cast<String>();
      expect(unlocks, hasLength(1),
          reason: 'milestone "$id" accorde ${unlocks.length} unlock(s) '
              '(${unlocks.join(', ')}) — règle : 1 milestone → 1 unlock');
    }
  });

  test('chaque unlock accordé est une UnlockKey valide', () {
    for (final entry in granters.entries) {
      expect(UnlockKey.fromString(entry.key), isNotNull,
          reason: 'unlock "${entry.key}" (accordé par ${entry.value}) '
              "ne correspond à aucune UnlockKey");
    }
  });

  test('aucun unlock accordé par deux milestones', () {
    final dups = {
      for (final e in granters.entries)
        if (e.value.length > 1) e.key: e.value
    };
    expect(dups, isEmpty,
        reason: 'unlocks accordés en double : $dups — chaque unlock doit '
            'avoir un producteur unique');
  });

  test('chaque "requires" se résout vers une milestone du catalogue', () {
    for (final m in milestones) {
      for (final r in (m['requires'] as List? ?? const []).cast<String>()) {
        expect(granters.containsKey(r), isTrue,
            reason: 'milestone "${m['id']}" requiert "$r" qu\'aucune '
                'milestone n\'accorde');
      }
    }
  });

  test('chaque axis de requiresCapability correspond à un CapabilityAxis', () {
    final validKeys = {
      for (final a in CapabilityAxis.values) a.storageKey,
    };
    for (final m in milestones) {
      final reqs = (m['requiresCapability'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final r in reqs) {
        final axis = r['axis'] as String?;
        final min = r['min'];
        expect(axis, isNotNull,
            reason: 'milestone "${m['id']}" : requiresCapability sans axis');
        expect(validKeys.contains(axis), isTrue,
            reason: 'milestone "${m['id']}" : axis "$axis" inconnu — vérifier '
                'CapabilityAxis.storageKey');
        expect(min, isA<num>(),
            reason:
                'milestone "${m['id']}" : min de "$axis" doit être un nombre');
      }
    }
  });

  test('chaque unlock accordé est consommé quelque part', () {
    // Source Dart à scanner pour les références `UnlockKey.<name>`. On
    // exclut le debug screen (qui itère `UnlockKey.values`) et l'enum
    // lui-même (le switch `serialized` cite tout).
    final libDir = Directory('$repoRoot/lib');
    final dartSrc = StringBuffer();
    for (final f in libDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('career_scenario_debug_screen.dart')) continue;
      if (f.path.endsWith('unlock_key.dart')) continue;
      dartSrc.write(f.readAsStringSync());
    }
    final src = dartSrc.toString();

    // Filtres de contenu (`requires_unlock`) dans les commentaires aléatoires.
    final randomComments =
        File('$repoRoot/assets/random_comments.json').readAsStringSync();

    // Prérequis `requires` des milestones (un unlock peut n'être consommé
    // que comme garde-fou de candidature d'une autre milestone — ex `basics`).
    final requiredByMilestones = <String>{
      for (final m in milestones)
        ...(m['requires'] as List? ?? const []).cast<String>()
    };

    for (final serialized in granters.keys) {
      final key = UnlockKey.fromString(serialized)!;
      final consumed = src.contains('UnlockKey.${key.name}') ||
          randomComments.contains('"$serialized"') ||
          requiredByMilestones.contains(serialized);
      expect(consumed, isTrue,
          reason: 'unlock "$serialized" (accordé par ${granters[serialized]}) '
              "n'est consommé nulle part : ni gate de step / runtime "
              '(UnlockKey.${key.name} dans lib/), ni filtre de contenu '
              '(requires_unlock dans random_comments.json), ni prérequis '
              "d'une autre milestone");
    }
  });
}
