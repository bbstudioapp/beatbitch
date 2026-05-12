import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/career_session_generator.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

/// Tests de la **Phase 5** — punitions générées & bornées (§7 de la spec).
/// On vérifie :
/// 1. Sélection « max humiliation qui passe » sur la palette hardcodée
///    (parité avec `_pickFinal`).
/// 2. `sessionCeilings` bornent réellement la durée des holds.
/// 3. `comfort` borne réellement les BPM rhythm.
/// 4. Fallback en escalier (`last_resort_rhythm` → `hand_fallback`).
/// 5. Toggle `includeHand` exclut les compos biffle.
/// 6. Forme du `Punishment` retourné (steps en ordre, time monotone,
///    durée totale cohérente avec la somme des steps).

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'boost': _p(['b']),
            'finale': _p(['f']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

final Set<UnlockKey> _allUnlocks = UnlockKey.values.toSet();

/// Profil où `best == comfort` pour chaque axe fourni — modèle Phase 1/2.
CapabilityProfile _profile(Map<CapabilityAxis, double> comforts) =>
    CapabilityProfile({
      for (final e in comforts.entries)
        e.key: CapabilityAxisState(best: e.value, comfort: e.value),
    });

/// Wrapper minimal autour de `generatePunishment` — tous les params utiles
/// sont exposés, les autres ont un default raisonnable.
({CareerSessionGenerator gen, dynamic punishment}) _gen(
  int seed, {
  required double humilCap,
  CapabilityProfile? profile,
  Map<CapabilityAxis, double> ceilings = const {},
  Set<UnlockKey>? unlocks,
  bool includeHand = true,
  int level = 14,
}) {
  final g = CareerSessionGenerator(seed: seed);
  final p = g.generatePunishment(
    level: level,
    bank: _bank(),
    unlockedKeys: unlocks ?? _allUnlocks,
    capabilityProfile: profile,
    capabilitySessionCeilings: ceilings,
    humiliationCareer: humilCap,
    humiliationSession: 0.0,
    includeHand: includeHand,
  );
  return (gen: g, punishment: p);
}

void main() {
  test('sélection max humil : humil 13 → biffle_burst (seul valide à req 13)',
      () {
    final r = _gen(1, humilCap: 13.0);
    expect(r.punishment.id, 'biffle_burst');
  });

  test(
      'sélection max humil : humil 100 → deep_hold_chain (req 20, max palette)',
      () {
    final r = _gen(1, humilCap: 100.0);
    expect(r.punishment.id, 'deep_hold_chain');
  });

  test('sélection max humil : humil 17 → slow_torture (req 16 valide, 18+ non)',
      () {
    // Ordre des req : 13 (biffle) < 14 (crossings) < 16 (slow) < 18 (throat)
    //   < 20 (deep_hold). À humilCap=17, seuls les ≤ 16 passent ; le plus
    //   humiliant valide est `slow_torture` (req 16).
    final r = _gen(1, humilCap: 17.0);
    expect(r.punishment.id, 'slow_torture');
  });

  test('sessionCeilings bornent la durée du hold full dans deep_hold_chain',
      () {
    // En carrière, le profil est toujours fourni (cf.
    // `_generateCareerPunishmentOrNull`). Profil vide + ceiling = 5s sur hold
    // full : `_clampToCapability` consulte `_capabilityCapFor` qui renvoie le
    // ceiling (comfort null). La compo `deep_hold_chain` contient un hold
    // full de 12s qui doit être tronqué à 5s.
    final ceilings = {CapabilityAxis.holdFullStreak: 5.0};
    final r = _gen(1,
        humilCap: 100.0, profile: _profile(const {}), ceilings: ceilings);
    expect(r.punishment.id, 'deep_hold_chain');
    final steps = r.punishment.steps as List<SessionStep>;
    final holdFull = steps.firstWhere(
      (s) => s.mode == SessionMode.hold && s.to == Position.full,
    );
    expect(holdFull.duration, lessThanOrEqualTo(5));
  });

  test('comfort borne le BPM rhythm dans throat_relentless', () {
    // Profil avec comfort `rhythmBpmCeilFull` = 60. La compo `throat_relentless`
    // (rhythm throat→full BPM 100) doit être bornée à 60.
    final profile = _profile({
      CapabilityAxis.rhythmBpmCeilFull: 60.0,
    });
    // humilCap=18 → seul throat_relentless (req 18) et compos < 18 passent.
    // On force la sélection sur throat_relentless en mettant humil exactement
    // 18 et en s'assurant que biffle/crossings/slow restent valides : la max
    // sera bien throat_relentless.
    final r = _gen(1, humilCap: 18.0, profile: profile);
    expect(r.punishment.id, 'throat_relentless');
    final steps = r.punishment.steps as List<SessionStep>;
    final rhythm = steps.firstWhere((s) => s.mode == SessionMode.rhythm);
    expect(rhythm.bpm, isNotNull);
    expect(rhythm.bpm!, lessThanOrEqualTo(60));
  });

  test(
      'fallback escalier : humil 5 → last_resort_rhythm (toutes compos req ≥ 13 échouent)',
      () {
    final r = _gen(1, humilCap: 5.0);
    expect(r.punishment.id, 'last_resort_rhythm');
  });

  test(
      'fallback ultime : humil 0 + rhythmMidBasic non débloqué → hand_fallback',
      () {
    // Sans `rhythmMidBasic`, `last_resort_rhythm` (rhythm head→mid) est
    // bloqué par `_isUnlocked` → on tombe sur le filet hand req 0.
    // On garde `handBasic` débloqué pour que le filet passe.
    final unlocks = {UnlockKey.handBasic};
    final r = _gen(1, humilCap: 0.0, unlocks: unlocks);
    expect(r.punishment.id, 'hand_fallback');
  });

  test('includeHand=false exclut biffle_burst de la palette principale', () {
    // À humilCap=13, normalement seul `biffle_burst` (req 13) passe et est
    // retenu. Avec `includeHand=false`, il est exclu → liste valide vide →
    // fallback escalier → `last_resort_rhythm` (req 5 ≤ 13).
    final r = _gen(1, humilCap: 13.0, includeHand: false);
    expect(r.punishment.id, 'last_resort_rhythm');
  });

  test('forme du Punishment : steps ordonnés, time monotone, durée cohérente',
      () {
    // Toutes les compos doivent produire une `Punishment` consommable par
    // `SessionController._runPunishment` (tick périodique qui applique les
    // steps par `time` croissant).
    for (final humil in [0.0, 5.0, 13.0, 17.0, 100.0]) {
      final r = _gen(1, humilCap: humil);
      final steps = r.punishment.steps as List<SessionStep>;
      expect(steps, isNotEmpty, reason: 'humil=$humil — pas de steps');
      // time monotone strict ou égalité (steps text-only à t=0 acceptés).
      var lastTime = -1;
      for (final s in steps) {
        expect(s.time, greaterThanOrEqualTo(lastTime),
            reason: 'humil=$humil — time non monotone');
        lastTime = s.time;
      }
      // Premier step à t=0 (amorce immédiate).
      expect(steps.first.time, 0,
          reason: 'humil=$humil — premier step pas à t=0');
      // Durée totale ≥ time du dernier step + duration éventuelle.
      final last = steps.last;
      final endOfLast = last.time + (last.duration ?? 0);
      expect(r.punishment.durationSeconds, greaterThanOrEqualTo(endOfLast),
          reason: 'humil=$humil — durée < fin du dernier step');
    }
  });

  test('phrases injectées : steps non-breath ont du texte tier hard du coach',
      () {
    final r = _gen(1, humilCap: 100.0);
    final steps = r.punishment.steps as List<SessionStep>;
    for (final s in steps) {
      if (s.mode == SessionMode.breath) {
        // breath = transition silencieuse côté générateur (le runner ne
        // parle pas sur les fenêtres respiration).
        continue;
      }
      expect(s.text, isNotEmpty,
          reason: 'step mode=${s.mode?.name} sans texte coach');
      // Le bank de test renvoie 'h' pour le tier 'hard'.
      expect(s.text, 'h');
    }
  });

  test(
      'overload axis : surcharge élargit le comfort mais reste bornée par ceiling',
      () {
    // Comfort `rhythmBpmCeilFull` = 60, axe surchargé = rhythmBpmCeilFull,
    // successRate moyenne (0.5). Le facteur de surcharge (1.03→1.15) reste
    // modeste → BPM rhythm reste ≤ ~70. Ceiling 50 prime même sur l'axe
    // surchargé (§6).
    const profile = CapabilityProfile({
      CapabilityAxis.rhythmBpmCeilFull:
          CapabilityAxisState(best: 60, comfort: 60, successRate: 0.5),
    });
    final r = _gen(
      1,
      humilCap: 18.0,
      profile: profile,
      ceilings: {CapabilityAxis.rhythmBpmCeilFull: 50.0},
    );
    expect(r.punishment.id, 'throat_relentless');
    final steps = r.punishment.steps as List<SessionStep>;
    final rhythm = steps.firstWhere((s) => s.mode == SessionMode.rhythm);
    expect(rhythm.bpm!, lessThanOrEqualTo(50),
        reason: 'sessionCeiling doit primer même sur l\'axe surchargé');
  });
}
