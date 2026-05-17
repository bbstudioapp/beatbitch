import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

/// Tests du **gating** : le générateur consomme un `CapabilityProfile`
/// (+ d'éventuels `sessionCeilings`) comme 2ᵉ enveloppe de difficulté — un
/// step n'est jouable que si profondeur / BPM / durée ne dépassent pas le
/// `comfort` de chaque axe pilotant, ni les plafonds figés sur un fail de la
/// session. `hand`/`lick`/`breath`/`freestyle` ne sont pas concernés.
///
/// Note Phase 3 : le générateur **surcharge un axe par séance** (`comfort ×
/// surcharge`, surcharge ≤ `kSurchargeMax`). On ne sait pas lequel ici (choix
/// pondéré interne), donc les bornes « durée/BPM » tolèrent ce surplus ; un
/// `sessionCeiling`, lui, prime *même* sur l'axe surchargé (verrou §6) et la
/// borne reste stricte. Le comportement précis de la surcharge est couvert par
/// `capability_overload_test.dart`.

/// Plafond toléré pour un axe potentiellement surchargé cette séance.
int _withSurcharge(num comfort) =>
    (comfort * CapabilityRegulator.kSurchargeMax).ceil();

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

/// Profil où `best == comfort` pour chaque axe fourni (= modèle Phase 1/2 :
/// `comfort` posé naïvement à `best`).
CapabilityProfile _profile(Map<CapabilityAxis, double> comforts) =>
    CapabilityProfile({
      for (final e in comforts.entries)
        e.key: CapabilityAxisState(best: e.value, comfort: e.value),
    });

CareerGenerationResult _gen(
  int seed, {
  int level = 14,
  CapabilityProfile? profile,
  Map<CapabilityAxis, double> ceilings = const {},
  bool includeHand = true,
}) =>
    CareerSessionGenerator(seed: seed).generate(
      level: level,
      bank: _bank(),
      includeHand: includeHand,
      humiliationCareer: 100.0,
      unlockedKeys: _allUnlocks,
      capability: CapabilityInputs(
        profile: profile,
        sessionCeilings: ceilings,
      ),
    );

void main() {
  test('profil vide ⇔ pas de profil — le générateur ne change rien', () {
    // Un profil sans aucune donnée (tous axes null) ne contraint rien : la
    // session générée doit être bit-à-bit identique à celle sans profil
    // (joueuse neuve = comportement actuel).
    List<SessionStep> steps(CapabilityProfile? p) =>
        _gen(42, profile: p).session.steps;
    final without = steps(null);
    final withEmpty = steps(_profile(const {}));
    expect(withEmpty.length, without.length);
    for (var i = 0; i < without.length; i++) {
      final a = without[i];
      final b = withEmpty[i];
      expect(
        [b.time, b.mode, b.from, b.to, b.bpm, b.bpmEnd, b.duration],
        [a.time, a.mode, a.from, a.to, a.bpm, a.bpmEnd, a.duration],
        reason: 'step $i diverge entre profil vide et pas de profil',
      );
    }
  });

  test('rhythmDepthMax borne la profondeur des steps rhythm', () {
    // Pré-condition : sans cap, niveau 14 + humil 100 produit bien des
    // rhythm throat/full.
    final wentDeep = [1, 7, 13].any((seed) => _gen(seed).session.steps.any(
        (s) =>
            s.mode == SessionMode.rhythm &&
            s.to != null &&
            s.to!.index >= Position.throat.index));
    expect(wentDeep, isTrue,
        reason: 'pré-condition : sans cap, des rhythm throat/full sont émis');

    // Avec un cap profondeur à `mid`, aucun step rhythm ne dépasse mid —
    // y compris les boosts du finish et le pré-finisher.
    final profile = _profile(
        {CapabilityAxis.rhythmDepthMax: Position.mid.index.toDouble()});
    for (final seed in [1, 7, 13, 42, 256]) {
      for (final s in _gen(seed, profile: profile).session.steps) {
        if (s.mode != SessionMode.rhythm || s.to == null) continue;
        expect(s.to!.index, lessThanOrEqualTo(Position.mid.index),
            reason: 'seed=$seed rhythm to=${s.to!.name} (t=${s.time}) dépasse '
                'le cap profondeur `mid`');
      }
    }
  });

  test(
      'holdThroatStreak / holdFullStreak / sessionCeilings bornent la durée '
      'des holds profonds', () {
    // Pré-condition : sans cap, niveau 14 + humil 100 produit un hold
    // throat ou full d'au moins 10 s (corps ou final).
    final hasLongDeepHold = [3, 11, 42].any((seed) => _gen(seed)
        .session
        .steps
        .any((s) =>
            (s.mode == SessionMode.hold || s.mode == SessionMode.beg) &&
            ((s.to ?? s.from) == Position.throat ||
                (s.to ?? s.from) == Position.full) &&
            (s.duration ?? 0) >= 10));
    expect(hasLongDeepHold, isTrue,
        reason: 'pré-condition : sans cap, des holds throat/full longs sont '
            'émis (corps ou apothéose)');

    final profile = _profile({
      CapabilityAxis.holdThroatStreak: 30.0,
      CapabilityAxis.holdFullStreak: 25.0,
    });
    const throatCeiling = 5.0; // plafond figé sur un fail — prime sur comfort
    for (final seed in [3, 11, 42, 77, 128]) {
      final r = _gen(seed,
          profile: profile,
          ceilings: const {CapabilityAxis.holdThroatStreak: throatCeiling});
      for (final s in r.session.steps) {
        if (s.mode != SessionMode.hold && s.mode != SessionMode.beg) continue;
        final held = s.to ?? s.from;
        final dur = s.duration ?? 0;
        if (held == Position.throat) {
          expect(dur, lessThanOrEqualTo(5),
              reason:
                  'seed=$seed ${s.mode!.name} throat $dur s (t=${s.time}) > '
                  'plafond session 5 s');
        } else if (held == Position.full) {
          expect(dur, lessThanOrEqualTo(_withSurcharge(25)),
              reason: 'seed=$seed ${s.mode!.name} full $dur s (t=${s.time}) > '
                  'comfort 25 s (+ surcharge éventuelle)');
        }
      }
      // Le step final (apothéose) est inclus dans la boucle : s'il s'agit
      // d'un hold throat/full, il a été tronqué comme les autres.
    }
  });

  test('rhythmBpmCeilShallow / biffleBpmMax bornent le BPM', () {
    // Pré-condition : sans cap, des rhythm `to ≤ mid` rapides (> 90 BPM) et
    // des biffles rapides (> 75 BPM) apparaissent.
    final fastShallow = [1, 7, 42].any((seed) => _gen(seed).session.steps.any(
        (s) =>
            s.mode == SessionMode.rhythm &&
            s.to != null &&
            s.to!.index <= Position.mid.index &&
            (s.bpm ?? 0) > 90));
    expect(fastShallow, isTrue,
        reason:
            'pré-condition : sans cap, des rhythm shallow > 90 BPM existent');
    final fastBiffle = [1, 7, 42, 64, 200].any((seed) => _gen(seed)
        .session
        .steps
        .any((s) => s.mode == SessionMode.biffle && (s.bpm ?? 0) > 75));
    expect(fastBiffle, isTrue,
        reason: 'pré-condition : sans cap, des biffles > 75 BPM existent');

    final profile = _profile({
      CapabilityAxis.rhythmBpmCeilShallow: 90.0,
      CapabilityAxis.biffleBpmMax: 75.0,
    });
    for (final seed in [1, 7, 42, 64, 200]) {
      for (final s in _gen(seed, profile: profile).session.steps) {
        if (s.mode == SessionMode.rhythm &&
            s.to != null &&
            s.to!.index <= Position.mid.index) {
          if (s.bpm != null) {
            expect(s.bpm, lessThanOrEqualTo(_withSurcharge(90)),
                reason: 'seed=$seed rhythm shallow bpm=${s.bpm} (t=${s.time}) '
                    '> comfort 90 (+ surcharge éventuelle)');
          }
          if (s.bpmEnd != null) {
            expect(s.bpmEnd, lessThanOrEqualTo(_withSurcharge(90)),
                reason: 'seed=$seed rhythm shallow bpmEnd=${s.bpmEnd} '
                    '(t=${s.time}) > comfort 90 (+ surcharge éventuelle)');
          }
        }
        if (s.mode == SessionMode.biffle && s.bpm != null) {
          expect(s.bpm, lessThanOrEqualTo(_withSurcharge(75)),
              reason: 'seed=$seed biffle bpm=${s.bpm} (t=${s.time}) > '
                  'comfort 75 (+ surcharge éventuelle)');
        }
      }
    }
  });
}
