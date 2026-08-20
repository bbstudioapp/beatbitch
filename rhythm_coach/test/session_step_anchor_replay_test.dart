import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

List<PhraseEntry> _p(List<String> t) =>
    t.map((x) => PhraseEntry(text: x)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'finale': _p(['f']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

Session _generated() => CareerSessionGenerator(seed: 42)
    .generate(
      level: 25,
      bank: _bank(),
      unlockedKeys: UnlockKey.values.toSet(),
      humiliationCareer: 400.0,
    )
    .session;

/// Chantier aimant : l'ancre est portée par le `SessionStep` précisément
/// pour survivre aux chemins qui rejouent la suite d'une séance sans
/// repasser par le générateur. Les deux helpers purs qui reconstruisent
/// ces steps recopient champ à champ — sans `anchor`/`ratio`, toute la
/// suite de la séance redevient métronomique après un Supplier, un retry
/// milestone ou un défi.
void main() {
  test('reprise Supplier / retry milestone : l\'ancre survit au rebase', () {
    final session = _generated();
    final before = <int, (BeatAnchor, int)>{
      for (final s in session.steps)
        if (s.anchor != BeatAnchor.none) s.time: (s.anchor, s.ratio),
    };
    expect(before, isNotEmpty,
        reason: 'la séance générée doit porter des steps ancrés');

    final upgraded = SessionController.buildUpgradedSession(
      previous: session,
      upcoming: session,
      insistentBeg: const SessionStep(
          time: 0, mode: SessionMode.beg, to: Position.mid, duration: 12),
      start: 60,
    );
    final kept = upgraded.steps.where((s) => s.anchor != BeatAnchor.none);
    expect(kept.length, before.length);
    for (final s in kept) {
      expect(s.ratio, 3, reason: 't=${s.time}');
    }
  });

  test('régénération post-défi : l\'ancre survit au rebase', () {
    final session = _generated();
    final anchored =
        session.steps.where((s) => s.anchor != BeatAnchor.none).toList();
    expect(anchored, isNotEmpty);

    final regen = SessionController.buildPostChallengeRegenSession(
      previous: session,
      upcoming: session,
      breathEnd: 30,
    );
    expect(regen.steps.where((s) => s.anchor != BeatAnchor.none).length,
        anchored.length);
    expect(
      regen.steps.where((s) => s.anchor == BeatAnchor.to).length,
      anchored.where((s) => s.anchor == BeatAnchor.to).length,
    );
  });

  test('sauvegarde/relecture JSON : l\'ancre survit à la sérialisation', () {
    final session = _generated();
    final anchored =
        session.steps.where((s) => s.anchor != BeatAnchor.none).toList();
    expect(anchored, isNotEmpty);

    final reread = Session.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>);
    expect(reread.steps.length, session.steps.length);
    for (var i = 0; i < session.steps.length; i++) {
      expect(reread.steps[i].anchor, session.steps[i].anchor,
          reason: 'step $i t=${session.steps[i].time}');
      expect(reread.steps[i].ratio, session.steps[i].ratio,
          reason: 'step $i t=${session.steps[i].time}');
    }
  });
}
