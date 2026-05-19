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
  // Convention : `mustReach` exige que la séquence aille **jusqu'à**
  // `value` (la séquence doit contenir un step ≥ value pour le montrer).
  // Le `field` discrimine la grandeur : `duration` ou `bpm`. Le `match`
  // filtre les steps pertinents (mode + position le cas échéant).
  //
  // Migration Phase 4 défis : `throat_hold_long`, `full_hold_long`,
  // `biffle_fast`, `rhythm_extreme`, `rhythm_head_mid_sustained` ne sont
  // plus accordés par milestone — ils tombent via défi (cf. spec § 6).
  // Pour les joueuses existantes les unlocks acquis restent en place ;
  // pour les nouvelles, le défi seul peut les acquitter. Exclus de cet
  // invariant. La variante `mustExceed` historique est retirée — tous les
  // unlocks scalaires « palier de dépassement » ont été migrés.
  final scalarUnlocks = <String, _ScalarUnlockSpec>{
    'throat_hold_short': const _ScalarUnlockSpec(
      mode: 'hold',
      position: 'throat',
      field: 'duration',
      mustReach: 10,
    ),
    'full_hold_short': const _ScalarUnlockSpec(
      mode: 'hold',
      position: 'full',
      field: 'duration',
      mustReach: 10,
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
  };

  /// Unlocks scalaires migrés vers le défi (Phase 4 défis). Ne sont plus
  /// accordés par milestone, donc absents de `granters`. On vérifie ici
  /// qu'ils n'apparaissent **pas** dans les `unlocks` d'aucune milestone
  /// (garde-fou contre une réintroduction accidentelle), et qu'ils
  /// restent consommés quelque part dans le code (sinon ils sont à
  /// retirer de l'enum aussi).
  const unlocksMigratedToChallenge = <String>{
    'throat_hold_long',
    'full_hold_long',
    'biffle_fast',
    'rhythm_extreme',
    'rhythm_head_mid_sustained',
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
      expect(maxValue, greaterThanOrEqualTo(spec.mustReach),
          reason:
              'milestone "$mid" débloque "$serialized" qui ouvre un palier '
              'jusqu\'à ${spec.mustReach} ${spec.field} ; la séquence ne va '
              'que jusqu\'à $maxValue. Monter la séquence ou descendre le seuil '
              'côté générateur.');
    }
  });

  test('unlocks migrés vers défi ne sont plus accordés par milestone', () {
    for (final u in unlocksMigratedToChallenge) {
      expect(granters.containsKey(u), isFalse,
          reason: 'unlock "$u" est marqué comme migré vers défi mais une '
              'milestone le produit encore (${granters[u]}) — Phase 4 défis');
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
/// désigne la grandeur lue (`duration` ou `bpm`) ; `mustReach` est le
/// seuil minimum que la séquence doit atteindre pour valider l'unlock.
class _ScalarUnlockSpec {
  final String mode;
  final String? position;
  final String field;
  final num mustReach;

  const _ScalarUnlockSpec({
    required this.mode,
    this.position,
    required this.field,
    required this.mustReach,
  });
}
