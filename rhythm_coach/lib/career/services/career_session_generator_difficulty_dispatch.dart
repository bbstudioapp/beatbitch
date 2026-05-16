// Fichier part de `career_session_generator.dart` — dispatch principal
// difficulté → step.
//
// `_mapDifficultyToStep` est le cœur de la boucle main : à partir d'une
// difficulté `diff ∈ [0, 1]` tirée par `generate`, il construit le
// _StepDraft concret du step suivant. Sa logique :
//   1. Sélection des candidats de mode (gating profil + Custom + chaîne
//      rythme + unlocks).
//   2. Tirage pondéré du mode via `_ModePicker.pickWeighted` (couleur spé
//      + dose coach + continuité par type).
//   3. Découpe simplex du budget de difficulté entre BPM / amplitude /
//      durée + bonus de spé par axe.
//   4. Construction d'un draft typé selon le mode tiré (chaque case
//      utilise ses propres samplers et caps).
//
// La méthode lit ~15 fields d'instance et appelle ~10 helpers (samplers,
// caps, pickers). Plutôt que de threader cette surface comme paramètres
// d'une méthode statique, on la pose comme **extension** sur
// `CareerSessionGenerator` : library-private, accès direct à `this`, le
// call site `_mapDifficultyToStep(diff)` dans `generate()` est inchangé.
//
// Cette extraction est purement physique — pas de pure-ification, pas de
// changement d'API. L'objectif est la lisibilité du fichier principal :
// le body principal de `generate()` n'a pas à cohabiter avec 230 lignes
// de dispatch de modes.

part of 'career_session_generator.dart';

extension _DifficultyDispatch on CareerSessionGenerator {
  /// Convertit la difficulté `diff ∈ [0, 1]` en step concret. Le budget est
  /// réparti aléatoirement entre les axes BPM, amplitude et durée — donc un
  /// step "hard" peut être lent profond endurant, ou rapide plus court, etc.
  _StepDraft _mapDifficultyToStep(double diff) {
    final candidates = <SessionMode>[];
    if (diff < 0.30) {
      candidates.add(SessionMode.lick);
    }
    // Bouche disponible quoi qu'il arrive si on y est déjà ou si on en
    // est sorti depuis longtemps : à diff < 0.20 le panel par défaut ne
    // contient que lick/hand, donc sans cette injection on est mécaniquement
    // forcé de quitter bouche au step suivant — la friction de continuité
    // n'a plus rien à pousser. La cohérence par type (séries de plusieurs
    // steps sur bouche) ne marche que si rhythm reste un candidat valide
    // pendant la phase de chauffe.
    if ((diff >= 0.20 ||
            _stepsOutsideBouche >= 2 ||
            _lastType == _StepType.bouche) &&
        _canChainRhythm()) {
      candidates.add(SessionMode.rhythm);
    }
    // Hold candidat dès diff >= 0.20 normalement, mais aussi dès diff >= 0.10
    // si on est déjà en bouche : permet l'alternance rhythm/hold à
    // l'intérieur d'une série bouche (sinon les phases de chauffe restaient
    // 100 % rhythm uniforme — l'utilisateur attend rythme/rythme/hold/…).
    if (diff >= 0.20 || (_lastType == _StepType.bouche && diff >= 0.10)) {
      candidates.add(SessionMode.hold);
    }
    // biffle : candidat seulement si `biffleBasic` est débloqué (pré-filtre
    // sur le mode pour éviter une cascade systématique de dégradation
    // biffle → lick quand la milestone n'est pas acquise). Le pré-filtre
    // respecte la convention héritée (`_unlockedKeys.isEmpty` = pas de
    // gating) pour ne pas casser les sessions hors carrière.
    final canBiffle =
        _unlockedKeys.isEmpty || _unlockedKeys.contains(UnlockKey.biffleBasic);
    if (diff >= 0.40 && _includeHand && canBiffle) {
      candidates.add(SessionMode.biffle);
    }
    if (_includeHand && diff >= 0.10) {
      // Hand est dispo dès le début : repose la bouche, aide à varier le
      // tempo. Seuil bas pour qu'il apparaisse aussi en bas niveau (sinon
      // les fenêtres de difficulté basses des premiers paliers le bloquent
      // trop souvent — feedback : « aucune au premier niveau »).
      candidates.add(SessionMode.hand);
    }
    // beg : candidat seulement si begLibre est déjà acquis (prérequis
    // transverse à toutes les formes de beg, cf. `_isUnlocked`). Convention
    // héritée appliquée aussi (set vide = pas de gating).
    final canBeg =
        _unlockedKeys.isEmpty || _unlockedKeys.contains(UnlockKey.begLibre);
    if (canBeg) {
      // Sa difficulté effective est portée par `from` (head = doux,
      // full = comme un hold profond), pas par diff.
      candidates.add(SessionMode.beg);
    }
    // suckle : geste latéral (head ou balls). En carrière, gaté par la
    // milestone `intro_suckle_head` qui accorde `UnlockKey.suckleHead`. En
    // mode hérité (Custom, scénarios), on l'ajoute inconditionnellement —
    // sa dose Custom (ModeDose.none ⇒ forbidden) le retire ensuite via
    // `removeWhere(_isModeForbidden)`. Sans cet ajout, la dose Custom
    // était de fait ignorée : suckle n'était jamais tiré.
    final canSuckle =
        _unlockedKeys.isEmpty || _unlockedKeys.contains(UnlockKey.suckleHead);
    if (canSuckle) {
      candidates.add(SessionMode.suckle);
    }
    // breath n'est jamais un step "d'effort" : il n'est tiré que par
    // _buildRecoveryStep quand l'endurance est basse, jamais ici.
    // Exclusions Custom (dose `none`) : retirer les modes interdits avant
    // tirage. Si tout est exclu, on retombe sur un mode bouche encore
    // actif (l'éditeur Custom garantit qu'au moins un mouth mode reste
    // ≥ rare via son garde-fou). On essaie lick → hold → rhythm pour
    // privilégier le mode le plus doux disponible, et rhythm en dernier
    // ressort pour ne jamais crasher si une config était corrompue.
    candidates.removeWhere(_isModeForbidden);
    if (candidates.isEmpty) {
      for (final m in const [
        SessionMode.lick,
        SessionMode.hold,
        SessionMode.rhythm,
      ]) {
        if (!_isModeForbidden(m)) {
          candidates.add(m);
          break;
        }
      }
      if (candidates.isEmpty) candidates.add(SessionMode.rhythm);
    }
    final mode = _pickWeightedMode(_filterRepeated(candidates));

    final (aBpm, aAmp, aDur) = _sampleSimplex3();
    var bpmScore = (diff * 3 * aBpm).clamp(0.0, 1.0);
    var ampScore = (diff * 3 * aAmp).clamp(0.0, 1.0);
    var durScore = (diff * 3 * aDur).clamp(0.0, 1.0);
    // Bonus de spé sur les axes (capés 1.0). Coefs renforcés (+0.05 →
    // +0.08/pt) pour que la branche choisie pousse plus visiblement les
    // paramètres : 5 pts en profondeur = +0.40 ampScore, donc des
    // amplitudes mid→full / throat→full bien plus fréquentes.
    bpmScore = (bpmScore + 0.08 * _pts(SpecializationBranch.rythmeBiffle))
        .clamp(0.0, 1.0);
    ampScore = (ampScore + 0.08 * _pts(SpecializationBranch.profondeur))
        .clamp(0.0, 1.0);
    durScore = (durScore + 0.08 * _pts(SpecializationBranch.endurance))
        .clamp(0.0, 1.0);

    switch (mode) {
      case SessionMode.rhythm:
        final bpm = _StaminaModel.lerp(60.0, 140.0, bpmScore).round();
        final (from, to) = _sampleFromTo(ampScore);
        var dur = _scaleDuration(
          _StaminaModel.lerp(20.0, 60.0, durScore),
          enduranceFactor: 0.05,
        );
        // Cap par nombre d'aller-retours sur les profondeurs throat/full :
        // un step rythme à `to=throat` ne devrait pas enchaîner 30+ pulses
        // consécutifs (à 90 bpm, 60 s = 45 throats — la joueuse étouffe).
        // Cf. règle « passé to:throat, on se limite à un certain nombre
        // d'aller-retours par step ». Le cap est calculé en secondes :
        // durMax = maxPulses × 120 / bpm (×2 car pulse = 2 beats).
        dur = _capRhythmDurationByPulses(dur, bpm, to);
        // Cap rythme soutenu : tant que la milestone
        // `intro_rhythm_sustained` n'a pas été acquittée, la chaîne rythme
        // consécutive est plafonnée à 60 s. Le candidat n'arrive ici que
        // si `_canChainRhythm()` était vrai au tirage, donc il reste au
        // moins `_minRhythmStepSeconds` de marge.
        dur = _capRhythmConsecutive(dur);
        return _StepDraft(
            mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.biffle:
        // Biffle = coups de queue sur le visage : pas de notion de
        // position. from/to restent null.
        final bpm = _StaminaModel.lerp(80.0, 140.0, bpmScore).round();
        final dur = _scaleDuration(
          _StaminaModel.lerp(15.0, 40.0, durScore),
          enduranceFactor: 0.05,
        );
        return _StepDraft(
            mode: mode, bpm: bpm, from: null, to: null, duration: dur);
      case SessionMode.hold:
        // Convention uniforme hold/beg : la position tenue est dans `to`
        // (matche BeepEngine et le format SessionStep des JSON).
        final to = _pickHoldPosition(ampScore);
        final dur = _scaleDuration(
          _StaminaModel.lerp(8.0, 30.0, max(durScore, bpmScore)),
          enduranceFactor: 0.08,
        );
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: to, duration: dur);
      case SessionMode.lick:
        // Sloppy : monte le BPM minimum (≥ 65 = lick humide / saliveux).
        final sloppyPts = _pts(SpecializationBranch.sloppy);
        final lickBpmScore = sloppyPts > 0 ? max(bpmScore, 0.3) : bpmScore;
        final bpm = _StaminaModel.lerp(55.0, 80.0, lickBpmScore).round();
        // Tirage spécifique lick : tip→head forcé tant qu'humiliation < 2,
        // toutes amplitudes (incluant tip → throat/full) à partir de 2.
        final (from, to) = _sampleFromToForLick(ampScore);
        final dur = _scaleDuration(
          _StaminaModel.lerp(10.0, 25.0, durScore),
          enduranceFactor: 0.04,
        );
        return _StepDraft(
            mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.breath:
        final dur = _StaminaModel.lerp(6.0, 15.0, durScore).round();
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: null, duration: dur);
      case SessionMode.beg:
        // Convention uniforme hold/beg : la position tenue est dans `to`.
        // Obéissance : beg plus profonds (ampScore boosté localement) et
        // plus longs.
        final obPts = _pts(SpecializationBranch.obeissance);
        final begAmp = (ampScore + 0.10 * obPts).clamp(0.0, 1.0);
        final to = _pickBegPosition(begAmp);
        final baseDur = _scaleDuration(
          _StaminaModel.lerp(7.0, 16.0, durScore),
          enduranceFactor: 0.04,
          extraFactor: obPts * 0.06,
        );
        final chained = _maybePickBegWithChain(
          to: to,
          obPts: obPts,
        );
        if (chained != null) return chained;
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: to, duration: baseDur);
      case SessionMode.hand:
        // Hand sert d'outil d'excitation/endurance pure : sa fréquence peut
        // grimper sans coût d'humiliation. Plage très large pour permettre
        // récup lente (60 BPM) jusqu'à burst frénétique (180 BPM).
        final bpm = _StaminaModel.lerp(60.0, 180.0, bpmScore).round();
        // Tirage spécifique hand : la main tient la base de la queue, donc
        // l'amplitude reste dans le haut (jamais plus profond que throat).
        // En revanche tip→head et head→head sont autorisés (le tirage
        // commun les exclut pour les autres modes).
        final (from, to) = _sampleFromToForHand(ampScore);
        final dur = _scaleDuration(
          _StaminaModel.lerp(15.0, 30.0, durScore),
          enduranceFactor: 0.04,
        );
        return _StepDraft(
            mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.freestyle:
        final dur = _StaminaModel.lerp(8.0, 18.0, durScore).round();
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: null, duration: dur);
      case SessionMode.suckle:
        // Aspiration : pas de BPM (pulse fixe ~1.2s côté audio), position
        // tenue dans `to`. Cibles valides = head ou balls (cf. `_isUnlocked`).
        // - En carrière : unlock `suckleHead` au level 4-5, `suckleBalls`
        //   plus tard ; le filtre `_isUnlocked` rejette ce qui n'est pas
        //   encore acquis et la cascade dégrade.
        // - En mode hérité (Custom) : balls n'est candidat que si l'anatomy
        //   l'inclut et que la profondeur max le permet (`_maxDepthIndex >=
        //   Position.balls.index`). On biaise vers head (zone classique) avec
        //   ~30 % de chances de tirer balls quand dispo, pour rester audible
        //   mais marginal.
        final dur = _scaleDuration(
          _StaminaModel.lerp(8.0, 18.0, durScore),
          enduranceFactor: 0.04,
        );
        final ballsAllowed = _anatomy.hasBalls &&
            _maxDepthIndex >= Position.balls.index &&
            (_unlockedKeys.isEmpty ||
                _unlockedKeys.contains(UnlockKey.suckleBalls));
        final to = (ballsAllowed && _rng.nextDouble() < 0.30)
            ? Position.balls
            : Position.head;
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: to, duration: dur);
    }
  }
}
