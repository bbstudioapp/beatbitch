/// Tests unitaires de `SessionConfig` — value object des inputs figés d'une
/// séance. Couvre les méthodes dérivées pures (pas la génération).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/generation/session_config.dart';
import 'package:beat_bitch/models/anatomy_profile.dart';
import 'package:beat_bitch/models/session.dart';

SessionConfig _config({
  bool includeHand = true,
  Map<SessionMode, double> coachModeWeights = const {},
}) {
  return SessionConfig(
    level: 5,
    includeHand: includeHand,
    maxDepthIndex: 4,
    spec: SpecializationAllocation.empty(),
    anatomy: AnatomyProfile.defaults,
    coachModeWeights: coachModeWeights,
    bpmRange: null,
    holdDurationRange: null,
    humiliationCareer: 0.0,
    humiliationSession: 0.0,
    obedience: 0.0,
    capProfile: null,
    capCeilings: const {},
    overloadAxis: null,
    overloadFactor: 1.0,
  );
}

void main() {
  group('SessionConfig.isModeForbidden', () {
    test('coachModeWeights[m] == 0 → forbidden (cas Custom dose `none`)', () {
      final cfg = _config(coachModeWeights: {SessionMode.lick: 0.0});
      expect(cfg.isModeForbidden(SessionMode.lick), isTrue);
      expect(cfg.isModeForbidden(SessionMode.rhythm), isFalse);
    });

    test('coachModeWeights[m] > 0 → autorisé', () {
      final cfg = _config(coachModeWeights: {SessionMode.lick: 1.5});
      expect(cfg.isModeForbidden(SessionMode.lick), isFalse);
    });

    test('coachModeWeights absent → autorisé (cas carrière standard)', () {
      final cfg = _config();
      expect(cfg.isModeForbidden(SessionMode.lick), isFalse);
      expect(cfg.isModeForbidden(SessionMode.rhythm), isFalse);
    });

    test('includeHand: false → hand forbidden (toggle joueuse carrière)', () {
      final cfg = _config(includeHand: false);
      expect(cfg.isModeForbidden(SessionMode.hand), isTrue);
    });

    test(
      'includeHand: false → biffle forbidden (biffle implique la main)',
      () {
        final cfg = _config(includeHand: false);
        expect(cfg.isModeForbidden(SessionMode.biffle), isTrue);
      },
    );

    test('includeHand: false → autres modes restent autorisés', () {
      final cfg = _config(includeHand: false);
      expect(cfg.isModeForbidden(SessionMode.rhythm), isFalse);
      expect(cfg.isModeForbidden(SessionMode.lick), isFalse);
      expect(cfg.isModeForbidden(SessionMode.hold), isFalse);
      expect(cfg.isModeForbidden(SessionMode.breath), isFalse);
    });

    test('includeHand: true → hand et biffle autorisés (par défaut)', () {
      final cfg = _config();
      expect(cfg.isModeForbidden(SessionMode.hand), isFalse);
      expect(cfg.isModeForbidden(SessionMode.biffle), isFalse);
    });
  });
}
