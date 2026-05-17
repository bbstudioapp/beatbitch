import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/career_session_generator.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

/// Tests de la **surcharge isolée** (Phase 3) côté générateur : un (et un seul)
/// axe pilotant est poussé au-dessus de son `comfort` par séance, exposé sur
/// `CareerGenerationResult.overloadAxis` ; un axe figé sur un fail en est
/// exclu (verrou §6) ; `motion_streak.comfort` remplace le mur fixe 60 s.

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

CapabilityAxisState _s(double v, {double sr = 0.5}) =>
    CapabilityAxisState(best: v, comfort: v, successRate: sr);

CareerGenerationResult _gen(
  int seed, {
  int level = 14,
  CapabilityProfile? profile,
  Map<CapabilityAxis, double> ceilings = const {},
  Set<UnlockKey>? unlocks,
}) =>
    CareerSessionGenerator(seed: seed).generate(
      level: level,
      bank: _bank(),
      includeHand: true,
      humiliationCareer: 100.0,
      unlockedKeys: unlocks ?? _allUnlocks,
      capability: CapabilityInputs(
        profile: profile,
        sessionCeilings: ceilings,
      ),
    );

void main() {
  test(
      'un seul axe surchargé par séance, exposé sur le résultat ; aucun sans '
      'profil exploitable', () {
    final profile = CapabilityProfile({
      CapabilityAxis.rhythmDepthMax: _s(Position.throat.index.toDouble()),
      CapabilityAxis.holdFullStreak: _s(25),
      CapabilityAxis.holdThroatStreak: _s(30),
      CapabilityAxis.gorgeApneeStreak: _s(24),
      CapabilityAxis.gorgeEngagementStreak: _s(35),
      CapabilityAxis.rhythmBpmCeilShallow: _s(100),
      CapabilityAxis.rhythmBpmCeilThroat: _s(90),
      CapabilityAxis.rhythmBpmCeilFull: _s(80),
      CapabilityAxis.rhythmMotionStreak: _s(45),
      CapabilityAxis.biffleStreak: _s(30),
      CapabilityAxis.biffleBpmMax: _s(90),
      CapabilityAxis.noswallowStreak: _s(120),
      CapabilityAxis.gorgeCrossingsBpmThroat: _s(90),
      CapabilityAxis.gorgeCrossingsBpmFull: _s(80),
    });
    for (final seed in [1, 7, 42, 99, 256]) {
      final r = _gen(seed, profile: profile);
      expect(r.overloadAxis, isNotNull, reason: 'seed=$seed');
    }
    // Sans profil / profil vide → aucun axe surchargé (= comportement Phase 2).
    expect(_gen(42).overloadAxis, isNull);
    expect(_gen(42, profile: const CapabilityProfile({})).overloadAxis, isNull);
  });

  test(
      'l\'axe surchargé dépasse son comfort (entre comfort et comfort × '
      'kSurchargeMax) ; les autres pilotants restent strictement clampés', () {
    const cHoldFull = 25.0;
    const cHoldThroat = 18.0;
    const cBpmFull = 80.0;
    // holdFull confiant (sr 0.9) → toujours désigné axe surchargé ; les autres
    // axes sont présents (pour vérifier qu'ils restent clampés) mais peu
    // prioritaires (sr 0.1).
    final profile = CapabilityProfile({
      CapabilityAxis.holdFullStreak: _s(cHoldFull, sr: 0.9),
      CapabilityAxis.holdThroatStreak: _s(cHoldThroat, sr: 0.1),
      CapabilityAxis.gorgeApneeStreak:
          _s(60, sr: 0.1), // assez grand : ne bride pas holdFull
      CapabilityAxis.rhythmBpmCeilFull: _s(cBpmFull, sr: 0.1),
    });
    final hardCap = (cHoldFull * CapabilityRegulator.kSurchargeMax).ceil();
    var sawOverloadedHoldFull = false;
    for (final seed in [1, 7, 42, 99, 256, 1000]) {
      final r = _gen(seed, profile: profile);
      expect(r.overloadAxis, CapabilityAxis.holdFullStreak,
          reason: 'seed=$seed');
      for (final s in r.session.steps) {
        final held = s.to ?? s.from;
        if (s.mode == SessionMode.hold || s.mode == SessionMode.beg) {
          if (held == Position.full) {
            final dur = s.duration ?? 0;
            expect(dur, lessThanOrEqualTo(hardCap),
                reason: 'seed=$seed hold full $dur s > comfort surchargé max');
            if (dur > cHoldFull) sawOverloadedHoldFull = true;
          } else if (held == Position.throat) {
            // axe non surchargé → borne stricte au comfort.
            expect(s.duration ?? 0, lessThanOrEqualTo(cHoldThroat.ceil()),
                reason: 'seed=$seed hold throat ${s.duration} s > comfort '
                    '$cHoldThroat (non surchargé)');
          }
        }
        if (s.mode == SessionMode.rhythm &&
            s.to == Position.full &&
            s.bpm != null) {
          expect(s.bpm, lessThanOrEqualTo(cBpmFull.ceil()),
              reason: 'seed=$seed rhythm full bpm ${s.bpm} > comfort '
                  '$cBpmFull (non surchargé)');
        }
      }
    }
    expect(sawOverloadedHoldFull, isTrue,
        reason: 'le hold full final doit dépasser le comfort 25 s quand '
            'holdFull est l\'axe surchargé');
  });

  test(
      'un axe figé sur un fail (sessionCeiling) n\'est jamais l\'axe surchargé '
      '(verrou §6)', () {
    final profile = CapabilityProfile({
      CapabilityAxis.holdFullStreak: _s(25),
      CapabilityAxis.gorgeApneeStreak: _s(24),
    });
    for (final seed in List.generate(15, (i) => i)) {
      // holdFull verrouillé → seul gorgeApnee reste candidat.
      expect(
          _gen(seed, profile: profile, ceilings: const {
            CapabilityAxis.holdFullStreak: 5,
          }).overloadAxis,
          CapabilityAxis.gorgeApneeStreak);
      // gorgeApnee verrouillé → seul holdFull reste candidat.
      expect(
          _gen(seed, profile: profile, ceilings: const {
            CapabilityAxis.gorgeApneeStreak: 5,
          }).overloadAxis,
          CapabilityAxis.holdFullStreak);
      // les deux verrouillés → plus aucun candidat.
      expect(
          _gen(seed, profile: profile, ceilings: const {
            CapabilityAxis.holdFullStreak: 5,
            CapabilityAxis.gorgeApneeStreak: 5,
          }).overloadAxis,
          isNull);
    }
  });

  test(
      'motion_streak : un comfort bas écourte le rythme du main loop ; un '
      'comfort haut le laisse filer (à seed égal)', () {
    // À seed égal, la divergence ne vient que du cap de chaîne rythme : avec un
    // `motion_streak.comfort` bas le main loop alterne plus tôt, avec un comfort
    // haut il enchaîne. On mesure le total de secondes de rythme du main loop,
    // borné en excluant la zone finish (boosts / final) où les chaînes ne
    // passent pas par `_capRhythmConsecutive`. Le total bas doit, au moins
    // parfois, être strictement inférieur au total haut.
    CapabilityProfile p(double motion) =>
        CapabilityProfile({CapabilityAxis.rhythmMotionStreak: _s(motion)});
    int mainLoopRhythmSeconds(CareerGenerationResult r) {
      final finishStart = r.session.finalStepTime ?? r.session.durationSeconds;
      var total = 0;
      for (final s in r.session.steps) {
        if (s.isTextOnly || s.mode != SessionMode.rhythm) continue;
        if (s.time >= finishStart - 90) continue; // zone finish/boosts exclue
        total += s.duration ?? 0;
      }
      return total;
    }

    var sawShorter = false;
    for (final seed in [
      1,
      7,
      11,
      42,
      64,
      99,
      128,
      256,
      512,
      1000,
      2048,
      4242
    ]) {
      final low = mainLoopRhythmSeconds(_gen(seed, profile: p(26)));
      final high = mainLoopRhythmSeconds(_gen(seed, profile: p(200)));
      if (low < high) sawShorter = true;
    }
    expect(sawShorter, isTrue,
        reason: 'un cap motion bas doit écourter le rythme du main loop au '
            'moins une fois — sinon `motion_streak.comfort` n\'est pas '
            'consommé par `_canChainRhythm`');
  });

  test(
      'Phase 4 — phrase « attempt » injectée comme texte du step #0 quand le dé '
      '∝ niveau gagne ; jamais aux niv ≤ 4 / quickie / openingPhrase imposée',
      () {
    // Un seul axe consolidé → `overloadAxis == holdFullStreak` à chaque séance.
    final profile = CapabilityProfile({
      CapabilityAxis.holdFullStreak: _s(25, sr: 0.5),
    });
    final coachBank = CoachCatalog.defaults.first
        .withPhrases(const CoachPhrasePack(progressPhrases: {
          'hold.full.streak': {
            'attempt': [PhraseEntry(text: 'ATTEMPT_HF')],
          },
        }))
        .toPhraseBank(fallback: _bank());

    String step0(int seed,
        {int level = 14, bool quickie = false, String? openingPhrase}) {
      final r = CareerSessionGenerator(seed: seed).generate(
        level: level,
        bank: coachBank,
        includeHand: true,
        quickie: quickie,
        openingPhrase: openingPhrase,
        humiliationCareer: 100.0,
        unlockedKeys: _allUnlocks,
        capability: CapabilityInputs(profile: profile),
      );
      return r.session.steps
          .firstWhere((s) => !s.isTextOnly && s.time == 0)
          .text;
    }

    final seeds = List.generate(40, (i) => i);
    // Niveau élevé (chance ~40 %) : la phrase attempt apparaît au moins une
    // fois, et certaines séances gardent l'ouverture générique ('s').
    final step0sHigh = seeds.map(step0).toList();
    expect(step0sHigh.where((t) => t == 'ATTEMPT_HF'), isNotEmpty,
        reason: 'la phrase attempt doit apparaître au moins une fois');
    expect(step0sHigh.where((t) => t != 'ATTEMPT_HF'), isNotEmpty,
        reason: 'toutes les séances ne posent pas la phrase attempt');
    // Niveau ≤ 4 : chance 0 → jamais.
    for (final s in seeds) {
      expect(step0(s, level: 4), isNot('ATTEMPT_HF'), reason: 'niv 4 seed=$s');
    }
    // Quickie : step #0 dramaturgique préservé → jamais la phrase attempt.
    for (final s in seeds) {
      expect(step0(s, quickie: true), isNot('ATTEMPT_HF'),
          reason: 'quickie seed=$s');
    }
    // `openingPhrase` imposée (Supplier / encore) → jamais la phrase attempt.
    for (final s in seeds) {
      expect(step0(s, openingPhrase: 'OPENING'), 'OPENING',
          reason: 'openingPhrase seed=$s');
    }
  });
}
