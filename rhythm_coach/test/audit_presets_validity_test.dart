// Audit des sessions préenregistrées (`assets/sessions/*.json`).
//
// Charge chaque fichier, parse via `Session.fromJson`, et valide la
// cohérence des steps : timestamps monotones, modes valides, amplitudes
// `from < to`, durées positives, BPM cohérent, dernier step ≤ durée
// totale.
//
// **Pas un test bloquant** : la sortie est un markdown dans
// `/tmp/audit_presets.md`. Le test ne fail que sur erreur catastrophique
// (parse impossible) — les anomalies de cohérence sont rapportées en
// flags, à arbitrer manuellement.
//
// Lancer : `flutter test test/audit_presets_validity_test.dart`

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/models/session.dart';

class _Flag {
  final String label;
  final String detail;
  const _Flag(this.label, this.detail);
}

const _amplitudeModes = <SessionMode>{
  SessionMode.rhythm,
  SessionMode.lick,
  SessionMode.hand,
};

const _modesNeedingDuration = <SessionMode>{
  SessionMode.hold,
  SessionMode.breath,
  SessionMode.freestyle,
};

const _rhythmicModes = <SessionMode>{
  SessionMode.rhythm,
  SessionMode.lick,
  SessionMode.hand,
  SessionMode.biffle,
};

List<_Flag> _validate(Session s) {
  final flags = <_Flag>[];
  if (s.steps.isEmpty) {
    flags.add(const _Flag('EMPTY-STEPS', 'aucun step dans la session'));
    return flags;
  }

  // 1. Timestamps monotones croissants
  for (var i = 1; i < s.steps.length; i++) {
    final prev = s.steps[i - 1];
    final cur = s.steps[i];
    if (cur.time < prev.time) {
      flags.add(_Flag(
        'TIME-DESC',
        'step #$i t=${cur.time} < step #${i - 1} t=${prev.time}',
      ));
      break; // un seul flag pour ne pas spammer
    }
  }

  // 2. Dernier step dans la fenêtre durationSeconds
  final last = s.steps.last;
  final lastEnd = last.time + (last.duration ?? 0);
  if (lastEnd > s.durationSeconds + 5) {
    flags.add(_Flag(
      'STEP-OVERSHOOT',
      'dernier step finit à t=$lastEnd mais durée totale ${s.durationSeconds}s',
    ));
  }

  // 3. Validation step par step
  for (var i = 0; i < s.steps.length; i++) {
    final step = s.steps[i];
    final mode = step.mode ?? s.defaultMode;

    // Amplitude `from < to` pour modes amplitude
    if (_amplitudeModes.contains(mode) &&
        step.from != null &&
        step.to != null) {
      if (step.from!.index >= step.to!.index) {
        flags.add(_Flag(
          'AMPL-INV',
          'step #$i ($mode) from=${step.from!.name} '
              '≥ to=${step.to!.name} (amplitude inversée ou nulle)',
        ));
      }
    }

    // Mode hold : besoin de `to` (la position tenue)
    if (mode == SessionMode.hold && step.to == null && !step.isTextOnly) {
      flags.add(_Flag(
        'HOLD-NO-POS',
        'step #$i (hold) sans `to` — quelle position tenue ?',
      ));
    }

    // Durée présente pour modes qui en ont besoin
    if (_modesNeedingDuration.contains(mode) &&
        !step.isTextOnly &&
        (step.duration == null || step.duration! <= 0)) {
      flags.add(_Flag(
        'DUR-MISSING',
        'step #$i ($mode) sans `duration` valide',
      ));
    }

    // BPM cohérent pour modes rythmés non text-only
    if (_rhythmicModes.contains(mode) &&
        !step.isTextOnly &&
        step.bpm != null &&
        (step.bpm! < 20 || step.bpm! > 250)) {
      flags.add(_Flag(
        'BPM-RANGE',
        'step #$i ($mode) bpm=${step.bpm} hors plage usuelle [20..250]',
      ));
    }
  }

  return flags;
}

String _renderSession(String filename, Session s, List<_Flag> flags) {
  final buf = StringBuffer();
  buf.writeln('## $filename');
  buf.writeln();
  buf.writeln('- id=`${s.id}`, lang=`${s.lang}`, durée ${s.durationSeconds}s, '
      'mode défaut=`${s.defaultMode.name}`');
  buf.writeln('- ${s.steps.length} steps');
  buf.writeln();

  // Distribution modes
  final modeCounts = <SessionMode, int>{};
  for (final st in s.steps) {
    final m = st.mode ?? s.defaultMode;
    modeCounts[m] = (modeCounts[m] ?? 0) + 1;
  }
  buf.writeln('### Modes');
  buf.writeln();
  final sorted = modeCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    buf.writeln('- `${e.key.name}` × ${e.value}');
  }
  buf.writeln();

  if (flags.isEmpty) {
    buf.writeln('### ✓ Valide');
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
  test('audit presets — chargement + cohérence', () {
    final dir = Directory('${Directory.current.path}/assets/sessions');
    // Filtre : on exclut les fichiers backup `_orig` / `_ps1` qui ne sont
    // pas dans `SessionLoader._assetPaths`. `session_camera_test` reste
    // (utilisé par `CameraTestScreen` en mode debug Android).
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .where((f) {
      final name = f.path.split('/').last;
      return !name.contains('_orig.') && !name.contains('_ps1.');
    }).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(files, isNotEmpty,
        reason: 'aucun preset trouvé dans assets/sessions');

    final buf = StringBuffer();
    buf.writeln('# Audit des sessions préenregistrées');
    buf.writeln();
    buf.writeln('Généré par `test/audit_presets_validity_test.dart`. '
        '${files.length} fichiers analysés.');
    buf.writeln();

    final allFlags = <String, List<_Flag>>{};
    final loadErrors = <String, String>{};

    for (final f in files) {
      final filename = f.path.split('/').last;
      try {
        final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final session = Session.fromJson(raw);
        final flags = _validate(session);
        allFlags[filename] = flags;
        buf.write(_renderSession(filename, session, flags));
      } catch (e, st) {
        loadErrors[filename] = '$e\n$st';
        buf.writeln('## $filename');
        buf.writeln();
        buf.writeln('### ❌ Échec de parsing');
        buf.writeln();
        buf.writeln('```');
        buf.writeln('$e');
        buf.writeln('```');
        buf.writeln();
        buf.writeln('---');
        buf.writeln();
      }
    }

    // Synthèse
    buf.writeln('## Synthèse');
    buf.writeln();
    final clean = allFlags.entries.where((e) => e.value.isEmpty).length;
    final dirty = allFlags.entries.where((e) => e.value.isNotEmpty).length;
    buf.writeln('- ✓ $clean/${files.length} presets sans anomalie');
    if (dirty > 0) {
      buf.writeln('- ⚠ $dirty preset(s) avec anomalies :');
      for (final entry in allFlags.entries) {
        if (entry.value.isEmpty) continue;
        buf.writeln('  - **${entry.key}** : '
            '${entry.value.map((f) => f.label).join(', ')}');
      }
    }
    if (loadErrors.isNotEmpty) {
      buf.writeln('- ❌ ${loadErrors.length} preset(s) impossibles à parser :');
      for (final name in loadErrors.keys) {
        buf.writeln('  - $name');
      }
    }

    const outPath = '/tmp/audit_presets.md';
    File(outPath).writeAsStringSync(buf.toString());
    // ignore: avoid_print
    print('Rapport audit écrit dans $outPath');

    // On fail uniquement sur erreur catastrophique (parse impossible).
    expect(loadErrors, isEmpty,
        reason: 'certains presets ne se chargent pas : ${loadErrors.keys}');
  });
}
