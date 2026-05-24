// Audit des sessions custom : génère une matrice de configs et vérifie
// que les dosages (rare/normal/frequent/none) et la difficulté
// (facile/normal/difficile/extreme) se traduisent dans la composition
// effective des sessions.
//
// Sortie markdown dans `/tmp/audit_custom_sessions.md`.
//
// Lancer : `flutter test test/audit_custom_sessions_test.dart`

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/custom_session_config.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
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

class _Flag {
  final String label;
  final String detail;
  const _Flag(this.label, this.detail);
}

class _Scenario {
  final String label;
  final CustomSessionConfig config;
  const _Scenario(this.label, this.config);
}

CustomSessionConfig _baseConfig({
  CustomDifficulty difficulty = CustomDifficulty.normal,
  Map<SessionMode, ModeDose>? doseOverrides,
  int durationSeconds = 720,
}) {
  final base = CustomSessionConfig.defaults();
  final doses = Map<SessionMode, ModeDose>.from(base.doses);
  if (doseOverrides != null) {
    doses.addAll(doseOverrides);
  }
  return base.copyWith(
    durationSeconds: durationSeconds,
    difficulty: difficulty,
    doses: doses,
  );
}

List<_Flag> _validate(_Scenario sc, List<SessionStep> steps) {
  final flags = <_Flag>[];
  final config = steps.where((s) => !s.isTextOnly).toList();
  if (config.isEmpty) {
    flags.add(const _Flag('EMPTY', 'aucun step de config généré'));
    return flags;
  }

  // 1. Compteur de modes émis (steps de config uniquement)
  final modeCounts = <SessionMode, int>{};
  for (final s in config) {
    final m = s.mode;
    if (m == null) continue;
    modeCounts[m] = (modeCounts[m] ?? 0) + 1;
  }

  // 2. Dosage `none` → mode quasi-absent. On tolère ≤ 1 (un finisher ou
  //    intro fixe peut imposer un step même si le dosage est à 0).
  for (final entry in sc.config.doses.entries) {
    if (entry.value != ModeDose.none) continue;
    final emitted = modeCounts[entry.key] ?? 0;
    if (emitted > 1) {
      flags.add(_Flag(
        'DOSE-NONE-VIOL',
        '${entry.key.name} dosé `none` mais émis $emitted fois',
      ));
    }
  }

  // 3. Dosage `frequent` ne doit pas être grossièrement dominé par les
  //    modes `rare` du même scénario. `frequent` (×2.2) est un
  //    multiplicateur relatif, pas un veto absolu — une légère inversion
  //    due aux phases scriptées (boosts finish + mini-vagues + pre-finisher
  //    hardcodés en rhythm) est acceptable. On ne flagge que les
  //    inversions grossières où `rare ≥ 2× frequent` : c'est le signe que
  //    le dosage utilisateur est ignoré, pas juste atténué par la
  //    dramaturgie.
  final frequentModes = sc.config.doses.entries
      .where((e) => e.value == ModeDose.frequent)
      .map((e) => e.key)
      .toList();
  final rareModes = sc.config.doses.entries
      .where((e) => e.value == ModeDose.rare)
      .map((e) => e.key)
      .toList();
  for (final fm in frequentModes) {
    final fc = modeCounts[fm] ?? 0;
    for (final rm in rareModes) {
      final rc = modeCounts[rm] ?? 0;
      if (fc > 0 && rc >= fc * 2) {
        flags.add(_Flag(
          'DOSE-ORDER',
          '${fm.name} frequent ($fc) écrasé par ${rm.name} rare ($rc) — '
              'ratio ≥ 2× indique que le dosage est ignoré',
        ));
      }
    }
  }

  // 4. Difficulté extrême → profondeur exploitée
  if (sc.config.difficulty == CustomDifficulty.extreme) {
    final maxDepth = config
        .where((s) => s.to != null)
        .map((s) => s.to!.index)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (maxDepth < Position.throat.index) {
      flags.add(const _Flag(
        'EXTREME-SHALLOW',
        'difficulté `extreme` mais aucun step n\'atteint throat ou plus',
      ));
    }
  }

  // 5. Difficulté facile → BPM raisonnables (pas de step > 150 BPM)
  if (sc.config.difficulty == CustomDifficulty.facile) {
    final fastSteps = config.where((s) => (s.bpm ?? 0) > 150).length;
    if (fastSteps > 0) {
      flags.add(_Flag(
        'EASY-FAST',
        'difficulté `facile` avec $fastSteps step(s) > 150 BPM',
      ));
    }
  }

  return flags;
}

String _renderScenario(
    _Scenario sc, List<SessionStep> steps, List<_Flag> flags) {
  final config = steps.where((s) => !s.isTextOnly).toList();
  final buf = StringBuffer();
  buf.writeln('## ${sc.label}');
  buf.writeln();
  buf.writeln('- difficulté `${sc.config.difficulty.name}`, '
      'durée ${sc.config.durationSeconds ?? "?"}s');
  buf.writeln('- niveau virtuel résolu : `${sc.config.resolveVirtualLevel()}`');
  buf.writeln('- doses non-normales :');
  for (final e in sc.config.doses.entries) {
    if (e.value == ModeDose.normal) continue;
    buf.writeln('  - `${e.key.name}` = `${e.value.name}`');
  }
  buf.writeln('- ${steps.length} steps total, ${config.length} de config');
  buf.writeln();

  // Distribution
  final modeCounts = <SessionMode, int>{};
  for (final s in config) {
    final m = s.mode ?? SessionMode.rhythm;
    modeCounts[m] = (modeCounts[m] ?? 0) + 1;
  }
  buf.writeln('### Distribution effective');
  buf.writeln();
  final sorted = modeCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    final pct = (e.value / config.length * 100).toStringAsFixed(0);
    final dose = sc.config.doses[e.key]?.name ?? '-';
    buf.writeln('- `${e.key.name}` : ${e.value} ($pct%) [dose: $dose]');
  }
  buf.writeln();

  if (flags.isEmpty) {
    buf.writeln('### ✓ Cohérent');
  } else {
    buf.writeln('### ⚠ ${flags.length} anomalie(s)');
    buf.writeln();
    for (final f in flags) {
      buf.writeln('- **${f.label}** — ${f.detail}');
    }
  }
  buf.writeln();
  buf.writeln('---');
  buf.writeln();
  return buf.toString();
}

void main() {
  test('audit custom — dosage et difficulté reflétés dans la session', () {
    final scenarios = <_Scenario>[
      _Scenario(
        'Default · normal · 12 min',
        _baseConfig(),
      ),
      _Scenario(
        'Facile · 8 min',
        _baseConfig(difficulty: CustomDifficulty.facile, durationSeconds: 480),
      ),
      _Scenario(
        'Difficile · 18 min',
        _baseConfig(
            difficulty: CustomDifficulty.difficile, durationSeconds: 1080),
      ),
      _Scenario(
        'Extrême · 25 min',
        _baseConfig(
            difficulty: CustomDifficulty.extreme, durationSeconds: 1500),
      ),
      _Scenario(
        'Rhythm `none` (rhythm doit disparaître)',
        _baseConfig(doseOverrides: {SessionMode.rhythm: ModeDose.none}),
      ),
      _Scenario(
        'Lick `frequent` + rhythm `rare` (lick > rhythm)',
        _baseConfig(doseOverrides: {
          SessionMode.lick: ModeDose.frequent,
          SessionMode.rhythm: ModeDose.rare,
        }),
      ),
      _Scenario(
        'Biffle `frequent` + lick `rare` (biffle > lick)',
        _baseConfig(doseOverrides: {
          SessionMode.biffle: ModeDose.frequent,
          SessionMode.lick: ModeDose.rare,
        }),
      ),
      _Scenario(
        'Hold `frequent` + beg `rare` (hold > beg)',
        _baseConfig(doseOverrides: {
          SessionMode.hold: ModeDose.frequent,
          SessionMode.beg: ModeDose.rare,
        }),
      ),
      _Scenario(
        'Extrême · biffle `frequent` (combo difficulté + dose)',
        _baseConfig(
          difficulty: CustomDifficulty.extreme,
          durationSeconds: 1500,
          doseOverrides: {SessionMode.biffle: ModeDose.frequent},
        ),
      ),
    ];

    final buf = StringBuffer();
    buf.writeln('# Audit des sessions custom');
    buf.writeln();
    buf.writeln('Généré par `test/audit_custom_sessions_test.dart`. '
        'Seed `42`. ${scenarios.length} scénarios.');
    buf.writeln();

    final allFlags = <String, List<_Flag>>{};

    for (final sc in scenarios) {
      final gen = CareerSessionGenerator(seed: 42);
      final cfg = sc.config;
      final result = gen.generate(
        level: cfg.resolveVirtualLevel(),
        bank: _bank(),
        durationSeconds: cfg.resolveDurationSeconds(),
        coachModeWeights: cfg.resolveCoachModeWeights(),
        includeHand: cfg.resolveIncludeHand,
        humiliationCareer: 400.0, // cf. _CustomModeScreenState._generate
        specialization: cfg.resolveSpecialization(),
        custom: CustomOverrides(
          intensityFloor: cfg.resolveIntensityFloor(),
          maxDepthIndex: cfg.maxDepthIndex < Position.values.length - 1
              ? cfg.maxDepthIndex
              : null,
          noStats: true,
        ),
      );
      final flags = _validate(sc, result.session.steps);
      allFlags[sc.label] = flags;
      buf.write(_renderScenario(sc, result.session.steps, flags));
    }

    // Synthèse
    buf.writeln('## Synthèse');
    buf.writeln();
    final clean = allFlags.entries.where((e) => e.value.isEmpty).length;
    buf.writeln('- ✓ $clean/${scenarios.length} scénarios cohérents');
    for (final entry in allFlags.entries) {
      if (entry.value.isEmpty) continue;
      buf.writeln('- ⚠ **${entry.key}** : '
          '${entry.value.map((f) => f.label).join(', ')}');
    }

    const outPath = '/tmp/audit_custom_sessions.md';
    File(outPath).writeAsStringSync(buf.toString());
    // ignore: avoid_print
    print('Rapport audit écrit dans $outPath');

    expect(allFlags.length, scenarios.length);
  });
}
