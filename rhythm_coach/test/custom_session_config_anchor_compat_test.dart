import 'package:beat_bitch/career/models/custom_session_config.dart';
import 'package:beat_bitch/models/session.dart' show SessionMode;
import 'package:beat_bitch/models/session_step.dart' show BeatAnchor;
import 'package:flutter_test/flutter_test.dart';

/// Une config Custom enregistrée avant le chantier aimant : aucune des
/// trois clés `anchor_*`. Le schéma est celui que `toJson` produisait
/// alors — c'est par cette absence que la compatibilité se prouve.
Map<String, dynamic> _legacyJson() => {
      'id': 'custom_1700000000000',
      'name': 'Ma séance',
      'lang': 'fr',
      'duration_seconds': 900,
      'non_stop': false,
      'cycle_duration_seconds': 600,
      'progressive_difficulty': false,
      'difficulty': 'difficile',
      'include_hand': true,
      'max_depth_index': 4,
      'bpm_min': 50,
      'bpm_max': 160,
      'hold_duration_min': 5,
      'hold_duration_max': 60,
      'doses': {
        for (final m in SessionMode.values) m.serialized: 'normal',
      },
    };

void main() {
  group('config enregistrée avant le chantier aimant', () {
    test('s\'ouvre avec l\'aimant éteint', () {
      final cfg = CustomSessionConfig.fromJson(_legacyJson());
      expect(cfg.anchorEnabled, isFalse);
      expect(cfg.resolveAnchor(), isNull,
          reason: 'sans surcharge, le générateur garde sa décision d\'ancrage '
              '— la séance rejoue à l\'identique');
    });

    test('garde tous ses autres réglages', () {
      final cfg = CustomSessionConfig.fromJson(_legacyJson());
      expect(cfg.id, 'custom_1700000000000');
      expect(cfg.name, 'Ma séance');
      expect(cfg.durationSeconds, 900);
      expect(cfg.difficulty, CustomDifficulty.difficile);
      expect(cfg.bpmMin, 50);
      expect(cfg.bpmMax, 160);
      expect(cfg.holdDurationMin, 5);
      expect(cfg.holdDurationMax, 60);
    });

    test('une valeur d\'aimant illisible retombe sur le défaut', () {
      final cfg = CustomSessionConfig.fromJson({
        ..._legacyJson(),
        'anchor_enabled': true,
        'anchor_strength': 'colossal',
        'anchor_point': 'none',
      });
      expect(cfg.anchorStrength, AnchorStrength.medium);
      expect(cfg.anchorPoint, BeatAnchor.from,
          reason: '`none` ne veut rien dire ici : l\'extinction passe par '
              'anchorEnabled');
    });
  });

  group('aller-retour JSON', () {
    test('conserve les trois réglages d\'aimant', () {
      for (final point in [BeatAnchor.from, BeatAnchor.to]) {
        for (final strength in AnchorStrength.values) {
          final source = CustomSessionConfig.defaults(id: 'c').copyWith(
            anchorEnabled: true,
            anchorPoint: point,
            anchorStrength: strength,
          );
          final back = CustomSessionConfig.fromJson(source.toJson());
          expect(back.anchorEnabled, isTrue);
          expect(back.anchorPoint, point);
          expect(back.anchorStrength, strength);
          expect(back.resolveAnchor(), source.resolveAnchor());
        }
      }
    });

    test('conserve un aimant éteint', () {
      final back = CustomSessionConfig.fromJson(
          CustomSessionConfig.defaults(id: 'c').toJson());
      expect(back.anchorEnabled, isFalse);
      expect(back.resolveAnchor(), isNull);
    });
  });

  group('copyWith', () {
    test('reporte les trois réglages quand on ne les touche pas', () {
      final source = CustomSessionConfig.defaults(id: 'c').copyWith(
        anchorEnabled: true,
        anchorPoint: BeatAnchor.to,
        anchorStrength: AnchorStrength.hard,
      );
      final renamed = source.copyWith(name: 'autre nom');
      expect(renamed.anchorEnabled, isTrue);
      expect(renamed.anchorPoint, BeatAnchor.to);
      expect(renamed.anchorStrength, AnchorStrength.hard);
    });
  });

  group('crans de force', () {
    test('sont ordonnés et restent en deçà du final « très dur » (9)', () {
      int ratioOf(AnchorStrength s) => CustomSessionConfig.defaults(id: 'c')
          .copyWith(anchorEnabled: true, anchorStrength: s)
          .resolveAnchor()!
          .$2;
      final light = ratioOf(AnchorStrength.light);
      final medium = ratioOf(AnchorStrength.medium);
      final hard = ratioOf(AnchorStrength.hard);
      expect(light, greaterThan(1),
          reason: 'un ratio ≤ 1 rend l\'intervalle nul ou négatif '
              '(BeepEngine._intervalAfter)');
      expect(light, lessThan(medium));
      expect(medium, lessThan(hard));
      expect(hard, lessThan(9));
    });
  });
}
