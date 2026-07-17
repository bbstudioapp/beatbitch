import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

// Structure du mode « Utilise-moi » (PR1). Le bypass complet de l'enveloppe
// humil/capacité (throat/full garanti sur TOUS les profils) + l'escalade BPM
// jusqu'à 300 sont PR2 ; ici on vérifie la structure sous inputs non
// contraints (humil haute + capacité par défaut = aucune, `_allUnlocks`).

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
          'boost': _p(['b']),
          'finale': _p(['f']),
        },
    },
    congrats: _p(['bravo']),
    intros: _p(['intro']),
  );
}

final Set<UnlockKey> _allUnlocks = UnlockKey.values.toSet();

/// Génère une suite « Utilise-moi » représentative (humil haute → throat/full
/// délivrable en PR1 ; durée longue → corps + boosts + final).
CareerGenerationResult _useMeResult(int seed) {
  return CareerSessionGenerator(seed: seed).generate(
    level: 12,
    bank: _bank(),
    durationSeconds: 20 * 60,
    intense: true,
    useMe: true,
    humiliationCareer: 300.0,
    obedience: 100.0,
    unlockedKeys: _allUnlocks,
  );
}

bool _hasToPosition(SessionMode? mode) =>
    mode == SessionMode.rhythm || mode == SessionMode.hold;

void main() {
  test('useMe — le corps ne contient que rhythm et hold', () {
    for (var seed = 0; seed < 20; seed++) {
      final result = _useMeResult(seed);
      final configSteps =
          result.session.steps.where((s) => !s.isTextOnly).toList();
      expect(configSteps, isNotEmpty, reason: 'seed=$seed : suite vide');
      for (final s in configSteps) {
        expect(
          s.mode == SessionMode.rhythm || s.mode == SessionMode.hold,
          isTrue,
          reason: 'seed=$seed : mode ${s.mode} interdit en useMe '
              '(t=${s.time})',
        );
      }
    }
  });

  test('useMe — aucun step breath (pause seulement sur fail)', () {
    for (var seed = 0; seed < 20; seed++) {
      final result = _useMeResult(seed);
      final breaths =
          result.session.steps.where((s) => s.mode == SessionMode.breath);
      expect(breaths, isEmpty,
          reason: 'seed=$seed : un breath a été émis en useMe');
    }
  });

  test('useMe — le `to` (profondeur atteinte) est toujours throat ou full', () {
    for (var seed = 0; seed < 20; seed++) {
      final result = _useMeResult(seed);
      for (final s in result.session.steps) {
        if (s.isTextOnly || !_hasToPosition(s.mode)) continue;
        final to = s.to;
        if (to == null) continue;
        expect(
          to == Position.throat || to == Position.full,
          isTrue,
          reason: 'seed=$seed : to=${to.name} < throat en useMe '
              '(mode=${s.mode} from=${s.from?.name} t=${s.time})',
        );
      }
    }
  });

  test('useMe — le `from` reste libre (tip/head/mid apparaissent)', () {
    // Contre-preuve de la correction : l'amplitude n'est pas figée à
    // throat→full, seul le `to` est contraint. Sur 20 seeds, on doit voir
    // au moins un rhythm dont le `from` est sous throat.
    var sawShallowFrom = false;
    for (var seed = 0; seed < 20 && !sawShallowFrom; seed++) {
      final result = _useMeResult(seed);
      for (final s in result.session.steps) {
        if (s.mode != SessionMode.rhythm) continue;
        final from = s.from;
        if (from != null && from.index < Position.throat.index) {
          sawShallowFrom = true;
          break;
        }
      }
    }
    expect(sawShallowFrom, isTrue,
        reason: 'aucun from < throat sur 20 seeds — amplitude sur-contrainte');
  });

  test('useMe — le final est un hold full', () {
    for (var seed = 0; seed < 20; seed++) {
      final result = _useMeResult(seed);
      final finalT = result.session.finalStepTime;
      expect(finalT, isNotNull, reason: 'seed=$seed : finalStepTime absent');
      final finisher = result.session.steps.firstWhere(
        (s) => !s.isTextOnly && s.time == finalT,
      );
      expect(finisher.mode, SessionMode.hold,
          reason: 'seed=$seed : final ${finisher.mode} ≠ hold');
      expect(finisher.to, Position.full,
          reason: 'seed=$seed : final hold to=${finisher.to?.name} ≠ full');
    }
  });

  test(
      'contraste — sans useMe, la même config produit d\'autres modes/'
      'profondeurs', () {
    // Sanity : c'est bien `useMe` qui restreint. Une génération standard aux
    // mêmes paramètres doit produire au moins un mode hors {rhythm, hold}
    // OU un `to` sous throat (variété normale).
    var sawVariety = false;
    for (var seed = 0; seed < 20 && !sawVariety; seed++) {
      final result = CareerSessionGenerator(seed: seed).generate(
        level: 12,
        bank: _bank(),
        durationSeconds: 20 * 60,
        intense: true,
        humiliationCareer: 300.0,
        obedience: 100.0,
        unlockedKeys: _allUnlocks,
      );
      for (final s in result.session.steps) {
        if (s.isTextOnly) continue;
        final otherMode = s.mode != null &&
            s.mode != SessionMode.rhythm &&
            s.mode != SessionMode.hold &&
            s.mode != SessionMode.breath;
        final shallowTo = _hasToPosition(s.mode) &&
            s.to != null &&
            s.to!.index < Position.throat.index;
        if (otherMode || shallowTo) {
          sawVariety = true;
          break;
        }
      }
    }
    expect(sawVariety, isTrue,
        reason: 'la génération standard devrait montrer plus de variété que '
            'useMe — le contraste ne se voit pas');
  });
}
