// Banc commun des tests « Utilise-moi » × profil de capacités (tss2-037) :
// vrai générateur, vrai tracker, vrai service (prefs simulées), rejeu seconde
// par seconde comme le contrôleur.
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/capability_tracker.dart';
import 'package:beat_bitch/services/saliva_engine.dart';

List<PhraseEntry> benchPhrases(List<String> t) =>
    t.map((x) => PhraseEntry(text: x)).toList();

PhraseBank benchBank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': benchPhrases(['s']),
            'medium': benchPhrases(['m']),
            'hard': benchPhrases(['h']),
            'boost': benchPhrases(['b']),
            'finale': benchPhrases(['f']),
          },
      },
      congrats: benchPhrases(['bravo']),
      intros: benchPhrases(['intro']),
    );

final Set<UnlockKey> benchUnlocks = UnlockKey.values.toSet();
const int benchLevel = 10;
const int benchSessionIdx = 20;

// (best, comfort, sr, lastSeen)
typedef BenchSeed = (double, double, double);

final Map<CapabilityAxis, BenchSeed> benchAvg = {
  CapabilityAxis.rhythmDepthMax: (3, 3, 0.6),
  CapabilityAxis.rhythmBpmCeilShallow: (135, 125, 0.6),
  CapabilityAxis.rhythmBpmCeilThroat: (105, 100, 0.55),
  CapabilityAxis.rhythmBpmCeilFull: (80, 75, 0.5),
  CapabilityAxis.rhythmBpmFloorShallow: (45, 50, 0.5),
  CapabilityAxis.rhythmBpmFloorThroat: (40, 45, 0.5),
  CapabilityAxis.rhythmBpmFloorFull: (35, 40, 0.5),
  CapabilityAxis.gorgeCrossingsBpmThroat: (100, 95, 0.55),
  CapabilityAxis.gorgeCrossingsBpmFull: (75, 70, 0.5),
  CapabilityAxis.gorgeCrossingsLifetime: (1500, 1500, 0.5),
  CapabilityAxis.gorgeApneeStreak: (20, 18, 0.55),
  CapabilityAxis.gorgeEngagementStreak: (70, 65, 0.55),
  CapabilityAxis.rhythmMotionStreak: (100, 95, 0.6),
  CapabilityAxis.holdThroatStreak: (25, 22, 0.55),
  CapabilityAxis.holdFullStreak: (14, 13, 0.5),
  CapabilityAxis.effortNoBreathStreak: (80, 75, 0.55),
  CapabilityAxis.noswallowStreak: (60, 55, 0.5),
  CapabilityAxis.breathMinDose: (4, 5, 0.5),
  CapabilityAxis.biffleStreak: (20, 18, 0.5),
  CapabilityAxis.biffleBpmMax: (120, 110, 0.5),
  CapabilityAxis.lickDepthMax: (4, 4, 0.5),
  CapabilityAxis.lickStreak: (60, 55, 0.5),
  CapabilityAxis.handStreak: (60, 55, 0.5),
};

Map<String, Object> benchPrefsSeed() {
  final m = <String, Object>{'cap.legacy_migrated': true};
  benchAvg.forEach((a, s) {
    m['cap.${a.storageKey}.best'] = s.$1;
    m['cap.${a.storageKey}.comfort'] = s.$2;
    m['cap.${a.storageKey}.sr'] = s.$3;
    m['cap.${a.storageKey}.seen'] = benchSessionIdx - 2;
  });
  return m;
}

CareerGenerationResult benchGen(int seed, int dur,
    {bool useMe = false,
    CapabilityProfile? profile,
    Map<CapabilityAxis, double> ceilings = const {}}) {
  return CareerSessionGenerator(seed: seed).generate(
    level: benchLevel,
    bank: benchBank(),
    durationSeconds: dur,
    intense: useMe,
    useMe: useMe,
    humiliationCareer: 120.0,
    humiliationSession: 0,
    obedience: 60.0,
    unlockedKeys: benchUnlocks,
    capability: CapabilityInputs(profile: profile, sessionCeilings: ceilings),
  );
}

List<SessionStep> benchShift(List<SessionStep> src, int dt, {int? until}) => [
      for (final s in src)
        if (until == null || s.time < until) _benchCopy(s, s.time + dt)
    ];

SessionStep _benchCopy(SessionStep s, int t) => SessionStep(
      time: t,
      text: s.text,
      mode: s.mode,
      from: s.from,
      to: s.to,
      bpm: s.bpm,
      bpmEnd: s.bpmEnd,
      duration: s.duration,
    );

/// Rejoue [steps] (temps absolus) de [t0] à [t1] dans le tracker réel. Les
/// steps dont l'instant est dans [useMeFrom, useMeUntil[ sont ceux d'« Utilise-moi ».
void benchReplay(CapabilityTracker tr, List<SessionStep> steps, int t0, int t1,
    {int? useMeFrom, int? useMeUntil}) {
  final cfg = steps
      .where((s) => !s.isTextOnly && s.time >= t0 && s.time < t1)
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  var i = 0;
  for (var s = t0; s < t1; s++) {
    while (i < cfg.length && cfg[i].time <= s) {
      final st = cfg[i++];
      final useMe = useMeFrom != null &&
          st.time >= useMeFrom &&
          (useMeUntil == null || st.time < useMeUntil);
      tr.onStepApplied(
        mode: st.mode ?? SessionMode.rhythm,
        from: st.from,
        to: st.to,
        bpm: st.bpm,
        duration: st.duration,
        useMe: useMe,
      );
    }
    tr.onTickSecond(
      swallowMode: SwallowMode.allowed,
      useMeActive: useMeFrom != null &&
          s >= useMeFrom &&
          (useMeUntil == null || s < useMeUntil),
    );
  }
}

class BenchOutcome {
  final CapabilityProfile before;
  final CapabilityProfile after;
  final SessionCapabilityReport report;
  const BenchOutcome(this.before, this.after, this.report);
}

/// Une séance : 2 min normales, puis soit « Utilise-moi » [useMeSec] s (précédé
/// d'un beg), soit — [useMe] faux — la même durée en séance normale (témoin).
/// [failFrac] : appui FAIL à cette fraction du segment, puis reprise normale.
Future<BenchOutcome> benchSession({
  required bool useMe,
  required int useMeSec,
  double? failFrac,
  int n = 0,
  CapabilityProfile? from,
}) async {
  final before = from ?? await CapabilityService().snapshotProfile();
  final tr = CapabilityTracker()..onSessionStart();
  final normal = benchGen(100 + n, 20 * 60, profile: before);
  const cut = 120;
  final List<SessionStep> steps;
  int? umFrom;
  if (useMe) {
    final pre = normal.session.steps.where((s) => s.time < cut).toList();
    const beg = SessionStep(
        time: cut,
        text: 'beg',
        mode: SessionMode.beg,
        from: Position.full,
        duration: 8);
    final um = benchGen(200 + n, useMeSec, useMe: true, profile: before);
    steps = [...pre, beg, ...benchShift(um.session.steps, cut + 8)];
    umFrom = cut + 8;
  } else {
    steps = normal.session.steps;
  }
  final total = cut + 8 + useMeSec;
  if (failFrac == null) {
    benchReplay(tr, steps, 0, total + (useMe ? 0 : 30), useMeFrom: umFrom);
  } else {
    final failAt = cut + 8 + (useMeSec * failFrac).round();
    benchReplay(tr, steps, 0, failAt, useMeFrom: umFrom);
    tr.onFail();
    final rest = total - failAt + 30;
    final resumed =
        benchGen(300 + n, rest, profile: before, ceilings: tr.sessionCeilings);
    benchReplay(
        tr, benchShift(resumed.session.steps, failAt), failAt, failAt + rest);
  }
  final report = tr.finalizeReport();
  await CapabilityService().commit(report, sessionIndex: benchSessionIdx + n);
  return BenchOutcome(
      before, await CapabilityService().snapshotProfile(), report);
}
