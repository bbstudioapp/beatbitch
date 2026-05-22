// Audit non-bloquant : dumpe la composition de N sessions générées et
// repère les patterns problématiques (boucles, profondeurs incohérentes,
// modes sur-représentés).
//
// **Pas un test de régression** — n'échoue jamais. Sortie dans
// `/tmp/audit_session_patterns.md` (markdown).
//
// Lancer : `flutter test test/audit_session_patterns_test.dart`
//
// Le but : repérer la « boucle breath/hold throat/rhythm tip→head »
// signalée par l'utilisatrice (steps répétitifs en cycle), et plus
// largement les compositions où une débutante reçoit trop de rhythm
// superficiel ou une expérimentée trop peu de profondeur.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() {
  return PhraseBank(
    byMode: {
      for (final m in SessionMode.values)
        m: {
          'soft': _p(['s']),
          'medium': _p(['m']),
          'hard': _p(['h']),
          'finale': _p(['f']),
          'boost': _p(['b']),
          'insistent': _p(['i']),
        },
    },
    congrats: _p(['bravo']),
    intros: _p(['intro']),
    encore: _p(['encore']),
  );
}

SpecializationAllocation _spec({
  int endurance = 0,
  int profondeur = 0,
  int rythmeBiffle = 0,
  int obeissance = 0,
  int sloppy = 0,
}) {
  return SpecializationAllocation(
    points: {
      SpecializationBranch.endurance: endurance,
      SpecializationBranch.profondeur: profondeur,
      SpecializationBranch.rythmeBiffle: rythmeBiffle,
      SpecializationBranch.obeissance: obeissance,
      SpecializationBranch.sloppy: sloppy,
    },
    lastRespecMs: null,
  );
}

class _Scenario {
  final String name;
  final int level;
  final int durationSeconds;
  final Set<UnlockKey> unlocks;
  final double humilCareer;
  final double obedience;
  final SpecializationAllocation? spec;

  const _Scenario({
    required this.name,
    required this.level,
    required this.durationSeconds,
    required this.unlocks,
    this.humilCareer = 0,
    this.obedience = 50,
    this.spec,
  });
}

/// Unlocks « bas niveau » : socle + premières actions débloquées.
const _unlocksLow = <UnlockKey>{
  UnlockKey.basics,
  UnlockKey.holdHead,
  UnlockKey.holdMid,
  UnlockKey.rhythmMidBasic,
  UnlockKey.lickFull,
  UnlockKey.begLibre,
  UnlockKey.finalHoldTip,
  UnlockKey.finalHoldHead,
  UnlockKey.finalLickTipHead,
};

/// Unlocks mi-niveau : ajoute throat + biffle.
const _unlocksMid = <UnlockKey>{
  ..._unlocksLow,
  UnlockKey.throatHold,
  UnlockKey.throatPulse,
  UnlockKey.biffleBasic,
  UnlockKey.finalHoldMid,
  UnlockKey.finalHoldThroat,
  UnlockKey.finalBiffle,
  UnlockKey.sloppyDroolBasic,
  UnlockKey.sloppyLoudSuck,
  UnlockKey.encore,
};

/// Unlocks haut niveau : ajoute full + fake breath.
final _unlocksHigh = <UnlockKey>{
  ..._unlocksMid,
  UnlockKey.fullHold,
  UnlockKey.fullPulse,
  UnlockKey.finalHoldFull,
  UnlockKey.fakeBreath,
  UnlockKey.surpriseNotifs,
  UnlockKey.sloppyOverflow,
  UnlockKey.sloppySwallowControl,
  UnlockKey.sloppyBiffleSlow,
  UnlockKey.sloppySpit,
  UnlockKey.freestyle,
  UnlockKey.suckleHead,
};

final _scenarios = <_Scenario>[
  _Scenario(
    name: 'A · débutante level 3, 8 min',
    level: 3,
    durationSeconds: 480,
    unlocks: _unlocksLow,
    humilCareer: 5,
  ),
  _Scenario(
    name: 'B · intermédiaire level 6, 12 min',
    level: 6,
    durationSeconds: 720,
    unlocks: {..._unlocksLow, UnlockKey.throatHold, UnlockKey.biffleBasic},
    humilCareer: 25,
    obedience: 80,
  ),
];

// Spécialisations construites à l'init (factory `_spec()` n'est pas const).
final SpecializationAllocation _specEndProf =
    _spec(endurance: 2, profondeur: 1);
final SpecializationAllocation _specProfEnd =
    _spec(profondeur: 3, endurance: 2);
final SpecializationAllocation _specMix =
    _spec(profondeur: 2, endurance: 2, rythmeBiffle: 1);

void _addScenariosWithSpec() {
  _scenarios.add(_Scenario(
    name: 'C · mi-haute level 10, 18 min (palier dont parle l\'utilisatrice)',
    level: 10,
    durationSeconds: 1080,
    unlocks: _unlocksMid,
    humilCareer: 60,
    obedience: 120,
    spec: _specEndProf,
  ));
  _scenarios.add(_Scenario(
    name: 'D · haut niveau level 15, 25 min',
    level: 15,
    durationSeconds: 1500,
    unlocks: _unlocksHigh,
    humilCareer: 150,
    obedience: 200,
    spec: _specProfEnd,
  ));
  _scenarios.add(_Scenario(
    name: 'E · expert level 20, 35 min',
    level: 20,
    durationSeconds: 2100,
    unlocks: _unlocksHigh,
    humilCareer: 250,
    obedience: 350,
    spec: _specMix,
  ));
}

String _modeName(SessionMode? m) => m?.name ?? '∅';
String _posName(Position? p) => p?.name ?? '-';

String _amplitudeKey(SessionMode? mode, Position? from, Position? to) {
  if (mode == null) return '∅';
  if (mode == SessionMode.hold) return _posName(to);
  if (from == null && to == null) return 'free';
  return '${_posName(from)}→${_posName(to)}';
}

class _PatternFlag {
  final String label;
  final String detail;
  const _PatternFlag(this.label, this.detail);
}

List<_PatternFlag> _analyze(List<SessionStep> steps, _Scenario sc) {
  final flags = <_PatternFlag>[];
  final config = steps.where((s) => !s.isTextOnly).toList();
  if (config.isEmpty) return flags;

  // 1. Distribution des modes
  final modeCounts = <SessionMode, int>{};
  for (final s in config) {
    final m = s.mode ?? SessionMode.rhythm;
    modeCounts[m] = (modeCounts[m] ?? 0) + 1;
  }
  final total = config.length;

  // 2. Distribution des amplitudes rhythm
  final rhythmAmplitudes = <String, int>{};
  for (final s in config) {
    if (s.mode != SessionMode.rhythm) continue;
    final k = _amplitudeKey(SessionMode.rhythm, s.from, s.to);
    rhythmAmplitudes[k] = (rhythmAmplitudes[k] ?? 0) + 1;
  }
  final rhythmTotal = rhythmAmplitudes.values.fold(0, (a, b) => a + b);

  // 3. Détection : rhythm à `to ≤ mid` dominant alors que throat débloqué.
  //    Cohérence du brief : la joueuse à `throat_hold` débloqué devrait
  //    voir plus de rhythm head→throat / mid→throat.
  if (sc.unlocks.contains(UnlockKey.throatHold) && rhythmTotal > 0) {
    var shallow = 0;
    for (final s in config) {
      if (s.mode != SessionMode.rhythm) continue;
      final t = s.to;
      if (t == null) continue;
      if (t.index <= Position.mid.index) shallow++;
    }
    final pct = shallow / rhythmTotal;
    if (pct > 0.65) {
      flags.add(_PatternFlag(
        'RHYTHM-LOW-DEPTH',
        '${(pct * 100).toStringAsFixed(0)}% des rhythms ont `to ≤ mid` '
            '($shallow/$rhythmTotal) alors que throat_hold est débloqué — '
            'profondeur sous-exploitée',
      ));
    }
  }

  // 3b. (Note : pas de détection « holds tous à la même profondeur » — si
  //      seul `throat` est débloqué, c'est cohérent que tous les holds y
  //      tombent. La variété sera mécaniquement présente quand `fullHold`
  //      sera débloqué.)

  // 4. Cycle de modes répétitif — détecte tout cycle de 2 ou 3 modes
  //    consécutifs qui se répète (ex: breath/hold/rhythm/breath/hold/rhythm).
  //    Plus général que la « boucle breath/hold throat/rhythm tip→head »
  //    initialement signalée — c'est la *structure* qui pose problème
  //    (« on n'est pas forcé de faire systématiquement breath/hold/rythm »),
  //    pas le détail des positions.
  for (final cycleLen in const [2, 3]) {
    final occurrences = <String, int>{};
    for (var i = 0; i + 2 * cycleLen - 1 < config.length; i++) {
      final sig = [
        for (var k = 0; k < cycleLen; k++)
          (config[i + k].mode ?? SessionMode.rhythm).name,
      ].join('/');
      final next = [
        for (var k = 0; k < cycleLen; k++)
          (config[i + cycleLen + k].mode ?? SessionMode.rhythm).name,
      ].join('/');
      if (sig != next) continue;
      // Ignorer les cycles d'un seul mode — captés par MODE-DOM / REPEAT-STREAK
      if (sig.split('/').toSet().length < 2) continue;
      occurrences[sig] = (occurrences[sig] ?? 0) + 1;
    }
    for (final entry in occurrences.entries) {
      if (entry.value >= 3) {
        flags.add(_PatternFlag(
          'CYCLE-REPEAT',
          'cycle `${entry.key}` répété ${entry.value} fois dans la séance '
              '(structure mécanique manquant de variation)',
        ));
      }
    }
  }

  // 5. Mode sur-représenté (>50%)
  for (final e in modeCounts.entries) {
    final pct = e.value / total;
    if (pct > 0.5) {
      flags.add(_PatternFlag(
        'MODE-DOM',
        '${e.key.name} domine ${(pct * 100).toStringAsFixed(0)}% des steps '
            '(${e.value}/$total)',
      ));
    }
  }

  // 6. Séquence répétitive : 3+ steps consécutifs avec même mode + amplitude
  var streak = 1;
  var maxStreak = 1;
  String? maxStreakKey;
  for (var i = 1; i < config.length; i++) {
    final prev = config[i - 1];
    final cur = config[i];
    final samMode = prev.mode == cur.mode;
    final samFrom = prev.from == cur.from;
    final samTo = prev.to == cur.to;
    if (samMode && samFrom && samTo) {
      streak++;
      if (streak > maxStreak) {
        maxStreak = streak;
        maxStreakKey =
            '${_modeName(cur.mode)} ${_amplitudeKey(cur.mode, cur.from, cur.to)}';
      }
    } else {
      streak = 1;
    }
  }
  if (maxStreak >= 4) {
    flags.add(_PatternFlag(
      'REPEAT-STREAK',
      '$maxStreak steps consécutifs identiques ($maxStreakKey)',
    ));
  }

  // 7. Cohérence amplitude rhythm : `from > to` (du shallow vers le deep)
  for (final s in config) {
    if (s.mode != SessionMode.rhythm && s.mode != SessionMode.lick) continue;
    final f = s.from;
    final t = s.to;
    if (f == null || t == null) continue;
    if (f.index >= t.index) {
      flags.add(_PatternFlag(
        'AMPL-INV',
        '${s.mode!.name} t=${s.time} from=${f.name} ≥ to=${t.name} '
            '(amplitude inversée ou nulle)',
      ));
      break; // un seul flag par session suffit pour pointer le bug
    }
  }

  return flags;
}

String _renderScenario(
    _Scenario sc, List<SessionStep> steps, List<_PatternFlag> flags) {
  final config = steps.where((s) => !s.isTextOnly).toList();
  final buf = StringBuffer();
  buf.writeln('## ${sc.name}');
  buf.writeln();
  buf.writeln(
      '- niveau **${sc.level}**, durée **${sc.durationSeconds ~/ 60} min**');
  buf.writeln('- humil career=${sc.humilCareer}, obed=${sc.obedience}');
  if (sc.spec != null) {
    final s = sc.spec!;
    buf.writeln('- spé : end=${s.pointsIn(SpecializationBranch.endurance)} '
        'prof=${s.pointsIn(SpecializationBranch.profondeur)} '
        'rb=${s.pointsIn(SpecializationBranch.rythmeBiffle)} '
        'ob=${s.pointsIn(SpecializationBranch.obeissance)} '
        'sl=${s.pointsIn(SpecializationBranch.sloppy)}');
  }
  buf.writeln(
      '- ${steps.length} steps total, ${config.length} steps de config');
  buf.writeln();

  // Distribution modes
  final modeCounts = <SessionMode, int>{};
  for (final s in config) {
    final m = s.mode ?? SessionMode.rhythm;
    modeCounts[m] = (modeCounts[m] ?? 0) + 1;
  }
  buf.writeln('### Distribution modes');
  buf.writeln();
  final sortedModes = modeCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedModes) {
    final pct = (e.value / config.length * 100).toStringAsFixed(0);
    buf.writeln('- `${e.key.name}` : ${e.value} ($pct%)');
  }
  buf.writeln();

  // Distribution amplitudes (rhythm + lick + hand)
  final ampCounts = <String, int>{};
  for (final s in config) {
    if (s.mode == SessionMode.rhythm ||
        s.mode == SessionMode.lick ||
        s.mode == SessionMode.hand) {
      final k = '${s.mode!.name} ${_amplitudeKey(s.mode, s.from, s.to)}';
      ampCounts[k] = (ampCounts[k] ?? 0) + 1;
    }
  }
  if (ampCounts.isNotEmpty) {
    buf.writeln('### Amplitudes rythme/lick/hand');
    buf.writeln();
    final sorted = ampCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      buf.writeln('- `${e.key}` : ${e.value}');
    }
    buf.writeln();
  }

  // Distribution profondeur holds
  final holdCounts = <String, int>{};
  for (final s in config) {
    if (s.mode != SessionMode.hold) continue;
    final k = _posName(s.to);
    holdCounts[k] = (holdCounts[k] ?? 0) + 1;
  }
  if (holdCounts.isNotEmpty) {
    buf.writeln('### Profondeur des holds');
    buf.writeln();
    final sorted = holdCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      buf.writeln('- `${e.key}` : ${e.value}');
    }
    buf.writeln();
  }

  // Flags
  buf.writeln('### Patterns détectés');
  buf.writeln();
  if (flags.isEmpty) {
    buf.writeln('_aucun pattern problématique._');
  } else {
    for (final f in flags) {
      buf.writeln('- **${f.label}** — ${f.detail}');
    }
  }
  buf.writeln();

  // Timeline complète (config steps)
  buf.writeln('### Timeline (steps de config)');
  buf.writeln();
  buf.writeln('| # | t | mode | from→to | bpm | dur |');
  buf.writeln('|--:|--:|------|---------|----:|----:|');
  for (var i = 0; i < config.length; i++) {
    final s = config[i];
    final ampl = _amplitudeKey(s.mode, s.from, s.to);
    buf.writeln(
        '| ${i + 1} | ${s.time} | ${_modeName(s.mode)} | $ampl | ${s.bpm ?? '-'} | ${s.duration ?? '-'} |');
  }
  buf.writeln();
  buf.writeln('---');
  buf.writeln();

  return buf.toString();
}

void main() {
  test('audit patterns intra-session — dump markdown', () {
    _addScenariosWithSpec();

    final buf = StringBuffer();
    buf.writeln('# Audit patterns de sessions BeatBitch');
    buf.writeln();
    buf.writeln('Généré par `test/audit_session_patterns_test.dart`. '
        'Seed déterministe `42`. ${_scenarios.length} scénarios.');
    buf.writeln();

    final allFlags = <String, List<_PatternFlag>>{};

    for (final sc in _scenarios) {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: sc.level,
        bank: _bank(),
        durationSeconds: sc.durationSeconds,
        humiliationCareer: sc.humilCareer,
        obedience: sc.obedience,
        unlockedKeys: sc.unlocks,
        specialization: sc.spec ?? SpecializationAllocation.empty(),
      );
      final flags = _analyze(result.session.steps, sc);
      allFlags[sc.name] = flags;
      buf.write(_renderScenario(sc, result.session.steps, flags));
    }

    // Récap final
    buf.writeln('## Synthèse');
    buf.writeln();
    var totalFlags = 0;
    for (final entry in allFlags.entries) {
      if (entry.value.isEmpty) continue;
      buf.writeln('- **${entry.key}** : ${entry.value.length} flag(s)');
      for (final f in entry.value) {
        buf.writeln('  - ${f.label}');
      }
      totalFlags += entry.value.length;
    }
    if (totalFlags == 0) {
      buf.writeln('Aucun pattern problématique détecté sur l\'échantillon.');
    } else {
      buf.writeln();
      buf.writeln(
          '**Total : $totalFlags flag(s) sur ${_scenarios.length} scénarios.**');
    }

    final outPath = '/tmp/audit_session_patterns.md';
    File(outPath).writeAsStringSync(buf.toString());
    // ignore: avoid_print
    print('Rapport audit écrit dans $outPath');

    // Sanity check minimal : la suite doit produire des steps
    expect(allFlags.length, _scenarios.length);
  });
}
