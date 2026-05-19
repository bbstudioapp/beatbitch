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

  // Unlocks « scalaires » : ils débloquent un palier de durée ou de BPM.
  // Garde-fou : la séquence de la milestone qui les accorde doit faire
  // *atteindre* (ou *dépasser*) le seuil que l'unlock ouvre. Sinon le
  // déblocage représente quelque chose que la joueuse n'a jamais éprouvé
  // — c'est l'audit qui motive l'ajout de ce test.
  //
  // Convention :
  // - `mustReach` : l'unlock ouvre un palier qui *va jusqu'à* `value`
  //   (la séquence doit contenir un step ≥ value pour le montrer).
  // - `mustExceed` : l'unlock ouvre un palier *au-delà* de `value`
  //   (la séquence doit contenir un step > value pour valider le saut).
  //
  // Le `field` discrimine la grandeur : `duration` ou `bpm`. Le `match`
  // filtre les steps pertinents (mode + position le cas échéant).
  final scalarUnlocks = <String, _ScalarUnlockSpec>{
    'throat_hold_short': const _ScalarUnlockSpec(
      mode: 'hold',
      position: 'throat',
      field: 'duration',
      mustReach: 10,
    ),
    'throat_hold_long': const _ScalarUnlockSpec(
      mode: 'hold',
      position: 'throat',
      field: 'duration',
      mustExceed: 10,
    ),
    'full_hold_short': const _ScalarUnlockSpec(
      mode: 'hold',
      position: 'full',
      field: 'duration',
      mustReach: 10,
    ),
    'full_hold_long': const _ScalarUnlockSpec(
      mode: 'hold',
      position: 'full',
      field: 'duration',
      mustExceed: 10,
    ),
    'hold_mid_short': const _ScalarUnlockSpec(
      mode: 'hold',
      position: 'mid',
      field: 'duration',
      mustReach: 10,
    ),
    'biffle_basic': const _ScalarUnlockSpec(
      mode: 'biffle',
      field: 'bpm',
      mustReach: 100,
    ),
    'biffle_fast': const _ScalarUnlockSpec(
      mode: 'biffle',
      field: 'bpm',
      mustExceed: 100,
    ),
    'rhythm_extreme': const _ScalarUnlockSpec(
      mode: 'rhythm',
      field: 'bpm',
      mustReach: 160,
    ),
    'rhythm_head_mid_sustained': const _ScalarUnlockSpec(
      mode: 'rhythm',
      field: 'duration',
      mustExceed: 60,
    ),
  };

  test(
      'chaque unlock scalaire atteint son seuil dans la milestone qui le débloque',
      () {
    for (final entry in scalarUnlocks.entries) {
      final serialized = entry.key;
      final spec = entry.value;
      final granterIds = granters[serialized];
      expect(granterIds, isNotNull,
          reason: 'unlock "$serialized" n\'est accordé par aucune milestone');
      expect(granterIds!, hasLength(1),
          reason: 'unlock scalaire "$serialized" accordé par '
              '${granterIds.length} milestones — un seul producteur attendu');
      final mid = granterIds.single;
      final milestone = milestones.firstWhere((m) => m['id'] == mid);
      final steps =
          (milestone['sequence'] as List).cast<Map<String, dynamic>>();
      final matching = steps.where((s) {
        if (s['mode'] != spec.mode) return false;
        if (spec.position != null && s['to'] != spec.position) return false;
        return s[spec.field] is num;
      });
      expect(matching, isNotEmpty,
          reason: 'milestone "$mid" : aucun step ne matche '
              '(mode=${spec.mode}${spec.position != null ? ', to=${spec.position}' : ''}, '
              'field=${spec.field}) — vérifier la séquence');
      final maxValue = matching
          .map((s) => (s[spec.field] as num).toDouble())
          .reduce((a, b) => a > b ? a : b);
      if (spec.mustReach != null) {
        expect(maxValue, greaterThanOrEqualTo(spec.mustReach!),
            reason:
                'milestone "$mid" débloque "$serialized" qui ouvre un palier '
                'jusqu\'à ${spec.mustReach} ${spec.field} ; la séquence ne va '
                'que jusqu\'à $maxValue. Monter la séquence ou descendre le seuil '
                'côté générateur.');
      }
      if (spec.mustExceed != null) {
        expect(maxValue, greaterThan(spec.mustExceed!.toDouble()),
            reason:
                'milestone "$mid" débloque "$serialized" qui ouvre un palier '
                'au-delà de ${spec.mustExceed} ${spec.field} ; la séquence ne va '
                'que jusqu\'à $maxValue. La milestone doit dépasser le seuil '
                'qu\'elle débloque, sinon l\'unlock ne représente rien.');
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

/// Spec d'un unlock scalaire à auditer dans le test ci-dessus. `mode`
/// (et `position` optionnelle) filtrent les steps pertinents ; `field`
/// désigne la grandeur lue (`duration` ou `bpm`). Exactement un de
/// [mustReach] / [mustExceed] doit être fourni.
class _ScalarUnlockSpec {
  final String mode;
  final String? position;
  final String field;
  final num? mustReach;
  final num? mustExceed;

  const _ScalarUnlockSpec({
    required this.mode,
    this.position,
    required this.field,
    this.mustReach,
    this.mustExceed,
  });
}
