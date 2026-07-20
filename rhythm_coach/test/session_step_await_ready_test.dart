import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';

/// Contrat du champ `awaitReady` (gate de validation posture, issue #77) :
/// parsé depuis le JSON et préservé au round-trip — garde-fou contre une
/// reconstruction de step qui l'oublierait (ex. `_pushMilestoneSequence`).
void main() {
  test('awaitReady : parsé depuis JSON (true / absent / snake_case)', () {
    expect(
      SessionStep.fromJson({'time': 0, 'mode': 'breath', 'awaitReady': true})
          .awaitReady,
      isTrue,
    );
    expect(
      SessionStep.fromJson({'time': 0, 'mode': 'breath'}).awaitReady,
      isFalse,
    );
    expect(
      SessionStep.fromJson({'time': 0, 'mode': 'breath', 'await_ready': true})
          .awaitReady,
      isTrue,
    );
  });

  test('awaitReady : round-trip toJson → fromJson', () {
    const step = SessionStep(
      time: 3,
      text: 'Mets-toi en position.',
      mode: SessionMode.breath,
      duration: 8,
      awaitReady: true,
    );
    final restored = SessionStep.fromJson({'time': 3, ...step.toJson()});
    expect(restored.awaitReady, isTrue);
    // Un step ordinaire n'émet pas la clé (défaut false).
    expect(const SessionStep(time: 0).toJson().containsKey('awaitReady'),
        isFalse);
  });
}
