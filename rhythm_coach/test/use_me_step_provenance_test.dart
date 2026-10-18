import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:flutter_test/flutter_test.dart';

/// tss2-037 : le régime « Utilise-moi » est porté par le step, posé là où la
/// timeline est remplacée par l'escalade.
void main() {
  const rhythm = SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 280);
  const beg = SessionStep(time: 0, mode: SessionMode.beg, duration: 2);
  const hold = SessionStep(
      time: 5, mode: SessionMode.hold, to: Position.full, duration: 4);

  Session session(List<SessionStep> steps) => Session(
        id: 's',
        name: 's',
        description: '',
        durationSeconds: 60,
        defaultMode: SessionMode.rhythm,
        steps: steps,
      );

  Session upgraded(List<SessionStep> upcoming, {required bool useMe}) =>
      SessionController.buildUpgradedSession(
        previous: session(const [rhythm]),
        upcoming: session(upcoming),
        insistentBeg: beg,
        start: 10,
        useMe: useMe,
      );

  test('l\'escalade marque le beg insistant et chaque step de la suite', () {
    final s = upgraded(const [rhythm, hold], useMe: true);
    expect(s.steps, hasLength(3));
    expect(s.steps.every((st) => st.useMe), isTrue);
  });

  test('une suite normale ne porte pas le régime « Utilise-moi »', () {
    final s = upgraded(const [rhythm, hold], useMe: false);
    expect(s.steps, hasLength(3));
    expect(s.steps.any((st) => st.useMe), isFalse);
  });

  test('un rebase garde la provenance du step', () {
    const venu = SessionStep(time: 0, mode: SessionMode.rhythm, useMe: true);
    expect(venu.rebased(7).useMe, isTrue);
    expect(rhythm.rebased(7).useMe, isFalse);
  });

  test('la provenance survit à un aller-retour JSON', () {
    const venu = SessionStep(time: 0, mode: SessionMode.rhythm, useMe: true);
    expect(SessionStep.fromJson(venu.toJson()).useMe, isTrue);
    expect(SessionStep.fromJson(rhythm.toJson()).useMe, isFalse);
  });
}
