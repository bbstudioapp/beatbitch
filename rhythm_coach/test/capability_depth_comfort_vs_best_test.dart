import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/career_level_gates.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/services/capability_service.dart';

/// Verrou de profondeur — le `comfort` rabaissé sous le `best` prouvé ne doit
/// pas faire disparaître la tranche throat/full des séances normales.
///
/// Origine : sonde adversariale du tri du 2026-08-18, reprise telle quelle
/// puis retournée. Dans sa version d'origine elle *caractérisait* le défaut
/// (elle attendait `rhythm == 0` en séance normale sous le seuil, et passait
/// au vert sur `origin/develop`). Les deux attentes qui figeaient le défaut
/// sont réécrites ici pour exprimer le comportement voulu — les deux mesures
/// brutes correspondantes sont conservées telles quelles dans le rapport.
///
/// Ce que le correctif fait, tel que mesuré : la profondeur rythmée vise **un
/// cran** au-dessus du `comfort`, borné par le `best`. Donc :
/// - `comfort=mid` / `best=throat` → cap throat : la tranche revient ;
/// - `comfort=head` / `best=throat` → cap mid : un cran, pas le retour à
///   throat — la remontée reste graduelle ;
/// - `best == comfort` → no-op strict.

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
CapabilityProfile _profile(
  double depthSuccessRate, {
  double comfort = 2.0, // mid
  double best = 3.0, // throat
}) {
  return CapabilityProfile({
    CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
      best: best,
      comfort: comfort,
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

/// Sur [seedCount] graines, compte séparément les séances qui contiennent
/// au moins un step **rhythm** (resp. **hold**) dont `to >= throat`, et la
/// profondeur maximale jamais atteinte par une **tenue**.
///
/// Séparation cruciale : `pickHoldPosition` (position_pickers.dart:160) est
/// documenté **« pas de cap par maxDepthIndex »** — la position d'un hold
/// est gatée par les milestones (`fullHold`/`throatHold`/`holdMid`), pas
/// par `rhythm.depth_max`. Un comptage fondu rhythm+hold confond deux
/// mécanismes différents et ne peut pas trancher CE constat.
({int rhythm, int hold, Position? deepestHold}) _countReachingThroat({
  required double depthSuccessRate,
  required bool intense,
  required bool useMe,
  required int seedCount,
  required Set<UnlockKey> unlockedKeys,
  double comfort = 2.0,
  double best = 3.0,
}) {
  final profile = _profile(depthSuccessRate, comfort: comfort, best: best);
  var rhythmCount = 0;
  var holdCount = 0;
  Position? deepestHold;
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
      if (to == null) continue;
      if (s.mode == SessionMode.hold &&
          (deepestHold == null || to.index > deepestHold.index)) {
        deepestHold = to;
      }
      if (to.index < Position.throat.index) continue;
      if (s.mode == SessionMode.rhythm) rhythmHit = true;
      if (s.mode == SessionMode.hold) holdHit = true;
    }
    if (rhythmHit) rhythmCount++;
    if (holdHit) holdCount++;
  }
  return (rhythm: rhythmCount, hold: holdCount, deepestHold: deepestHold);
}

/// Milestones réalistes pour un profil `comfort=mid/best=throat` : elle a
/// prouvé jusqu'à throat, donc les unlocks jusqu'à throat sont acquis —
/// mais PAS `fullHold`/`fullPulse` (jamais prouvé full).
final Set<UnlockKey> _throatProvenUnlocks = {
  UnlockKey.holdMid,
  UnlockKey.throatHold,
  UnlockKey.throatPulse,
};

void main() {
  const seedCount = 300;

  group('sonde vers le best prouvé', () {
    test('comfort=mid/best=throat, sr sous le seuil — throat revient', () {
      final n = _countReachingThroat(
        depthSuccessRate: 0.50,
        intense: false,
        useMe: false,
        seedCount: seedCount,
        unlockedKeys: _throatProvenUnlocks,
      );
      expect(n.rhythm, seedCount,
          reason: 'la sonde vise le best PROUVÉ : reproposer throat ne pousse '
              'pas au-delà de ce qu\'elle a tenu, donc elle ne doit dépendre '
              'ni de la loterie de surcharge ni de kDepthCranGate — sinon '
              'aucun overshoot n\'est possible et le comfort ne remonte '
              'jamais (le verrou d\'origine : 0/300 ici)');
    });

    test('comfort=mid/best=throat, sr au-dessus du seuil — inchangé', () {
      final n = _countReachingThroat(
        depthSuccessRate: 0.80,
        intense: false,
        useMe: false,
        seedCount: seedCount,
        unlockedKeys: _throatProvenUnlocks,
      );
      expect(n.rhythm, seedCount);
    });

    test('la sonde rend UN cran, pas le best : comfort=head reste borné à mid',
        () {
      final n = _countReachingThroat(
        depthSuccessRate: 0.80,
        intense: false,
        useMe: false,
        seedCount: seedCount,
        unlockedKeys: _throatProvenUnlocks,
        comfort: Position.head.index.toDouble(),
      );
      expect(n.rhythm, 0,
          reason: 'comfort=head + 1 cran = mid : une chute de deux crans ne '
              'se rattrape pas d\'un coup, même best=throat prouvé');
    });

    test('best == comfort — no-op strict', () {
      final n = _countReachingThroat(
        depthSuccessRate: 0.50,
        intense: false,
        useMe: false,
        seedCount: seedCount,
        unlockedKeys: _throatProvenUnlocks,
        best: Position.mid.index.toDouble(),
      );
      expect(n.rhythm, 0,
          reason: 'axe consolidé : rien à sonder, comportement Phase 19.7');
    });

    test('best < comfort (profil incohérent) — la sonde n\'abaisse pas', () {
      final n = _countReachingThroat(
        depthSuccessRate: 0.50,
        intense: false,
        useMe: false,
        seedCount: seedCount,
        unlockedKeys: _throatProvenUnlocks,
        comfort: Position.throat.index.toDouble(),
        best: Position.mid.index.toDouble(),
      );
      expect(n.rhythm, seedCount,
          reason: 'un état persisté où best < comfort ne doit pas faire '
              'RABAISSER le cap sous le comfort');
    });

    test('maxDepthIndexForProfile suit la même règle', () {
      int cap(double comfort, double best) =>
          CareerLevelGates.maxDepthIndexForProfile(
              _profile(0.5, comfort: comfort, best: best));
      expect(cap(2, 3), Position.throat.index); // mid + 1 cran, borné au best
      expect(cap(2, 4), Position.throat.index); // un seul cran, pas full
      expect(cap(2, 2), Position.mid.index); // consolidé : no-op
      expect(cap(1, 3), Position.mid.index); // head + 1 cran, planché mid
      expect(
          cap(3, 2), Position.throat.index); // incohérent : pas d'abaissement
      expect(cap(4, 4), Position.full.index); // plafond full conservé
    });
  });

  group('escalade — inchangée', () {
    test('Encore (intense, sans surcharge ni seuil)', () {
      final n = _countReachingThroat(
        depthSuccessRate: 0.50,
        intense: true,
        useMe: false,
        seedCount: seedCount,
        unlockedKeys: _throatProvenUnlocks,
      );
      expect(n.rhythm, seedCount);
    });

    test('Utilise-moi', () {
      final n = _countReachingThroat(
        depthSuccessRate: 0.50,
        intense: true,
        useMe: true,
        seedCount: seedCount,
        unlockedKeys: _throatProvenUnlocks,
      );
      expect(n.rhythm, seedCount);
    });
  });

  group('non-régression des tenues', () {
    // Les tenues sont gatées par les milestones hold, pas par
    // `rhythm.depth_max` : le correctif ne doit rien y changer. Les compteurs
    // bruts ne sont pas comparables step à step (déplacer un step rythmé fait
    // diverger toute la séquence RNG en aval) — d'où deux invariants qui, eux,
    // le sont : la tranche throat sort toujours, et `full` reste fermé.
    for (final (label, comfort, best) in [
      ('sonde active (mid/throat)', 2.0, 3.0),
      ('no-op (mid/mid)', 2.0, 2.0),
      ('chute de deux crans (head/throat)', 1.0, 3.0),
    ]) {
      test('$label — tenues throat présentes, full jamais ouvert', () {
        final n = _countReachingThroat(
          depthSuccessRate: 0.50,
          intense: false,
          useMe: false,
          seedCount: seedCount,
          unlockedKeys: _throatProvenUnlocks,
          comfort: comfort,
          best: best,
        );
        expect(n.hold, seedCount,
            reason: 'les tenues throat ne dépendent pas du profil rythme');
        expect(n.deepestHold, Position.throat,
            reason: 'sans `fullHold` acquise, aucune tenue ne doit atteindre '
                'full — le correctif ne doit pas ouvrir de palier de tenue');
      });
    }
  });
}
