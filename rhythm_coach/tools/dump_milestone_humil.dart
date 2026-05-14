import 'dart:convert';
import 'dart:io';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';

/// Dumpe pour chaque milestone son `humilRequired` calculé (via
/// `HumiliationScale.requiredFor` sur la séquence — reproduction exacte
/// de la logique `MilestoneLoader._computeHumilRequired`), son
/// `minLevel`, ses `branches`, son `requiresCapability` et la liste de
/// ses `requires`. Sert à vérifier que l'ordre des paliers tient face à
/// la montée rapide humil/obed/capacités (cf. passe 2 du handoff
/// `~/beatbitch_career_unlocks_handoff.md`).
///
/// Usage : `dart run tools/dump_milestone_humil.dart` depuis
/// `rhythm_coach/`. Sort un tableau aligné sur stdout.
void main() {
  final file = File('assets/career/milestones.json');
  if (!file.existsSync()) {
    stderr.writeln('assets/career/milestones.json absent — run from '
        'rhythm_coach/');
    exit(2);
  }

  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final milestones =
      (raw['milestones'] as List).cast<Map<String, dynamic>>().toList();

  final rows = <_Row>[];
  for (final m in milestones) {
    final id = m['id'] as String;
    final level = (m['level'] as num?)?.toInt() ?? 1;
    final placement = (m['placement'] as String? ?? 'body');
    final branches =
        (m['branches'] as List? ?? const []).cast<String>().join(',');
    final requires = (m['requires'] as List? ?? const []).cast<String>();
    final caps = (m['requiresCapability'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((c) => '${c['axis']}≥${c['min']}')
        .join(', ');
    final seq = (m['sequence'] as List).cast<Map<String, dynamic>>();
    final expanded = <SessionStep>[];
    for (final s in seq) {
      final parent = SessionStep.fromJson(s);
      expanded.add(parent);
      final chain = parent.chainAction;
      if (chain != null) {
        expanded.add(SessionStep(
          time: parent.time + (parent.duration ?? 0),
          text: chain.text,
          from: chain.from,
          to: chain.to,
          bpm: chain.bpm,
          duration: chain.duration,
          mode: chain.mode,
        ));
      }
    }
    final humil = _humilRequired(expanded);
    rows.add(_Row(
      id: id,
      level: level,
      placement: placement,
      humil: humil,
      branches: branches,
      caps: caps,
      requires: requires.join(','),
    ));
  }

  // Tri principal : (placement, humil asc, level asc, id) pour vérifier
  // visuellement la montée. Les `body` d'abord, puis les `final`.
  rows.sort((a, b) {
    final byPlacement = a.placement.compareTo(b.placement);
    if (byPlacement != 0) return byPlacement;
    final byHumil = a.humil.compareTo(b.humil);
    if (byHumil != 0) return byHumil;
    final byLevel = a.level.compareTo(b.level);
    if (byLevel != 0) return byLevel;
    return a.id.compareTo(b.id);
  });

  // Largeurs colonnes
  final wId = rows.map((r) => r.id.length).fold<int>(2, max);
  final wBr = rows.map((r) => r.branches.length).fold<int>(8, max);
  final wCp = rows.map((r) => r.caps.length).fold<int>(20, max);
  final wRq = rows.map((r) => r.requires.length).fold<int>(8, max);

  String pad(String s, int w) => s.padRight(w);

  final header = '${pad('id', wId)}  lvl  humil  pl   ${pad('branches', wBr)}'
      '  ${pad('requiresCapability', wCp)}  ${pad('requires', wRq)}';
  stdout.writeln(header);
  stdout.writeln('-' * header.length);
  for (final r in rows) {
    stdout.writeln('${pad(r.id, wId)}  ${r.level.toString().padLeft(3)}  '
        '${r.humil.toStringAsFixed(1).padLeft(5)}  '
        '${r.placement.substring(0, 2)}   '
        '${pad(r.branches, wBr)}  ${pad(r.caps, wCp)}  ${pad(r.requires, wRq)}');
  }
}

int max(int a, int b) => a > b ? a : b;

/// Reproduit `MilestoneLoader._computeHumilRequired` — agrégation des
/// holds consécutifs sur la même position, sinon évaluation step par
/// step via `HumiliationScale.requiredFor`.
double _humilRequired(List<SessionStep> sequence) {
  var maxV = 0.0;
  Position? chainTo;
  int chainDur = 0;

  void flush() {
    if (chainTo == null) return;
    final r = HumiliationScale.requiredFor(
      mode: SessionMode.hold,
      to: chainTo,
      duration: chainDur,
    );
    if (r > maxV) maxV = r;
    chainTo = null;
    chainDur = 0;
  }

  for (final s in sequence) {
    final mode = s.mode ?? SessionMode.rhythm;
    if (mode == SessionMode.hold && s.to != null) {
      if (chainTo == s.to) {
        chainDur += s.duration ?? 0;
      } else {
        flush();
        chainTo = s.to;
        chainDur = s.duration ?? 0;
      }
      continue;
    }
    flush();
    final r = HumiliationScale.requiredFor(
      mode: mode,
      from: s.from,
      to: s.to,
      bpm: s.bpm,
      duration: s.duration,
    );
    if (r > maxV) maxV = r;
  }
  flush();
  return maxV;
}

class _Row {
  final String id;
  final int level;
  final String placement;
  final double humil;
  final String branches;
  final String caps;
  final String requires;

  _Row({
    required this.id,
    required this.level,
    required this.placement,
    required this.humil,
    required this.branches,
    required this.caps,
    required this.requires,
  });
}
