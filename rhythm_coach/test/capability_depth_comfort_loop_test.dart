import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/capability_tracker.dart';
import 'package:beat_bitch/services/saliva_engine.dart';

/// Boucle complète séance → régulateur → séance suivante, sur la profondeur
/// rythmée. Les autres sondes de profondeur injectent un profil **figé** dans
/// le générateur : elles montrent que la tranche throat redevient visible,
/// jamais que le `comfort` remonte. Celle-ci referme le circuit — le profil
/// persisté est relu par le générateur, la séance produite est rejouée dans le
/// vrai `CapabilityTracker`, et son rapport repasse par le vrai
/// `CapabilityService.commit` avant la séance suivante.
///
/// Simplifications assumées du rejeu (le `SessionController` n'est pas
/// instancié) :
/// - les `chainAction` ne sont pas déroulées ;
/// - après un tap-out la séance s'arrête, là où l'app régénère la suite bornée
///   par les `sessionCeilings` ;
/// - le temps avance d'une seconde exacte par tick, sans TTS ni différé.

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

/// Milestones d'une joueuse qui a prouvé jusqu'à throat, jamais full.
final Set<UnlockKey> _throatProvenUnlocks = {
  UnlockKey.holdMid,
  UnlockKey.throatHold,
  UnlockKey.throatPulse,
};

/// Les 14 axes surchargeables renseignés, comme un profil d'historique — pour
/// que `rhythmDepthMax` entre en concurrence pour le tirage d'axe surchargé.
const Map<String, double> _otherAxes = {
  'gorge.apnee.streak': 24,
  'gorge.engagement.streak': 35,
  'gorge.crossings.bpm.throat': 90,
  'gorge.crossings.bpm.full': 80,
  'rhythm.bpm_ceil.shallow': 100,
  'rhythm.bpm_ceil.throat': 90,
  'rhythm.bpm_ceil.full': 80,
  'rhythm.motion.streak': 200,
  'hold.throat.streak': 30,
  'hold.full.streak': 25,
  'noswallow.streak': 120,
  'biffle.streak': 30,
  'biffle.bpm_max': 90,
};

/// Profil persisté de départ : `comfort` rabaissé sous le `best` prouvé, et
/// une confiance sous `kDepthCranGate` — l'état exact du défaut.
Map<String, Object> _seed({
  required double comfort,
  required double best,
  double successRate = 0.50,
}) {
  final values = <String, Object>{};
  void put(String key, double best, double comfort, double sr) {
    values['cap.$key.best'] = best;
    values['cap.$key.comfort'] = comfort;
    values['cap.$key.sr'] = sr;
    values['cap.$key.seen'] = 0;
  }

  put(CapabilityAxis.rhythmDepthMax.storageKey, best, comfort, successRate);
  _otherAxes.forEach((key, v) => put(key, v, v, 0.5));
  return values;
}

/// Ce qu'une séance a produit une fois rejouée.
typedef _Played = ({
  SessionCapabilityReport report,
  int deepestRhythm,
  bool tappedOut,
});

/// Génère une séance depuis [profile] et la rejoue seconde par seconde dans un
/// `CapabilityTracker`, comme le fait `SessionController`.
///
/// [tapOut] : la joueuse tape out dès qu'un step rythmé vise plus profond que
/// son `comfort` — elle ne tient pas le cran sondé. Le tap-out tombe 2 s après
/// le step, donc avant le seuil de record soutenu (3 s) : elle ne pose aucun
/// record à ce cran, seulement un plafond de session.
_Played _play({
  required CapabilityProfile profile,
  required int seed,
  required bool tapOut,
}) {
  final result = CareerSessionGenerator(seed: seed).generate(
    level: 14,
    bank: _bank(),
    durationSeconds: 1500,
    humiliationCareer: 100.0,
    obedience: 100.0,
    unlockedKeys: _throatProvenUnlocks,
    capability: CapabilityInputs(profile: profile),
  );
  final session = result.session;
  final comfort = profile.comfortOf(CapabilityAxis.rhythmDepthMax) ?? 0;

  final tracker = CapabilityTracker()..onSessionStart();
  final byTime = <int, List<SessionStep>>{};
  var lastTime = 0;
  for (final step in session.steps) {
    byTime.putIfAbsent(step.time, () => []).add(step);
    if (step.time > lastTime) lastTime = step.time;
  }
  final totalSeconds =
      session.durationSeconds > lastTime ? session.durationSeconds : lastTime;

  var swallow = SwallowMode.allowed;
  var deepestRhythm = 0;
  var tappedOut = false;
  var failAt = -1;

  for (var t = 0; t <= totalSeconds; t++) {
    for (final step in byTime[t] ?? const <SessionStep>[]) {
      final stepSwallow = step.swallowMode;
      if (stepSwallow != null) swallow = stepSwallow;
      if (step.isTextOnly) continue;
      final mode = step.mode ?? session.defaultMode;
      tracker.onStepApplied(
        mode: mode,
        from: step.from,
        to: step.to,
        bpm: step.bpm,
        duration: step.duration,
      );
      final to = step.to;
      if (mode == SessionMode.rhythm && to != null) {
        if (to.index > deepestRhythm) deepestRhythm = to.index;
        if (tapOut && failAt < 0 && to.index > comfort) {
          failAt = t + 2;
        }
      }
    }
    tracker.onTickSecond(swallowMode: swallow);
    if (failAt >= 0 && t >= failAt) {
      tracker.onFail();
      tappedOut = true;
      break;
    }
  }

  return (
    report: tracker.finalizeReport(),
    deepestRhythm: deepestRhythm,
    tappedOut: tappedOut,
  );
}

/// Une séance de la boucle, telle qu'observée de l'extérieur : le `comfort`
/// qui a servi à la générer, la profondeur rythmée qu'elle a effectivement
/// proposée, et l'état du profil une fois le rapport régulé.
typedef _Round = ({
  double comfortBefore,
  double comfort,
  double best,
  double successRate,
  int deepestRhythm,
  bool tappedOut,
});

/// Enchaîne [sessions] séances en repassant chaque rapport au régulateur.
/// Renvoie l'état du profil **après** chaque séance.
Future<List<_Round>> _loop({
  required double comfort,
  required double best,
  required int sessions,
  Set<int> tapOutOn = const {},
  int seedBase = 0,
}) async {
  SharedPreferences.setMockInitialValues(_seed(comfort: comfort, best: best));
  final service = CapabilityService();
  final rounds = <_Round>[];

  for (var i = 1; i <= sessions; i++) {
    final profile = await service.snapshotProfile();
    final played = _play(
      profile: profile,
      seed: seedBase + i,
      tapOut: tapOutOn.contains(i),
    );
    await service.commit(played.report, sessionIndex: i);
    final after = await service.snapshotProfile();
    final state = after.stateOf(CapabilityAxis.rhythmDepthMax);
    rounds.add((
      comfortBefore: profile.comfortOf(CapabilityAxis.rhythmDepthMax) ?? 0,
      comfort: state.comfort ?? 0,
      best: state.best ?? 0,
      successRate: state.successRate,
      deepestRhythm: played.deepestRhythm,
      tappedOut: played.tappedOut,
    ));
  }
  return rounds;
}

const double _head = 1;
const double _mid = 2;
const double _throat = 3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('boucle complète — le comfort remonte vers le best', () {
    test('comfort=mid / best=throat : throat récupéré à la 2ᵉ séance',
        () async {
      for (final seedBase in [0, 100, 200, 300, 400]) {
        final rounds = await _loop(
          comfort: _mid,
          best: _throat,
          sessions: 6,
          seedBase: seedBase,
        );
        expect(rounds[0].deepestRhythm, Position.throat.index,
            reason: 'graines $seedBase : la sonde rend la tranche throat '
                'visible dès la 1ʳᵉ séance — c\'est la condition nécessaire, '
                'sur origin/develop la profondeur proposée plafonne à mid');
        expect(rounds[0].comfort, _mid,
            reason: 'séance 1 : l\'overshoot est vu, mais le ratchet ↑ d\'un '
                'axe depthCran est en plus gaté par kDepthCranGate — la '
                'confiance (0,50) n\'y est pas encore');
        expect(rounds[0].successRate,
            closeTo(CapabilityRegulator.kDepthCranGate, 1e-9),
            reason: 'l\'EMA de succès passe 0,50 → 0,65 = le seuil, tout '
                'juste : c\'est ce qui coûte la 1ʳᵉ séance');
        expect(rounds[1].comfort, _throat,
            reason: 'séance 2 : le seuil est atteint, le cran est rendu');
        for (final r in rounds.skip(1)) {
          expect(r.comfort, _throat, reason: 'et il ne rebouge plus');
          expect(r.best, _throat,
              reason: 'la sonde ne pousse jamais au-delà du territoire prouvé');
        }
      }
    });

    test('chute de deux crans : un cran par séance, throat à la 3ᵉ', () async {
      final rounds = await _loop(comfort: _head, best: _throat, sessions: 6);
      expect(
          rounds.map((r) => r.comfort).take(3).toList(), [_head, _mid, _throat],
          reason: 'la remontée reste graduelle — jamais de retour direct au '
              'best (sur origin/develop elle s\'arrête à mid, plancher de '
              'maxDepthIndexForProfile, et n\'en repart jamais)');
    });
  });

  group('boucle complète — l\'échec redescend, il ne coince pas', () {
    test('tap-out à chaque séance : la profondeur proposée suit', () async {
      final rounds = await _loop(
        comfort: _mid,
        best: _throat,
        sessions: 4,
        tapOutOn: const {1, 2, 3, 4},
      );
      expect(rounds[0].tappedOut, isTrue,
          reason: 'le cran sondé l\'expose vraiment — sur origin/develop rien '
              'ne dépasse son comfort, elle n\'est jamais mise en difficulté');
      expect(rounds.map((r) => r.comfort).toList(), [_head, 0, 0, 0],
          reason: 'un tap-out imputé coûte un cran, plancher à 0');
      for (final r in rounds) {
        expect(r.deepestRhythm, lessThanOrEqualTo(r.comfortBefore + 1),
            reason: 'la sonde ne propose jamais plus d\'un cran au-dessus du '
                'comfort courant : ce qu\'elle ne tient pas redescend');
      }
    });

    test('tap-out puis reprise : throat récupéré 4 séances plus tard',
        () async {
      final rounds = await _loop(
        comfort: _mid,
        best: _throat,
        sessions: 6,
        tapOutOn: const {1},
      );
      expect(rounds.map((r) => r.comfort).toList(),
          [_head, _head, _head, _mid, _throat, _throat],
          reason: 'le tap-out casse la confiance (EMA vers 0) autant qu\'il '
              'baisse le cran : il faut deux séances propres pour repasser '
              'kDepthCranGate avant que les crans reviennent');
    });
  });
}
