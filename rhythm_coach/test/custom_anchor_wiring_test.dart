import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/custom_session_config.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/session.dart' show Session, SessionMode;
import 'package:beat_bitch/models/session_step.dart'
    show BeatAnchor, SessionStep;
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

/// Rejoue `custom_mode_screen._generate` : mêmes arguments, même ordre,
/// seul le seed est figé. Une divergence ici ferait mentir toutes les
/// assertions du fichier — c'est le seul endroit qui décrit la séance.
Session _customSession(CustomSessionConfig cfg, {required int seed}) {
  return CareerSessionGenerator(seed: seed)
      .generate(
        level: cfg.resolveVirtualLevel(),
        bank: _bank(),
        durationSeconds: cfg.resolveDurationSeconds(),
        includeHand: cfg.resolveIncludeHand,
        encoreChainIndex: cfg.resolveEncoreChainIndex(),
        specialization: cfg.resolveSpecialization(),
        obedience: 100.0,
        humiliationCareer: 400.0,
        humiliationSession: 0.0,
        unlockedKeys: const {},
        coachModeWeights: cfg.resolveCoachModeWeights(),
        sessionName: 'test',
        custom: CustomOverrides(
          intensityFloor: cfg.resolveIntensityFloor(),
          bpmRange: (cfg.bpmMin, cfg.bpmMax),
          holdDurationRange: (cfg.holdDurationMin, cfg.holdDurationMax),
          anchor: cfg.resolveAnchor(),
          noStats: true,
        ),
      )
      .session;
}

String _fingerprint(List<SessionStep> steps) => steps
    .map((s) => '${s.time}/${s.mode?.serialized}/${s.from?.name}/${s.to?.name}/'
        '${s.bpm}/${s.duration}/${s.anchor.name}/${s.ratio}')
    .join('|');

const _seeds = [1, 7, 42];

/// Empreinte des steps ancrés d'une séance Custom **avant** l'exposition de
/// l'aimant dans l'éditeur (relevé sur le worktree, commit `65d47a7`).
/// Contrairement à ce qu'on pourrait croire, une séance Custom n'était pas
/// vierge d'ancres : le générateur en pose déjà depuis le niveau virtuel
/// (étape 3) et le final `hold` en reçoit une au-dessus du niveau 10
/// (étape 4). C'est cet état-là que l'aimant éteint doit reconduire.
const Map<String, String> _anchorsBeforeStep5 = {
  'facile/1': '693/rhythm/from/3 723/rhythm/from/3 738/rhythm/from/3',
  'facile/7': '684/rhythm/from/3',
  'facile/42': '715/rhythm/from/3 739/rhythm/from/3 754/rhythm/from/3',
  'normal/1': '352/rhythm/from/3 364/rhythm/from/3 374/rhythm/from/3 '
      '726/rhythm/from/3 742/rhythm/from/3 758/rhythm/from/3',
  'normal/7': '723/rhythm/from/3 738/rhythm/from/3 751/rhythm/from/3',
  'normal/42': '590/rhythm/from/3 602/rhythm/from/3 612/rhythm/from/3',
  'difficile/1': '557/rhythm/to/3 569/rhythm/to/3 579/rhythm/to/3 '
      '767/hold/to/9',
  'difficile/7': '426/rhythm/to/3 438/rhythm/to/3 448/rhythm/to/3 '
      '738/rhythm/to/3 753/rhythm/to/3 765/rhythm/to/3 777/rhythm/to/3 '
      '790/hold/to/9',
  'difficile/42': '356/rhythm/to/3 368/rhythm/to/3 378/rhythm/to/3 '
      '758/rhythm/to/3 774/rhythm/to/3 786/rhythm/to/3 802/rhythm/to/3 '
      '816/hold/to/9',
  'extreme/1': '305/rhythm/to/3 317/rhythm/to/3 327/rhythm/to/3 '
      '777/hold/to/9',
  'extreme/7': '439/rhythm/to/3 451/rhythm/to/3 461/rhythm/to/3 '
      '715/rhythm/to/3 731/rhythm/to/3 745/rhythm/to/3 761/rhythm/to/3 '
      '777/rhythm/to/3 793/hold/to/9',
  'extreme/42': '615/rhythm/to/3 627/rhythm/to/3 637/rhythm/to/3 '
      '721/rhythm/to/3 733/rhythm/to/3 748/rhythm/to/3 764/rhythm/to/3 '
      '778/rhythm/to/3 792/hold/to/9',
};

String _anchorTrace(List<SessionStep> steps) => steps
    .where((s) => s.anchor != BeatAnchor.none)
    .map((s) => '${s.time}/${s.mode?.serialized}/${s.anchor.name}/${s.ratio}')
    .join(' ');

void main() {
  group('aimant éteint (défaut)', () {
    test('reconduit exactement les ancres d\'avant l\'étape 5', () {
      final cfg0 = CustomSessionConfig.defaults(id: 'c');
      expect(cfg0.anchorEnabled, isFalse,
          reason: 'l\'aimant est une variation, pas le standard');
      expect(cfg0.resolveAnchor(), isNull);

      for (final difficulty in CustomDifficulty.values) {
        for (final seed in _seeds) {
          final session = _customSession(
            cfg0.copyWith(difficulty: difficulty),
            seed: seed,
          );
          expect(
            _anchorTrace(session.steps),
            _anchorsBeforeStep5['${difficulty.name}/$seed'],
            reason: 'difficulté ${difficulty.name}, seed $seed : une séance '
                'Custom sans aimant doit produire les mêmes ancres qu\'avant '
                'que le réglage existe',
          );
        }
      }
    });
  });

  group('aimant allumé', () {
    test(
        'ne change rien hors rhythm et hold, et ne touche pas au reste '
        'du step', () {
      final off = CustomSessionConfig.defaults(id: 'c')
          .copyWith(difficulty: CustomDifficulty.normal);
      final on = off.copyWith(
        anchorEnabled: true,
        anchorPoint: BeatAnchor.to,
        anchorStrength: AnchorStrength.hard,
      );
      for (final seed in _seeds) {
        // Les consignes de micro-mouvements sont des steps de texte seul : une
        // tenue ancrée n'en reçoit pas, le nombre de steps n'est pas comparable.
        final before = _configSteps(_customSession(off, seed: seed));
        final after = _configSteps(_customSession(on, seed: seed));
        expect(after.length, before.length,
            reason: 'l\'aimant ne doit pas déplacer le tirage (seed $seed)');
        for (var i = 0; i < before.length; i++) {
          final b = before[i], a = after[i];
          final anchorable =
              b.mode == SessionMode.rhythm || b.mode == SessionMode.hold;
          if (!anchorable) {
            expect(a.anchor, BeatAnchor.none,
                reason: 'step $i (${b.mode?.serialized}) ancré alors que seuls '
                    'rhythm et hold le peuvent');
            expect(a.ratio, 1);
          }
          expect(a.time, b.time);
          expect(a.mode, b.mode);
          expect(a.from, b.from);
          expect(a.to, b.to);
          expect(a.duration, b.duration);
        }
      }
    });

    test(
        'pose le point et la force choisis sur les steps rhythm du corps '
        'de séance', () {
      for (final point in [BeatAnchor.from, BeatAnchor.to]) {
        for (final strength in AnchorStrength.values) {
          final off = CustomSessionConfig.defaults(id: 'c')
              .copyWith(difficulty: CustomDifficulty.normal);
          final on = off.copyWith(
            anchorEnabled: true,
            anchorPoint: point,
            anchorStrength: strength,
          );
          final expectedRatio = on.resolveAnchor()!.$2;
          var piloted = 0;
          for (final seed in _seeds) {
            final before = _configSteps(_customSession(off, seed: seed));
            final after = _configSteps(_customSession(on, seed: seed));
            for (var i = 0; i < after.length; i++) {
              final a = after[i], b = before[i];
              if (a.mode != SessionMode.rhythm) continue;
              if (a.anchor == b.anchor && a.ratio == b.ratio) {
                // La phase finish (boosts + final) construit ses steps par
                // son propre chemin, hors de portée de ce réglage : elle
                // garde l'ancre que le niveau lui donne.
                continue;
              }
              piloted++;
              expect(a.anchor, point,
                  reason: 'step rhythm à ${a.time}s, point $point');
              expect(a.ratio, expectedRatio,
                  reason: 'step rhythm à ${a.time}s, cran ${strength.name}');
            }
          }
          expect(piloted, greaterThan(0),
              reason: 'aucun step rhythm piloté pour $point/${strength.name} : '
                  'la sonde ne prouverait rien');
        }
      }
    });

    test('ancre plus de steps rhythm qu\'aimant éteint', () {
      final off = CustomSessionConfig.defaults(id: 'c')
          .copyWith(difficulty: CustomDifficulty.normal);
      final on = off.copyWith(anchorEnabled: true);
      var offCount = 0, onCount = 0;
      for (final seed in _seeds) {
        offCount += _customSession(off, seed: seed)
            .steps
            .where((s) =>
                s.mode == SessionMode.rhythm && s.anchor != BeatAnchor.none)
            .length;
        onCount += _customSession(on, seed: seed)
            .steps
            .where((s) =>
                s.mode == SessionMode.rhythm && s.anchor != BeatAnchor.none)
            .length;
      }
      expect(onCount, greaterThan(offCount),
          reason: 'allumer l\'aimant doit s\'entendre sur la séance entière, '
              'pas seulement sur les passages que le générateur montait déjà');
    });

    test('un hold ancré sur l\'arrivée reçoit le bpm qui le cadence', () {
      final cfg = CustomSessionConfig.defaults(id: 'c').copyWith(
        difficulty: CustomDifficulty.normal,
        anchorEnabled: true,
        anchorPoint: BeatAnchor.to,
      );
      var seen = 0;
      for (final seed in _seeds) {
        for (final s in _customSession(cfg, seed: seed).steps) {
          if (s.mode != SessionMode.hold || s.anchor == BeatAnchor.none) {
            continue;
          }
          seen++;
          expect(s.anchor, BeatAnchor.to);
          expect(s.to, isNotNull);
          expect(s.to!.index, greaterThan(0),
              reason: 'à tip il n\'y a pas de position plus aiguë pour '
                  'l\'aller-retour');
          expect(s.bpm, isNotNull,
              reason: 'sans bpm, BeepEngine n\'a aucune cadence à jouer');
        }
      }
      expect(seen, greaterThan(0), reason: 'aucun hold ancré observé');
    });

    test('un hold ancré sur le départ reste tenu, jamais ancré', () {
      final cfg = CustomSessionConfig.defaults(id: 'c').copyWith(
        difficulty: CustomDifficulty.normal,
        anchorEnabled: true,
        anchorPoint: BeatAnchor.from,
      );
      var seenHold = 0;
      for (final seed in _seeds) {
        for (final s in _customSession(cfg, seed: seed).steps) {
          if (s.mode != SessionMode.hold) continue;
          seenHold++;
          // Le final `hold` de la phase finish garde sa propre ancre `to`
          // (étape 4) — elle n'est pas pilotée par ce réglage.
          if (s.anchor != BeatAnchor.none) {
            expect(s.anchor, BeatAnchor.to);
          }
        }
      }
      expect(seenHold, greaterThan(0));
    });
  });

  group('empreinte complète du step', () {
    test(
        'aimant éteint : la séance entière est identique champ à champ '
        'entre deux générations', () {
      final cfg = CustomSessionConfig.defaults(id: 'c');
      for (final seed in _seeds) {
        expect(_fingerprint(_customSession(cfg, seed: seed).steps),
            _fingerprint(_customSession(cfg, seed: seed).steps));
      }
    });
  });
}

List<SessionStep> _configSteps(Session s) =>
    s.steps.where((st) => !st.isTextOnly).toList();
