import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/services/capability_service.dart';

/// Sonde adversariale — rejeu du constat « grave » du tri du 2026-08-18
/// (verrou de profondeur : le générateur cible `comfort`, pas `best`).
///
/// Prédiction écrite avant exécution : avec `comfort=mid`/`best=throat`,
/// une séance normale ne devrait produire un step visant `throat` que si
/// `rhythmDepthMax` est l'axe surchargé de la séance ET que sa
/// `successRate` franchit `kDepthCranGate` (0.65) — jamais en dessous.
/// En séance `intense` (Encore) le bonus de cran est inconditionnel dans
/// `capabilityCapFor`, mais `maxDepthIndex` (plafond de *tirage*, distinct
/// du clamp) reste dérivé du `comfort` brut pour Encore (`useMe=false`) —
/// contrairement à Utilise-moi qui le force à `full`. Hypothèse à
/// trancher ici : Encore seul peut donc ne JAMAIS tirer `throat`, même si
/// `capabilityCapFor` l'autoriserait — un désaccord avec le rapport, qui
/// annonce 300/300 pour « Utilise-moi ou Encore » sans distinguer les deux.

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

CapabilityAxisState _s(double v, {double sr = 0.5}) =>
    CapabilityAxisState(best: v, comfort: v, successRate: sr);

/// Profil réaliste : les 14 axes surchargeables sont tous renseignés (comme
/// une joueuse avec un historique), pour que `rhythmDepthMax` entre en
/// concurrence pour le tirage d'axe surchargé au lieu d'être le seul
/// candidat (ce qui gonflerait artificiellement son taux de sélection).
CapabilityProfile _profile(double depthSuccessRate) {
  return CapabilityProfile({
    CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
      best: Position.throat.index.toDouble(),
      comfort: Position.mid.index.toDouble(),
      successRate: depthSuccessRate,
    ),
    CapabilityAxis.gorgeApneeStreak: _s(24),
    CapabilityAxis.gorgeEngagementStreak: _s(35),
    CapabilityAxis.gorgeCrossingsBpmThroat: _s(90),
    CapabilityAxis.gorgeCrossingsBpmFull: _s(80),
    CapabilityAxis.rhythmBpmCeilShallow: _s(100),
    CapabilityAxis.rhythmBpmCeilThroat: _s(90),
    CapabilityAxis.rhythmBpmCeilFull: _s(80),
    CapabilityAxis.rhythmMotionStreak: _s(200),
    CapabilityAxis.holdThroatStreak: _s(30),
    CapabilityAxis.holdFullStreak: _s(25),
    CapabilityAxis.noswallowStreak: _s(120),
    CapabilityAxis.biffleStreak: _s(30),
    CapabilityAxis.biffleBpmMax: _s(90),
  });
}

/// Variante « à égalité » : les 14 axes surchargeables partagent la MÊME
/// `successRate` (dont `rhythmDepthMax`). Isole le tirage lui-même : si
/// tous les axes sont à égalité de confiance, `rhythmDepthMax` ne devrait
/// gagner la loterie de surcharge qu'un axe sur ~14 (~7 %), pas 300/300 —
/// contrairement au scénario `_profile` ci-dessus où depth est délibérément
/// avantagé (sr=0.80 contre 0.50 pour les 13 autres, un écart plus grand
/// que le tie-break aléatoire ±0.05, donc une victoire garantie).
CapabilityProfile _profileTied(double sr) {
  return CapabilityProfile({
    CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
      best: Position.throat.index.toDouble(),
      comfort: Position.mid.index.toDouble(),
      successRate: sr,
    ),
    CapabilityAxis.gorgeApneeStreak: _s(24, sr: sr),
    CapabilityAxis.gorgeEngagementStreak: _s(35, sr: sr),
    CapabilityAxis.gorgeCrossingsBpmThroat: _s(90, sr: sr),
    CapabilityAxis.gorgeCrossingsBpmFull: _s(80, sr: sr),
    CapabilityAxis.rhythmBpmCeilShallow: _s(100, sr: sr),
    CapabilityAxis.rhythmBpmCeilThroat: _s(90, sr: sr),
    CapabilityAxis.rhythmBpmCeilFull: _s(80, sr: sr),
    CapabilityAxis.rhythmMotionStreak: _s(200, sr: sr),
    CapabilityAxis.holdThroatStreak: _s(30, sr: sr),
    CapabilityAxis.holdFullStreak: _s(25, sr: sr),
    CapabilityAxis.noswallowStreak: _s(120, sr: sr),
    CapabilityAxis.biffleStreak: _s(30, sr: sr),
    CapabilityAxis.biffleBpmMax: _s(90, sr: sr),
  });
}

int _countRhythmThroatTied({
  required double sr,
  required int seedCount,
}) {
  final profile = _profileTied(sr);
  var count = 0;
  for (var seed = 0; seed < seedCount; seed++) {
    final r = CareerSessionGenerator(seed: seed).generate(
      level: 14,
      bank: _bank(),
      durationSeconds: 1500,
      humiliationCareer: 100.0,
      obedience: 100.0,
      unlockedKeys: _throatProvenUnlocks,
      capability: CapabilityInputs(profile: profile),
    );
    final hit = r.session.steps.any((s) =>
        !s.isTextOnly &&
        s.mode == SessionMode.rhythm &&
        s.to != null &&
        s.to!.index >= Position.throat.index);
    if (hit) count++;
  }
  return count;
}

/// Sur [seedCount] graines, compte séparément les séances qui contiennent
/// au moins un step **rhythm** (resp. **hold**) dont `to >= throat`.
///
/// Séparation cruciale : `pickHoldPosition` (position_pickers.dart:160) est
/// documenté **« pas de cap par maxDepthIndex »** — la position d'un hold
/// est gatée par les milestones (`fullHold`/`throatHold`/`holdMid`), pas
/// par `rhythm.depth_max`. Un comptage fondu rhythm+hold (comme le fait
/// `use_me_mode_test.dart` pour une autre question) confond deux
/// mécanismes différents et ne peut pas trancher CE constat.
({int rhythm, int hold}) _countReachingThroat({
  required double depthSuccessRate,
  required bool intense,
  required bool useMe,
  required int seedCount,
  required Set<UnlockKey> unlockedKeys,
}) {
  final profile = _profile(depthSuccessRate);
  var rhythmCount = 0;
  var holdCount = 0;
  for (var seed = 0; seed < seedCount; seed++) {
    final r = CareerSessionGenerator(seed: seed).generate(
      level: 14,
      bank: _bank(),
      durationSeconds: 1500, // format "moyenne" (25 min)
      intense: intense,
      useMe: useMe,
      humiliationCareer: 100.0,
      obedience: 100.0,
      unlockedKeys: unlockedKeys,
      capability: CapabilityInputs(profile: profile),
    );
    var rhythmHit = false;
    var holdHit = false;
    for (final s in r.session.steps) {
      if (s.isTextOnly) continue;
      final to = s.to;
      if (to == null || to.index < Position.throat.index) continue;
      if (s.mode == SessionMode.rhythm) rhythmHit = true;
      if (s.mode == SessionMode.hold) holdHit = true;
    }
    if (rhythmHit) rhythmCount++;
    if (holdHit) holdCount++;
  }
  return (rhythm: rhythmCount, hold: holdCount);
}

/// Milestones réalistes pour un profil `comfort=mid/best=throat` : elle a
/// prouvé jusqu'à throat, donc les unlocks jusqu'à throat sont acquis —
/// mais PAS `fullHold`/`fullPulse` (jamais prouvé full). Contraste avec
/// `_allUnlocks` (utilisé par `use_me_mode_test.dart` pour une autre
/// question, qui ouvre aussi le palier full).
final Set<UnlockKey> _throatProvenUnlocks = {
  UnlockKey.holdMid,
  UnlockKey.throatHold,
  UnlockKey.throatPulse,
};

void main() {
  const seedCount = 300;

  test('normal, successRate 0.50 (< 0.65) — jamais de throat en rhythm', () {
    final n = _countReachingThroat(
      depthSuccessRate: 0.50,
      intense: false,
      useMe: false,
      seedCount: seedCount,
      unlockedKeys: _throatProvenUnlocks,
    );
    // ignore: avoid_print
    print('[depth-probe] normal sr=0.50 (sous le seuil) : '
        'rhythm=${n.rhythm}/$seedCount hold=${n.hold}/$seedCount');
    expect(n.rhythm, 0,
        reason: 'sous kDepthCranGate, capabilityCapFor ne doit jamais '
            'accorder le +1 cran, quel que soit l\'axe surchargé tiré');
  });

  test('normal, successRate 0.80 (>= 0.65) — le +1 cran doit sortir', () {
    final n = _countReachingThroat(
      depthSuccessRate: 0.80,
      intense: false,
      useMe: false,
      seedCount: seedCount,
      unlockedKeys: _throatProvenUnlocks,
    );
    // ignore: avoid_print
    print('[depth-probe] normal sr=0.80 (au-dessus du seuil) : '
        'rhythm=${n.rhythm}/$seedCount hold=${n.hold}/$seedCount');
    expect(n.rhythm, greaterThan(0),
        reason: 'au-dessus du seuil, le +1 cran doit sortir au moins parfois '
            '(quand rhythmDepthMax est tiré comme axe surchargé) — sinon le '
            'plafond de TIRAGE (maxDepthIndex, dérivé du comfort BRUT, '
            'jamais boosté hors useMe) empêche `capabilityCapFor` de '
            'jamais servir à quoi que ce soit pour rhythm');
  });

  test(
      'normal, TOUS les axes à sr=0.70 à égalité — loterie ~1/14, pas '
      'déterministe', () {
    final n = _countRhythmThroatTied(sr: 0.70, seedCount: seedCount);
    // ignore: avoid_print
    print('[depth-probe] normal égalité sr=0.70 (14 axes) : '
        'rhythm=$n/$seedCount (≈${(n / seedCount * 100).toStringAsFixed(1)}%'
        ', attendu ≈100/14≈7%)');
    expect(n, greaterThan(0),
        reason: 'la loterie doit désigner depth au '
            'moins une fois sur 300 graines');
    expect(n, lessThan(seedCount ~/ 3),
        reason: 'à égalité stricte entre 14 '
            'candidats, depth ne doit pas gagner la majorité des séances — '
            'sinon le tirage n\'est pas ce que pickOverloadAxis documente');
  });

  test('Encore (intense=true, useMe=false), successRate 0.50 — cas litigieux',
      () {
    final n = _countReachingThroat(
      depthSuccessRate: 0.50,
      intense: true,
      useMe: false,
      seedCount: seedCount,
      unlockedKeys: _throatProvenUnlocks,
    );
    // ignore: avoid_print
    print('[depth-probe] Encore sr=0.50 (sous le seuil) : '
        'rhythm=${n.rhythm}/$seedCount hold=${n.hold}/$seedCount');
    // Pas d'expect() ici : c'est la valeur mesurée elle-même qui tranche
    // entre « le rapport a raison (300) » et « Encore diverge d'Utilise-moi
    // (0, faute de plafond de tirage relevé) » — voir le rapport final.
  });

  test('Encore (intense=true, useMe=false), successRate 0.80', () {
    final n = _countReachingThroat(
      depthSuccessRate: 0.80,
      intense: true,
      useMe: false,
      seedCount: seedCount,
      unlockedKeys: _throatProvenUnlocks,
    );
    // ignore: avoid_print
    print('[depth-probe] Encore sr=0.80 (au-dessus du seuil) : '
        'rhythm=${n.rhythm}/$seedCount hold=${n.hold}/$seedCount');
  });

  test('Utilise-moi (intense=true, useMe=true), successRate 0.50 — 300/300 ?',
      () {
    final n = _countReachingThroat(
      depthSuccessRate: 0.50,
      intense: true,
      useMe: true,
      seedCount: seedCount,
      unlockedKeys: _throatProvenUnlocks,
    );
    // ignore: avoid_print
    print('[depth-probe] Utilise-moi sr=0.50 (sous le seuil) : '
        'rhythm=${n.rhythm}/$seedCount hold=${n.hold}/$seedCount');
    expect(n.rhythm, seedCount,
        reason: 'useMe force maxDepthIndex=full au tirage, puis '
            'capabilityCapFor(intense) autorise comfort+1=throat sans '
            'gate — devrait sortir dans TOUTES les séances');
  });
}
