// Fichier part de `career_session_generator.dart` — dispatch principal
// difficulté → step.
//
// `_mapDifficultyToStep` est le cœur de la boucle main : à partir d'une
// difficulté `diff ∈ [0, 1]` tirée par `generate`, il construit le
// StepDraft concret du step suivant. Sa logique :
//   1. Sélection des candidats de mode (gating profil + Custom + chaîne
//      rythme + unlocks).
//   2. Tirage pondéré du mode via `_ModePicker.pickWeighted` (couleur spé
//      + dose coach + continuité par type).
//   3. Découpe simplex du budget de difficulté entre BPM / amplitude /
//      durée + bonus de spé par axe.
//   4. **Dispatch polymorphique** vers `ModeRules.build(DraftCtx)` du
//      mode tiré (cf. `career_session_generator_mode_rules.dart`). Chaque
//      rule porte ses propres ranges / samplers / caps mode-specific.
//
// Le file reste posé comme **extension** sur `CareerSessionGenerator`
// (library-private, call site `_mapDifficultyToStep(diff)` inchangé)
// pour l'accès à `this` côté orchestration (candidats, picker, _config.pts).
// Le sous-cas par mode du switch a migré vers le registry `_modeRules`.

part of 'career_session_generator.dart';

extension _DifficultyDispatch on CareerSessionGenerator {
  /// Convertit la difficulté `diff ∈ [0, 1]` en step concret. Le budget est
  /// réparti aléatoirement entre les axes BPM, amplitude et durée — donc un
  /// step "hard" peut être lent profond endurant, ou rapide plus court, etc.
  StepDraft _mapDifficultyToStep(double diff) {
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
            _state.stepsOutsideBouche >= 2 ||
            _state.lastType == StepType.bouche) &&
        _rhythmChain.canChain()) {
      candidates.add(SessionMode.rhythm);
    }
    // Hold candidat dès diff >= 0.20 normalement, mais aussi dès diff >= 0.10
    // si on est déjà en bouche : permet l'alternance rhythm/hold à
    // l'intérieur d'une série bouche (sinon les phases de chauffe restaient
    // 100 % rhythm uniforme — l'utilisateur attend rythme/rythme/hold/…).
    if (diff >= 0.20 || (_state.lastType == StepType.bouche && diff >= 0.10)) {
      candidates.add(SessionMode.hold);
    }
    // biffle : candidat seulement si `biffleBasic` est débloqué (pré-filtre
    // sur le mode pour éviter une cascade systématique de dégradation
    // biffle → lick quand la milestone n'est pas acquise). Le pré-filtre
    // respecte la convention héritée (`_state.unlockedKeys.isEmpty` = pas de
    // gating) pour ne pas casser les sessions hors carrière.
    final canBiffle = _state.unlockedKeys.isEmpty ||
        _state.unlockedKeys.contains(UnlockKey.biffleBasic);
    if (diff >= 0.40 && _config.includeHand && canBiffle) {
      candidates.add(SessionMode.biffle);
    }
    if (_config.includeHand && diff >= 0.10) {
      // Hand est dispo dès le début : repose la bouche, aide à varier le
      // tempo. Seuil bas pour qu'il apparaisse aussi en bas niveau (sinon
      // les fenêtres de difficulté basses des premiers paliers le bloquent
      // trop souvent — feedback : « aucune au premier niveau »).
      candidates.add(SessionMode.hand);
    }
    // beg : candidat seulement si begLibre est déjà acquis (prérequis
    // transverse à toutes les formes de beg, cf. `_isUnlocked`). Convention
    // héritée appliquée aussi (set vide = pas de gating).
    final canBeg = _state.unlockedKeys.isEmpty ||
        _state.unlockedKeys.contains(UnlockKey.begLibre);
    if (canBeg) {
      // Sa difficulté effective est portée par `from` (head = doux,
      // full = comme un hold profond), pas par diff.
      candidates.add(SessionMode.beg);
    }
    // suckle : geste latéral (head ou balls). En carrière, gaté par la
    // milestone `intro_suckle_head` qui accorde `UnlockKey.suckleHead`. En
    // mode hérité (Custom, scénarios), on l'ajoute inconditionnellement —
    // sa dose Custom (ModeDose.none ⇒ forbidden) le retire ensuite via
    // `removeWhere(_config.isModeForbidden)`. Sans cet ajout, la dose Custom
    // était de fait ignorée : suckle n'était jamais tiré.
    final canSuckle = _state.unlockedKeys.isEmpty ||
        _state.unlockedKeys.contains(UnlockKey.suckleHead);
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
    candidates.removeWhere(_config.isModeForbidden);
    if (candidates.isEmpty) {
      for (final m in const [
        SessionMode.lick,
        SessionMode.hold,
        SessionMode.rhythm,
      ]) {
        if (!_config.isModeForbidden(m)) {
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
    bpmScore =
        (bpmScore + 0.08 * _config.pts(SpecializationBranch.rythmeBiffle))
            .clamp(0.0, 1.0);
    ampScore = (ampScore + 0.08 * _config.pts(SpecializationBranch.profondeur))
        .clamp(0.0, 1.0);
    durScore = (durScore + 0.08 * _config.pts(SpecializationBranch.endurance))
        .clamp(0.0, 1.0);

    // Dispatch polymorphique : chaque rule consomme les 3 scores via
    // `DraftCtx` et accède aux samplers / caps via `ctx.gen.*` (typé
    // `GenFacade`, surface restreinte du générateur). La logique
    // mode-specific (ranges BPM/amplitude/durée, sloppy boost pour lick,
    // obéissance boost pour beg, anatomy gate pour suckle…) est portée
    // par les `ModeRules.build` correspondants.
    return _modeRulesRegistry[mode]!.build(DraftCtx(
      bpmScore: bpmScore,
      ampScore: ampScore,
      durScore: durScore,
      gen: _facade,
    ));
  }
}
