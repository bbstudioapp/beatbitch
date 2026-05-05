import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/final_category.dart';
import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/excitation_engine.dart';
import '../../services/humiliation_engine.dart';
import '../models/career_level.dart';
import '../models/level_milestone.dart';
import '../models/phrase_bank.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';

/// Résultat d'une génération : la session figée à passer au controller +
/// le profil d'endurance projeté + le profil d'excitation projeté
/// (utile à l'overlay debug `StaminaBar` / `ExcitationBar`).
class CareerGenerationResult {
  final Session session;
  final List<double> staminaProfile;
  final List<double> excitationProfile;

  const CareerGenerationResult({
    required this.session,
    required this.staminaProfile,
    required this.excitationProfile,
  });
}

/// Génère une session procédurale en fonction du niveau choisi et de la
/// durée demandée. Voir `(plan local)`
/// pour la spec complète de l'algorithme.
class CareerSessionGenerator {
  static const int _finisherBudgetSeconds = 12;
  static const double _staminaMax = 100.0;
  /// Sentinel pour signaler "pas de cible explicite, utilise celle du
  /// niveau" (cf. `CareerLevel.excitationTarget`). Distinct de toute valeur
  /// que l'écran carrière peut passer pour les régénérations en cours de
  /// session (Supplier / Encore qui transmettent une cible explicite).
  static const double _defaultExcitationTarget = -1.0;

  /// Budget réservé en fin de session pour la phase d'accélération qui
  /// précède le hold final (bas niveaux uniquement). Permet d'enchaîner
  /// proprement effort → finisher sans dépasser la durée demandée.
  static const int _preFinisherBudgetSeconds = 30;

  final Random _rng;

  /// Toggle propagé depuis [generate]. Filtre hand ET biffle des candidats
  /// (les coups de queue impliquent de tenir avec la main, donc cohérent
  /// d'exclure les deux ensemble).
  bool _includeHand = true;

  /// Plafond de profondeur autorisé (index Position) — appliqué à
  /// `_sampleFromTo` et `_pickHoldPosition`. Valeur par défaut 4 (full).
  /// Renseigné par `generate` à partir du `CareerLevel`.
  int _maxDepthIndex = 4;

  /// Probabilité de retenir une position profonde (throat/full) quand le
  /// plafond la permet. Permet de raréfier sans bannir.
  double _deepProbability = 1.0;

  /// Allocation de spécialisation propagée pour pondérer le tirage des
  /// candidats et les paramètres internes (BPM, amplitude, durée). Si
  /// non fournie : map vide → comportement neutre.
  SpecializationAllocation _spec = SpecializationAllocation.empty();

  /// Dernier mode poussé dans la séance, pour éviter qu'un même mode
  /// (breath, beg, …) se déclenche deux steps d'affilé. Reset dans `generate`.
  SessionMode? _lastMode;

  /// Dernière phrase TTS poussée, pour éviter de répéter la même phrase
  /// scriptée d'un step à l'autre. Reset dans `generate`.
  String _lastText = '';

  /// Niveau de carrière de la session en cours. Sert au filtrage par
  /// niveau (ex : freestyle débloqué au niveau 4 seulement).
  int _level = 1;

  /// Dernier BPM appliqué à un step (rhythm/lick/biffle/hand). Sert à
  /// forcer la variété : un nouveau BPM trop proche du précédent est
  /// décalé de 18–30 BPM par `_diversifyBpm`.
  int? _lastBpm;

  /// Dernier couple (from, to) appliqué pour les modes à amplitude
  /// (rhythm/lick/hand/biffle). Sert à forcer une variation de profondeur
  /// quand le step suivant tombe sur exactement la même paire.
  Position? _lastFrom;
  Position? _lastTo;

  /// Simulateur d'excitation utilisé pendant la génération. Mime le
  /// comportement de l'`ExcitationEngine` runtime : décroissance V²/800,
  /// spike par profondeur, plateaux. Réinitialisé à chaque `generate`.
  late ExcitationEngine _excitSim;

  /// Set des `UnlockKey` débloquées pour la génération en cours. Une action
  /// dont la clé n'est pas dedans est rejetée par `_isUnlocked` et dégradée
  /// par `_stepDownOne`. Vide = aucune clé requise (mode héritage).
  Set<UnlockKey> _unlockedKeys = const {};

  /// Multiplicateur de poids par mode, fourni par le coach actif. Combiné
  /// **multiplicativement** par-dessus la pondération spé dans `_modeWeight`.
  /// Mode absent = 1.0 (neutre). Cf. CoachMeta.modeWeights.
  Map<SessionMode, double> _coachModeWeights = const {};

  /// Score d'humiliation au démarrage de la session (cf. param
  /// `humiliationScore` de `generate`). Sert au tirage spécifique de
  /// certains modes (lick : amplitudes complètes seulement à partir de 2).
  double _humiliationScore = 0.0;

  /// Score d'obédiance au démarrage de la session (cf. param `obedience`
  /// de `generate`). Pilote le tier de phrase auto-bumpé dans `_pickPhrase`
  /// (plus c'est élevé, plus la coach pioche dans `medium`/`hard`) et le
  /// `recoveryThreshold` (plus c'est élevé, plus on respecte l'endurance).
  double _obedience = 0.0;

  CareerSessionGenerator({int? seed})
      : _rng = seed != null ? Random(seed) : Random();

  CareerGenerationResult generate({
    required int level,
    required PhraseBank bank,
    int? durationSeconds,
    bool includeHand = true,
    double excitationTarget = _defaultExcitationTarget,
    String? openingPhrase,
    bool quickie = false,
    SpecializationAllocation? specialization,
    bool intense = false,
    double obedience = 100.0,
    double humiliationScore = 0.0,
    LevelMilestone? milestone,
    LevelMilestone? finalMilestone,
    Set<UnlockKey> unlockedKeys = const {},
    String? Function(String milestoneId, int stepTime)? milestoneTextResolver,
    Map<SessionMode, double> coachModeWeights = const {},
  }) {
    assert(
      finalMilestone == null ||
          finalMilestone.placement == MilestonePlacement.finalApotheose,
      'finalMilestone doit avoir placement=finalApotheose',
    );
    assert(
      milestone == null || milestone.placement == MilestonePlacement.body,
      'milestone (paramètre body) doit avoir placement=body',
    );
    final cfg = CareerLevel.forLevel(level);
    _includeHand = includeHand;
    _maxDepthIndex = cfg.maxDepthIndex;
    _deepProbability = cfg.deepProbability;
    _spec = specialization ?? SpecializationAllocation.empty();
    _level = level;
    _lastMode = null;
    _lastText = '';
    _lastBpm = null;
    _lastFrom = null;
    _lastTo = null;
    _unlockedKeys = unlockedKeys;
    _coachModeWeights = coachModeWeights;
    _humiliationScore = humiliationScore;
    _obedience = obedience;
    // Mode "Session bâclée" : 6 min, intense tout du long. Floor d'intensité
    // appliqué au tirage de difficulté + on saute l'intro douce et la
    // pré-finition. Override la durée passée en paramètre.
    //
    // Mode "intense" : régénération post-Supplier. On garde la durée
    // demandée mais on supprime le soft intro et on applique un plancher
    // de difficulté solide pour que la suite ressente vraiment le level up.
    final effectiveDuration = quickie ? 6 * 60 : (durationSeconds ?? cfg.durationSeconds);
    final intensityFloor =
        quickie ? 0.65 : (intense ? 0.55 : 0.0);
    // Cible d'excitation : si l'appelant n'a rien passé (sentinel négatif),
    // on prend celle du niveau. Encore et Supplier transmettent une valeur
    // explicite (ancien max + bonus) qu'on respecte.
    final resolvedExcitationTarget =
        excitationTarget < 0 ? cfg.excitationTarget : excitationTarget;
    // `minFinal` = seuil que les boosts visent (≠ max engine). Pour les
    // chaînes encore, on monte minFinal proportionnellement (delta target
    // appliqué aussi à minFinal pour rester cohérent). Sentinel négatif =
    // base niveau ; sinon valeur explicite.
    final resolvedMinFinal = excitationTarget < 0
        ? cfg.minFinal
        : (cfg.minFinal + (excitationTarget - cfg.excitationTarget))
            .clamp(0.0, excitationTarget);
    _excitSim = ExcitationEngine()..setMax(resolvedExcitationTarget);
    final steps = <SessionStep>[];
    final profile = List<double>.filled(effectiveDuration + 60, _staminaMax);
    final excitProfile = List<double>.filled(effectiveDuration + 60, 0.0);

    var time = 0;
    var stamina = _staminaMax;
    var excitation = 0.0;

    // Insertion différée de la milestone d'apprentissage. Pour permettre
    // une chauffe avant de tomber sur la séquence pédagogique, on insère
    // au plus tôt à `insertAtMinSeconds` (default 60s) et au plus tard à
    // `insertAtMaxSeconds` (default 0.4 × durée totale). L'insertion se
    // fait dans la boucle main dès que `time` entre dans la fenêtre.
    //
    // Cas spécial `insertAtMinSeconds <= 0` : la milestone EST l'intro,
    // on remplace le first step classique. Utile pour la milestone
    // niveau 1 qui guide depuis t=0.
    int? milestoneStartTime;
    int? milestoneDurationSeconds;
    bool milestoneInserted = false;
    final int minInsert = milestone?.insertAtMinSeconds ?? 60;
    final int maxInsert = milestone?.insertAtMaxSeconds ??
        (effectiveDuration * 0.4).round();
    final bool milestoneReplacesIntro =
        milestone != null && minInsert <= 0;

    void insertMilestoneNow() {
      if (milestone == null || milestoneInserted) return;
      milestoneStartTime = time;
      for (final mStep in milestone.sequence) {
        // Si une surcharge i18n existe pour ce step (clé = offset `time`
        // du step dans la sequence), on l'utilise à la place du `text`
        // du JSON principal.
        final overrideText =
            milestoneTextResolver?.call(milestone.id, mStep.time);
        steps.add(SessionStep(
          time: time + mStep.time,
          text: overrideText ?? mStep.text,
          mode: mStep.mode,
          bpm: mStep.bpm,
          from: mStep.from,
          to: mStep.to,
          duration: mStep.duration,
        ));
        // Simulation stamina/excitation pour chaque step de la séquence,
        // pour que la projection reste cohérente.
        final mDraft = _stepToDraft(mStep, SessionMode.rhythm);
        stamina = _applyStaminaChange(
            stamina, mDraft, time / effectiveDuration, cfg);
        excitation = _runOnEngine(_excitSim, mDraft);
        _fillProfile(
            profile, time + mStep.time, mStep.duration ?? 0, stamina);
        _fillProfile(
            excitProfile, time + mStep.time, mStep.duration ?? 0, excitation);
      }
      // Met à jour le « dernier mode/texte » avec le dernier step de la
      // milestone — sert au filtrage anti-répétition de la suite générée.
      final lastStep = milestone.sequence.last;
      _lastMode = lastStep.mode ?? _lastMode;
      _lastText = lastStep.text;
      time += milestone.durationSeconds;
      milestoneDurationSeconds = milestone.durationSeconds;
      milestoneInserted = true;
    }

    // Step #0 obligatoirement non text-only à time=0 (sinon _lastConfigStep
    // reste null côté controller, casse la restauration post-fail). Une
    // phrase soft d'amorce y est attachée pour ne pas démarrer la séance
    // dans le silence. En mode bâclée, intro raccourcie pour aller au but.
    //
    // Si la milestone remplace l'intro, on l'insère ici à t=0 et c'est
    // son premier step qui tient le rôle de step #0 non text-only.
    if (milestoneReplacesIntro) {
      insertMilestoneNow();
    } else {
      final first = _firstStep(
        quickie: quickie,
        intense: intense,
      );
      final firstText =
          openingPhrase ?? _pickPhrase(bank, first.mode, 'soft');
      steps.add(_draftToStep(first, time: 0, text: firstText));
      _lastMode = first.mode;
      _lastText = firstText;
      _lastBpm = first.bpm ?? _lastBpm;
      _lastFrom = first.from;
      _lastTo = first.to;
      stamina = _applyStaminaChange(stamina, first, 0.0, cfg);
      _fillProfile(profile, 0, first.duration ?? 1, stamina);
      excitation = _runOnEngine(_excitSim, first);
      _fillProfile(excitProfile, 0, first.duration ?? 1, excitation);
      time += first.duration ?? 1;
    }

    // Pour les bas niveaux on réserve un créneau supplémentaire avant le
    // finisher pour insérer une légère accélération de fin (cf. plus bas).
    // Modes bâclée / intense : pas de pré-finition, on enchaîne directement
    // — la régen post-Supplier doit déjà être à fond, pas besoin de la
    // pré-accélérer.
    //
    // Cas `finalMilestone != null` : la séquence milestone EST le final
    // (placement `finalApotheose`). Elle remplace les boosts + le step
    // finisher classique. On réserve donc sa durée intégrale en fin de
    // séance (au lieu de `_finisherBudgetSeconds`), et on saute le
    // pré-finisher (la milestone porte sa propre amorce d'apothéose).
    final isLowLevel = level <= 2 && !quickie && !intense;
    final useFinalMilestone = finalMilestone != null;
    final finalBudget = useFinalMilestone
        ? finalMilestone.durationSeconds
        : _finisherBudgetSeconds;
    final genUntil = effectiveDuration -
        finalBudget -
        (isLowLevel && !useFinalMilestone ? _preFinisherBudgetSeconds : 0);

    while (time < genUntil) {
      // Insertion milestone : dès que `time` atteint la borne min, OU dès
      // qu'on dépasse la borne max (auquel cas on insère en urgence pour
      // ne pas la louper). Le cas time<minInsert continue à empiler des
      // steps de chauffe normalement.
      if (milestone != null && !milestoneInserted &&
          (time >= minInsert || time >= maxInsert)) {
        insertMilestoneNow();
        if (time >= genUntil) break;
        continue;
      }
      final progress = time / effectiveDuration;
      final windowMin = _lerp(0.05, 0.50, progress);
      var windowMax =
          min(_lerp(0.30, 1.00, progress), cfg.maxDifficultyCap);
      // Floor d'intensité (mode bâclée) : tronque le bas de la fenêtre.
      final flooredMin = max(windowMin, intensityFloor);
      final boundedMin = min(flooredMin, windowMax - 0.05).clamp(0.0, 1.0);
      windowMax = max(windowMax, boundedMin + 0.05);

      final diff =
          boundedMin + _rng.nextDouble() * (windowMax - boundedMin);

      final _StepDraft initialDraft;
      // Seuils de recovery modulés par l'obéissance : plus elle est haute,
      // plus on respecte l'endurance (recovery déclenché plus tôt). Sur la
      // dernière minute, on les coupe entièrement — la fin de séance ignore
      // l'endurance par contrat.
      final inLastMinute = (effectiveDuration - time) <= 60;
      // Bonus obédiance sur le seuil de recovery : capé +25 pour pas
      // qu'une obédiance lifetime extrême (200+) pousse le seuil à 80
      // (= recovery quasi-permanente). À obed=100, +25 ; à obed=0, +0.
      final obedienceBonus = (obedience / 100.0).clamp(0.0, 1.0) * 25.0;
      final recoveryThreshold =
          inLastMinute ? -1 : (quickie ? 15 : 30) + obedienceBonus;
      final recoveryRandomThreshold =
          inLastMinute ? -1 : (quickie ? 25 : 50) + obedienceBonus;
      if (stamina < recoveryThreshold ||
          (stamina < recoveryRandomThreshold && _rng.nextBool())) {
        initialDraft = _buildRecoveryStep();
      } else {
        initialDraft = _mapDifficultyToStep(diff);
      }
      // Si beg arrive juste après une phase douce (lick / breath), on
      // retire le `from` pour enchaîner sur une supplique purement vocale
      // plutôt que de redemander de tenir une position. Côté stamina,
      // beg avec from=null suit la même branche regen que from=head.
      var draft = _stripBegFromAfterSoft(initialDraft, steps);

      // Filtre humiliation requise : on garde uniquement ce que le score
      // d'humiliation courant permet. La tolérance progresse au fil de la
      // session (+1 toutes les 4 min) — on monte d'un cran pour préparer
      // le score plus haut qu'on visera en fin de séance.
      final humilCap =
          humiliationScore + (progress * 4.0).floorToDouble();
      draft = _enforceHumiliationRequired(draft, humilCap);

      // Anti-saturation : si en projetant ce step on dépasserait 90% alors
      // qu'il reste plus d'1 min avant le pré-finisher, on bascule sur
      // un step de récup pour garder de la marge.
      final secondsLeft = genUntil - time;
      if (secondsLeft > 60) {
        final preview = _runOnEngine(_forkEngine(_excitSim), draft);
        if (preview > 90.0) {
          draft = _enforceHumiliationRequired(_buildRecoveryStep(), humilCap);
          draft = _stripBegFromAfterSoft(draft, steps);
        }
      }

      // Variété BPM : évite d'enchaîner des steps au même tempo.
      draft = _applyBpmDiversity(draft);
      // Variété amplitude : évite d'enchaîner deux fois exactement la
      // même paire from/to dans le même mode.
      draft = _diversifyAmplitude(draft);

      // Sas breath conditionnel : on insère un breath UNIQUEMENT si le
      // draft retenu provoquerait un déficit d'endurance (stamina projetée
      // < 0). Pas de breath gratuit quand on a encore 80% — on ne respire
      // que quand on en a vraiment besoin pour tenir la step suivante.
      // Le breath est à durée variable, calée pour combler le déficit.
      // Skip si le draft est lui-même breath (jamais le cas via la boucle
      // standard) ou si on est à <8s du genUntil (laisse la place au
      // pré-finisher / boost).
      if (draft.mode != SessionMode.breath && genUntil - time > 8) {
        final delta = _staminaDelta(draft, progress, cfg);
        final projected = stamina + delta;
        if (projected < 0) {
          final breathDraft = _buildBreathRecovery(-projected, progress, cfg);
          final breathText = _pickPhrase(bank, SessionMode.breath, 'soft');
          steps.add(_draftToStep(breathDraft, time: time, text: breathText));
          stamina = _applyStaminaChange(stamina, breathDraft, progress, cfg);
          excitation = _runOnEngine(_excitSim, breathDraft);
          _fillProfile(profile, time, breathDraft.duration!, stamina);
          _fillProfile(excitProfile, time, breathDraft.duration!, excitation);
          time += breathDraft.duration!;
          _lastMode = SessionMode.breath;
          _lastText = breathText;
        }
      }

      // Diversification interne : si la step dure plus de 40s et qu'elle
      // est rythmique (rhythm/lick/hand), on la split en 2-3 sous-segments
      // avec une variation BPM/profondeur entre chaque, pour qu'une longue
      // phase ne sonne pas comme un loop monotone.
      final emitDrafts = _diversifyLongSegment(draft);

      final tier = diff < 0.33
          ? 'soft'
          : diff < 0.66
              ? 'medium'
              : 'hard';

      for (var partIdx = 0; partIdx < emitDrafts.length; partIdx++) {
        final partDraft = emitDrafts[partIdx];
        // Texte sur le 1er sous-segment seulement : la phrase est cohérente
        // avec le tier global. Les sous-segments suivants déclencheront
        // automatiquement les phrases de transition (cf. C2) puisque BPM
        // ou profondeur change entre eux.
        final partText = partIdx == 0 ? _pickPhrase(bank, partDraft.mode, tier) : '';
        stamina = _applyStaminaChange(stamina, partDraft, progress, cfg);
        excitation = _runOnEngine(_excitSim, partDraft);
        steps.add(_draftToStep(partDraft, time: time, text: partText));
        _lastMode = partDraft.mode;
        _lastText = partText;
        _lastFrom = partDraft.from;
        _lastTo = partDraft.to;
        _fillProfile(profile, time, partDraft.duration!, stamina);
        _fillProfile(excitProfile, time, partDraft.duration!, excitation);
        time += partDraft.duration!;
      }

      // Chain action attachée au draft principal (beg + suite continue) :
      // émise immédiatement après les sous-segments, sans nouveau texte
      // d'intro (la consigne est déjà dans la phrase du beg).
      final chain = draft.chainNext;
      if (chain != null && chain.duration != null) {
        stamina = _applyStaminaChange(stamina, chain, progress, cfg);
        excitation = _runOnEngine(_excitSim, chain);
        steps.add(_draftToStep(chain, time: time, text: ''));
        _lastMode = chain.mode;
        _lastText = '';
        _lastFrom = chain.from;
        _lastTo = chain.to;
        _fillProfile(profile, time, chain.duration!, stamina);
        _fillProfile(excitProfile, time, chain.duration!, excitation);
        time += chain.duration!;
      }

      if (kDebugMode) {
        debugPrint(
          '[career-gen] t=$time mode=${draft.mode.name} '
          'bpm=${draft.bpm} from=${draft.from?.name} to=${draft.to?.name} '
          'dur=${draft.duration} diff=${diff.toStringAsFixed(2)} '
          'stamina=${stamina.toStringAsFixed(1)} '
          'parts=${emitDrafts.length}',
        );
      }
    }

    // Si la boucle main s'est terminée sans avoir inséré la milestone
    // (durée trop courte pour atteindre la fenêtre, ou `genUntil` faible
    // après le first step), on force l'insertion ici pour qu'elle soit
    // jouée avant le finisher. Cas rare mais on ne veut pas perdre la
    // milestone silencieusement.
    if (milestone != null && !milestoneInserted) {
      insertMilestoneNow();
    }

    // À partir d'ici on entre dans la fenêtre **finish** (pré-finisher +
    // boosts + final + son d'orgasme). Les commentaires aléatoires sont
    // coupés sur cette fenêtre par le contrôleur, pour ne pas qu'une
    // phrase random vienne se chevaucher avec la dramaturgie scriptée
    // (boost « continue je viens », chime, annonce milestone, etc.).
    final silentFinishStartTime = time;

    // Cas milestone-final : la séquence imposée remplace l'ensemble
    // pré-finisher + boosts + step finisher. Pas d'amorce générée — la
    // milestone porte sa propre dramaturgie d'apothéose. On termine la
    // session juste après la séquence (+ congrats text-only) pour laisser
    // `_finish` enchaîner sur la phrase finale + finale_chime.
    if (useFinalMilestone) {
      final finalMilestoneStartTime = time;
      for (final mStep in finalMilestone.sequence) {
        final overrideText =
            milestoneTextResolver?.call(finalMilestone.id, mStep.time);
        steps.add(SessionStep(
          time: time + mStep.time,
          text: overrideText ?? mStep.text,
          mode: mStep.mode,
          bpm: mStep.bpm,
          from: mStep.from,
          to: mStep.to,
          duration: mStep.duration,
        ));
        final mDraft = _stepToDraft(mStep, SessionMode.rhythm);
        stamina = _applyStaminaChange(
            stamina, mDraft, time / effectiveDuration, cfg);
        excitation = _runOnEngine(_excitSim, mDraft);
        _fillProfile(
            profile, time + mStep.time, mStep.duration ?? 0, stamina);
        _fillProfile(
            excitProfile, time + mStep.time, mStep.duration ?? 0, excitation);
      }
      time += finalMilestone.durationSeconds;
      _lastMode = finalMilestone.sequence.last.mode ?? _lastMode;
      _lastText = finalMilestone.sequence.last.text;

      // Catégorise le final pour piocher le bon `finale_chime` côté
      // BeepEngine. Basé sur le dernier step de config de la séquence
      // (= l'action sur laquelle la coach jouit).
      final lastConfigStep = finalMilestone.sequence
          .lastWhere((s) => !s.isTextOnly,
              orElse: () => finalMilestone.sequence.last);
      final lastDraft = _stepToDraft(lastConfigStep, SessionMode.rhythm);
      final finalCategory = _categorizeFinal(lastDraft);

      // Marque l'instant où le dernier step de config de la milestone
      // démarre (= moment où le chime doit retentir). `time` (avant ce
      // bloc) a déjà été incrémenté de finalMilestone.durationSeconds, on
      // recule donc à `finalMilestoneStartTime + lastConfigStep.time` pour
      // pointer le bon instant absolu.
      final finalStepStartTime =
          finalMilestoneStartTime + lastConfigStep.time;

      steps.add(SessionStep(
        time: time,
        text: bank.pickCongrats(_rng),
      ));

      final finalDuration = time + 2;
      final trimmedProfile = List<double>.generate(
        finalDuration,
        (i) => i < profile.length ? profile[i] : stamina,
      );
      final trimmedExcit = List<double>.generate(
        finalDuration,
        (i) => i < excitProfile.length ? excitProfile[i] : excitation,
      );

      return CareerGenerationResult(
        session: Session(
          id: 'career:lvl$level:${effectiveDuration}s${quickie ? ":q" : ""}',
          name: quickie
              ? 'Carrière niveau $level — bâclée'
              : 'Carrière niveau $level',
          description: 'Session générée — $effectiveDuration s',
          durationSeconds: finalDuration,
          defaultMode: SessionMode.rhythm,
          steps: steps,
          milestoneId: milestone?.id,
          milestoneStartTime: milestoneStartTime,
          milestoneDurationSeconds: milestoneDurationSeconds,
          finalMilestoneId: finalMilestone.id,
          finalMilestoneStartTime: finalMilestoneStartTime,
          finalMilestoneDurationSeconds: finalMilestone.durationSeconds,
          finalCategory: finalCategory,
          silentFinishStartTime: silentFinishStartTime,
          finalStepTime: finalStepStartTime,
        ),
        staminaProfile: trimmedProfile,
        excitationProfile: trimmedExcit,
      );
    }

    // Position cible du pré-finisher : profondeur « normale » du niveau,
    // capée par `_maxDepthIndex`. Sert de transition vers le final.
    final preFinisherTarget = _pickFinisherPosition(level);

    // Pré-finisher : pour les bas niveaux, courte accélération (rythme
    // un peu plus rapide que le plafond habituel du niveau) qui débouche
    // sur le final, dans une position d'amorce.
    if (isLowLevel) {
      final preDur = 22 + _rng.nextInt(9); // [22, 30]
      final preBpm = 62 + _rng.nextInt(9); // [62, 70]
      final preDraft = _StepDraft(
        mode: SessionMode.rhythm,
        bpm: preBpm,
        from: Position.head,
        to: preFinisherTarget,
        duration: preDur,
      );
      final preText = _pickPhrase(bank, SessionMode.rhythm, 'medium');
      steps.add(_draftToStep(preDraft, time: time, text: preText));
      _lastMode = SessionMode.rhythm;
      _lastText = preText;
      _fillProfile(profile, time, preDur, stamina);
      excitation = _runOnEngine(_excitSim, preDraft);
      _fillProfile(excitProfile, time, preDur, excitation);
      time += preDur;
    }

    // Choix du template de finish : `hand_burst` (non humiliant, pure
    // intensité) ou `rhythm_burst` (humiliant). Voir B1 du plan.
    // - humiliation faible (<5) ET niveau ≤ 3 : 70% hand, 30% rhythm
    //   (rhythm sera de toute façon doux à ce niveau, autant pousser via hand)
    // - sinon : 75% rhythm, 25% hand (variété)
    final preferHand =
        humiliationScore < 5 && level <= 3 ? 0.70 : 0.25;
    final useHandBurst = _rng.nextDouble() < preferHand;
    final burstMode =
        useHandBurst ? SessionMode.hand : SessionMode.rhythm;

    // Plafond humiliation pour les bursts. Hand n'est pas gating par
    // humiliation (cap inutile), mais on laisse `_enforceHumiliationRequired`
    // tourner — il rejettera juste si la profondeur du draft demande trop.
    final boostHumilCap = humiliationScore + 8.0;
    var boostsAdded = 0;
    // **Forçage minimum de 2 boosts** : la phase finish doit toujours
    // sonner comme un sprint clair, même si la dernière minute du main
    // loop a déjà saturé l'excitation à 100. Sinon le passage main → final
    // perd sa dramaturgie (le commentaire CLAUDE.md notait cette faille).
    const minBoosts = 2;
    // **BPM cap qui scale par niveau** : niveau 1 plafonne à ~110 BPM
    // (hand) / 130 (rhythm), niveau 18 à 170/180. Évite qu'une débutante
    // se retrouve avec head→mid à 168 BPM dans son finish.
    final levelBpmBoost = ((level - 1) * 4).clamp(0, 70);
    final bpmCap = useHandBurst
        ? (110 + levelBpmBoost).clamp(110, 170)
        : (130 + levelBpmBoost).clamp(130, 180);
    final bpmFloor = useHandBurst ? 80 : 100;
    // BPM "ancre" du burst : varie autour de bpmCap selon deficit. Chaque
    // step varie de ±15 par-dessus pour éviter de répéter exactement le
    // même tempo tout en restant clairement en mode finish. La cible (`to`)
    // varie également d'un cran selon le step — sinon on enchaîne 5 fois le
    // même tip→mid à 148 BPM, sensation de stagnation.
    // Cap de profondeur des boosts indexé sur le niveau (proxy de
    // milestone d'introduction) :
    // - jusqu'au niveau 5 : mid (idx 2). Throat n'est pas encore introduit.
    // - niveaux 6-10 : throat (idx 3). intro_hold_throat_short au niveau 6.
    // - niveaux 11+ : full (idx 4). intro_hold_full_short au niveau 11.
    // Borné en plus par `_maxDepthIndex` (sécurité, ne devrait jamais
    // descendre sous le cap niveau ci-dessus).
    final int levelBoostCeiling;
    if (level < 6) {
      levelBoostCeiling = 2;
    } else if (level < 11) {
      levelBoostCeiling = 3;
    } else {
      levelBoostCeiling = 4;
    }
    final boostMaxToIdx =
        min(_maxDepthIndex.clamp(2, 4), levelBoostCeiling);
    // Index dans `steps` du dernier boost ajouté. Sert ensuite à substituer
    // le `text` par une annonce du final (ex: hand → lick → "sors ta langue,
    // j'arrive") quand le mode change pour le finisher.
    int? lastBoostIndex;
    // Monotonie ascendante : la phase finish ne doit JAMAIS ralentir. Chaque
    // boost démarre sur un BPM ≥ au précédent (idem pour la profondeur `to`).
    // Sans ces planchers, le shift aléatoire ±15 et le tirage `boostMaxToIdx
    // -1` pouvaient créer un palier descendant audible — l'utilisateur a
    // explicitement noté ce ralentissement.
    int prevBoostBpm = 0;
    int prevBoostToIdx = 0;
    while (boostsAdded < minBoosts ||
        (excitation < resolvedMinFinal - 1.0 && boostsAdded < 5)) {
      // Durée variable : 12 à 16 s pour casser la régularité.
      final boostDur = 12 + _rng.nextInt(5);
      final deficit = (resolvedMinFinal - excitation).clamp(0.0, 30.0);
      final baseBpm = (bpmCap - 30 + deficit.round()).clamp(bpmFloor, bpmCap);
      // Variabilité contrôlée : on tire +0..+15 BPM par-dessus le base, jamais
      // de décalage négatif. Combiné au plancher `prevBoostBpm`, ça garantit
      // un BPM strictement non-décroissant tout en gardant un peu de hasard.
      final shift = _rng.nextInt(16);
      final bpmRaw = (baseBpm + shift).clamp(bpmFloor, bpmCap);
      // Plancher monotone : on ne descend jamais sous le BPM du boost précédent.
      // Si bpmRaw < prevBoostBpm, on relève à prevBoostBpm (et un cran +5 si
      // possible pour entendre la montée), tronqué par bpmCap.
      final bpm = bpmRaw <= prevBoostBpm
          ? min(prevBoostBpm + 5, bpmCap)
          : bpmRaw;
      // `to` ne redescend jamais sous le `to` précédent. Pour la variété, on
      // peut atteindre boostMaxToIdx ou rester à boostMaxToIdx-1 — mais une
      // fois atteint un niveau de profondeur, on ne revient pas en arrière.
      final toIdxFloor = max(prevBoostToIdx, boostMaxToIdx - 1);
      final toIdx = boostMaxToIdx >= 3 && _rng.nextBool()
          ? max(toIdxFloor, boostMaxToIdx - 1)
          : boostMaxToIdx;
      final boostTo = Position.values[toIdx];
      // `from` : 2 crans au-dessus si possible (pour amplitude max), sinon
      // 1 cran. Permet à un finish niveau 4 (maxDepthIndex=2 → mid) de
      // varier entre tip→mid (amplitude pleine) et head→mid (plus court).
      final boostFromIdx = _rng.nextBool() && toIdx >= 2
          ? max(0, toIdx - 2)
          : max(0, toIdx - 1);
      final boostFrom = Position.values[boostFromIdx];
      final boostDraftRaw = _StepDraft(
        mode: burstMode,
        bpm: bpm,
        from: boostFrom,
        to: boostTo,
        duration: boostDur,
      );
      // Dégrade le boost si humiliation insuffisante. Pour hand, la
      // contrainte humiliation est nulle → pas de dégradation, on garde
      // amplitude max. Pour rhythm, on respecte le cap normal du finish.
      final boostDraft = useHandBurst
          ? boostDraftRaw
          : _enforceHumiliationRequired(boostDraftRaw, boostHumilCap);
      // Tier dédié `boost` : phrases explicites « accélère / on monte /
      // dernier sprint » pour rendre la phase finish lisible. Fallback
      // sur 'hard' si la bank n'a rien dans 'boost'.
      var boostText = _pickPhrase(bank, boostDraft.mode, 'boost');
      if (boostText.isEmpty) {
        boostText = _pickPhrase(bank, boostDraft.mode, 'hard');
      }
      steps.add(_draftToStep(boostDraft, time: time, text: boostText));
      lastBoostIndex = steps.length - 1;
      _lastMode = boostDraft.mode;
      _lastText = boostText;
      _lastBpm = boostDraft.bpm ?? _lastBpm;
      stamina = _applyStaminaChange(stamina, boostDraft, 1.0, cfg);
      excitation = _runOnEngine(_excitSim, boostDraft);
      _fillProfile(profile, time, boostDur, stamina);
      _fillProfile(excitProfile, time, boostDur, excitation);
      time += boostDur;
      boostsAdded++;
      // Mémorise BPM/profondeur retenus (post-dégradation humil) pour que le
      // boost suivant ne puisse pas redescendre sous ce palier.
      prevBoostBpm = boostDraft.bpm ?? prevBoostBpm;
      if (boostDraft.to != null) {
        prevBoostToIdx = max(prevBoostToIdx, boostDraft.to!.index);
      }
    }

    // Final : action longue tenue qui clôture la séance. Distinct de la
    // phase « finish » (boosts) qui pousse l'excitation à 100 ; le final
    // est l'apothéose contemplative. Choisi parmi les candidats valides
    // selon le score d'humiliation, le plafond de profondeur du niveau,
    // et la durée des holds profonds qui scale avec le niveau.
    final finalHumilCap = humiliationScore + 4.0; // rampe progress=1
    final finishMul = resolvedExcitationTarget / 100.0;
    final finisherDraft = _pickFinal(
      humilCap: finalHumilCap,
      includeHand: includeHand,
      maxDepth: _maxDepthIndex,
      level: level,
      finishMul: finishMul,
    );
    final finalCategory = _categorizeFinal(finisherDraft);
    final finalMode = finisherDraft.mode;

    // **Annonce du final sur la step pré-finale** : si le finisher change
    // de mode (ex: dernier boost = hand, finisher = lick), on remplace le
    // texte du dernier boost par une phrase qui prépare l'utilisatrice au
    // changement physique (« sors ta langue, j'arrive »). Sans ça, la
    // bascule de mode arrive sans préavis vocal et casse la dramaturgie.
    if (lastBoostIndex != null && burstMode != finalMode) {
      final announce = bank.pickFinalAnnouncement(
        preMode: burstMode,
        finalMode: finalMode,
        rng: _rng,
      );
      if (announce != null && announce.isNotEmpty) {
        final old = steps[lastBoostIndex];
        steps[lastBoostIndex] = SessionStep(
          time: old.time,
          text: announce,
          from: old.from,
          to: old.to,
          bpm: old.bpm,
          duration: old.duration,
          mode: old.mode,
          chainAction: old.chainAction,
        );
        _lastText = announce;
      }
    }

    // **Phrase d'action sur le step final** : impératif court à exécuter
    // immédiatement (« ouvre ta bouche », « sors ta langue », « avale
    // tout »…). Indexée par mode, et pour `hold` qualifiée par profondeur
    // (bouche / lèvres / gorge). Le `SessionController` joue cette phrase
    // au démarrage du step puis enchaîne le `finale_chime` PENDANT le step
    // (cf. `Session.finalStepTime`) — ainsi l'orgasme retentit sur l'action
    // en cours, pas après. Fallback `congrats` si la banque ne fournit pas
    // de `final_action` pour ce mode.
    final finalActionPhrase = bank.pickFinalAction(
      mode: finalMode,
      holdPosition: finalMode == SessionMode.hold ? finisherDraft.from : null,
      rng: _rng,
    ) ?? '';
    final finalStepStartTime = time;
    final finisherStep =
        _draftToStep(finisherDraft, time: time, text: finalActionPhrase);
    _lastMode = finalMode;
    _lastText = finalActionPhrase;
    final finisherDuration = finisherDraft.duration!;
    steps.add(finisherStep);
    _fillProfile(profile, time, finisherDuration, stamina);
    excitation = _runOnEngine(_excitSim, finisherDraft);
    _fillProfile(excitProfile, time, finisherDuration, excitation);
    time += finisherDuration;

    // **Phase post-final** : ~12 s d'action douce après l'orgasme — la
    // coach ne lâche pas l'utilisatrice net, on profite de la fin. Mode
    // contrastant avec le step final (alternance) pour que l'oreille
    // perçoive bien la bascule « apothéose → calme ». Phrase de compliment
    // douce piochée dans `post_final` (fallback `congrats` si vide).
    // Le pool d'actions est tieré par humiliation : lick (= nettoyer après)
    // est l'aftercare humiliant qui n'apparaît qu'au-dessus d'un seuil.
    final postFinalDraft = _buildPostFinalDraft(finalMode, humiliationScore);
    // Phrase : un step `beg` doit porter une CONSIGNE de supplique
    // (« remercie-moi », « supplie-moi de revenir »), pas un compliment
    // doux qui sonnerait à côté. Cascade de fallback pour ne jamais
    // tomber sur un text vide.
    final postFinalText = postFinalDraft.mode == SessionMode.beg
        ? (bank.pickPostFinalBeg(_rng) ??
            bank.pickPostFinal(_rng) ??
            bank.pickCongrats(_rng))
        : (bank.pickPostFinal(_rng) ?? bank.pickCongrats(_rng));
    final postFinalDuration = postFinalDraft.duration!;
    steps.add(_draftToStep(postFinalDraft, time: time, text: postFinalText));
    _fillProfile(profile, time, postFinalDuration, stamina);
    excitation = _runOnEngine(_excitSim, postFinalDraft);
    _fillProfile(excitProfile, time, postFinalDuration, excitation);
    time += postFinalDuration;
    _lastMode = postFinalDraft.mode;
    _lastText = postFinalText;

    final finalDuration = time + 2;
    final trimmedProfile = List<double>.generate(
      finalDuration,
      (i) => i < profile.length ? profile[i] : stamina,
    );
    final trimmedExcit = List<double>.generate(
      finalDuration,
      (i) => i < excitProfile.length ? excitProfile[i] : excitation,
    );

    return CareerGenerationResult(
      session: Session(
        id: 'career:lvl$level:${effectiveDuration}s${quickie ? ":q" : ""}',
        name: quickie
            ? 'Carrière niveau $level — bâclée'
            : 'Carrière niveau $level',
        description: 'Session générée — $effectiveDuration s',
        durationSeconds: finalDuration,
        defaultMode: SessionMode.rhythm,
        steps: steps,
        milestoneId: milestone?.id,
        milestoneStartTime: milestoneStartTime,
        milestoneDurationSeconds: milestoneDurationSeconds,
        finalCategory: finalCategory,
        silentFinishStartTime: silentFinishStartTime,
        finalStepTime: finalStepStartTime,
      ),
      staminaProfile: trimmedProfile,
      excitationProfile: trimmedExcit,
    );
  }

  /// Construit le step de post-final : action douce contrastante avec le
  /// mode du final, durée 10-15 s, BPM 38-48. La phrase de compliment sera
  /// ajoutée par le caller.
  ///
  /// **Échelle d'humiliation post-final** (du moins au plus humiliant,
  /// validée avec l'utilisateur) :
  ///
  /// 1. `breath` (req 0) — pure récup, jamais bloqué
  /// 2. `hand` tip→head lent (req 8) — main douce sur la pointe
  /// 3. `hold tip` (req 20) — bisou prolongé, immobilisation légère
  /// 4. `beg` libre (req 25) — supplique vocale (« remercie-moi »…)
  /// 5. `lick` tip→head lent (req 35) — « nettoyer après »
  /// 6. `rhythm` tip→head lent (req 55) — « continue à me sucer encore »
  /// 7. `beg` from=head (req 60) — supplique avec bouche tenue sur le gland
  /// 8. `hold head` (req 70) — bouche tenue sur le gland, post-orgasme
  ///
  /// Stratégie de tirage : on filtre par humilCap, on **alterne** avec le
  /// mode du final (si final = hold, pas de hold post ; si final = lick,
  /// pas de lick post ; etc.), puis on prend les **3 plus humiliantes
  /// accessibles** et on tire uniformément dedans. Garde un peu de variété
  /// tout en respectant la progression : à humil 5 on tombe sur breath,
  /// à humil 100 on tombe sur les beg + hold head.
  _StepDraft _buildPostFinalDraft(
      SessionMode finalMode, double humiliationScore) {
    final dur = 10 + _rng.nextInt(6); // [10, 15]
    final bpm = 38 + _rng.nextInt(11); // [38, 48]
    // Builders à la volée — un `const` figerait dur/bpm tirés ici.
    _StepDraft breath() => _StepDraft(
          mode: SessionMode.breath,
          bpm: null,
          from: null,
          to: null,
          duration: dur,
        );
    _StepDraft hand() => _StepDraft(
          mode: SessionMode.hand,
          bpm: bpm,
          from: Position.tip,
          to: Position.head,
          duration: dur,
        );
    _StepDraft holdTip() => _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: Position.tip,
          to: null,
          duration: dur,
        );
    _StepDraft lick() => _StepDraft(
          mode: SessionMode.lick,
          bpm: bpm,
          from: Position.tip,
          to: Position.head,
          duration: dur,
        );
    _StepDraft rhythm() => _StepDraft(
          mode: SessionMode.rhythm,
          bpm: bpm,
          from: Position.tip,
          to: Position.head,
          duration: dur,
        );
    _StepDraft holdHead() => _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: Position.head,
          to: null,
          duration: dur,
        );
    _StepDraft begLibre() => _StepDraft(
          mode: SessionMode.beg,
          bpm: null,
          from: null,
          to: null,
          duration: dur,
        );
    _StepDraft begHead() => _StepDraft(
          mode: SessionMode.beg,
          bpm: null,
          from: Position.head,
          to: null,
          duration: dur,
        );
    // Échelle ordonnée. `blocked` exclut le mode du final (alternance) et,
    // pour les beg, vérifie l'unlock `begLibre` (sinon on demanderait à
    // une utilisatrice qui n'a pas encore validé la milestone d'introduction
    // au beg de supplier post-orgasme — pédagogiquement faux).
    final isFinalHold = finalMode == SessionMode.hold;
    final canBeg = _unlockedKeys.contains(UnlockKey.begLibre);
    final candidates = <(double req, bool blocked, _StepDraft Function() build)>[
      (0.0, false, breath),
      (8.0, !_includeHand || finalMode == SessionMode.hand, hand),
      (20.0, isFinalHold, holdTip),
      (25.0, !canBeg, begLibre),
      (35.0, finalMode == SessionMode.lick, lick),
      (55.0, finalMode == SessionMode.rhythm, rhythm),
      (60.0, !canBeg, begHead),
      (70.0, isFinalHold, holdHead),
    ];
    final valid = candidates
        .where((c) => c.$1 <= humiliationScore && !c.$2)
        .toList()
      ..sort((a, b) => b.$1.compareTo(a.$1)); // req décroissante
    if (valid.isEmpty) return breath();
    // Top 3 : tirage uniforme dans les 3 plus humiliantes accessibles.
    // Donne de la variété sans casser la progression d'humiliation.
    final top = valid.take(3).toList();
    return top[_rng.nextInt(top.length)].$3();
  }

  /// Convertit un [SessionStep] (issu du JSON ou d'une milestone) en
  /// [_StepDraft] interne pour pouvoir le passer à `_applyStaminaChange`
  /// et `_runOnEngine`. Inverse le swap from↔to fait par `_draftToStep`
  /// pour les modes hold/beg.
  _StepDraft _stepToDraft(SessionStep step, SessionMode defaultMode) {
    final mode = step.mode ?? defaultMode;
    final isHoldLike =
        mode == SessionMode.hold || mode == SessionMode.beg;
    return _StepDraft(
      mode: mode,
      bpm: step.bpm,
      from: isHoldLike ? step.to : step.from,
      to: isHoldLike ? null : step.to,
      duration: step.duration ?? 0,
    );
  }

  /// Step d'intro. Modes hardcodés pour quickie / intense (besoins
  /// dramaturgiques spécifiques). En séance normale, panel de variantes
  /// douces : lick et rhythm en amplitude limitée, plus une option hand
  /// pour la variété. Filtré par `_maxDepthIndex` (head→mid n'apparaît pas
  /// si le niveau plafonne à head) et `_includeHand`.
  _StepDraft _firstStep({
    bool quickie = false,
    bool intense = false,
  }) {
    if (intense) {
      // Plus profond et plus rapide que quickie : la régen post-Supplier
      // est censée prouver que l'utilisatrice « monte d'un niveau ».
      // Plafonné par maxDepthIndex pour rester dans le contrat du niveau.
      final to = Position.values[_maxDepthIndex.clamp(2, 3)];
      return _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 90,
        from: Position.head,
        to: to,
        duration: 10,
      );
    }
    if (quickie) {
      return const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 75,
        from: Position.head,
        to: Position.mid,
        duration: 8,
      );
    }
    // Panel de variantes : on retient seulement celles compatibles avec
    // le niveau (head→mid demande maxDepthIndex ≥ 2, déjà le cas dès
    // niveau 1) et avec `_includeHand`. Tirage uniforme dans la liste
    // filtrée pour assurer la variété demandée — chaque variante a une
    // signature identifiable (lick lent, rhythm doux superficiel, rhythm
    // amplitude moyenne, hand amorce).
    final allowMid = _maxDepthIndex >= Position.mid.index;
    final variants = <_StepDraft>[
      const _StepDraft(
        mode: SessionMode.lick,
        bpm: 60,
        from: Position.tip,
        to: Position.head,
        duration: 20,
      ),
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 65,
        from: Position.tip,
        to: Position.head,
        duration: 16,
      ),
      if (allowMid)
        const _StepDraft(
          mode: SessionMode.rhythm,
          bpm: 70,
          from: Position.head,
          to: Position.mid,
          duration: 14,
        ),
      if (allowMid)
        const _StepDraft(
          mode: SessionMode.rhythm,
          bpm: 65,
          from: Position.tip,
          to: Position.mid,
          duration: 16,
        ),
      if (_includeHand)
        const _StepDraft(
          mode: SessionMode.hand,
          bpm: 55,
          from: Position.tip,
          to: Position.head,
          duration: 18,
        ),
    ];
    return variants[_rng.nextInt(variants.length)];
  }

  /// Construit un step `breath` dont la durée est calculée pour combler
  /// exactement un déficit d'endurance projeté. Borné à [3, 15] secondes :
  /// au-delà, on préfère raccourcir la step suivante plutôt qu'imposer
  /// une respi interminable.
  _StepDraft _buildBreathRecovery(
    double deficit,
    double progress,
    CareerLevel cfg,
  ) {
    final regen = _lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    // Cohérent avec `_staminaDelta` pour breath : `dur * 1.4 * regen`.
    final regenPerSec = 1.4 * regen;
    final raw = deficit / (regenPerSec <= 0 ? 1.0 : regenPerSec);
    final dur = raw.ceil().clamp(3, 15);
    return _StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Tirage d'un step "respi active" : mode parmi lick/biffle/beg/freestyle,
  /// BPM ≤ 60 pour déclencher la regen d'endurance. Le mode `breath` n'est
  /// plus tiré ici — il est désormais inséré strictement sur déficit
  /// d'endurance projeté (cf. `_buildBreathRecovery`), pas comme une option
  /// d'humeur générale.
  _StepDraft _buildRecoveryStep() {
    final canBeg = _unlockedKeys.contains(UnlockKey.begLibre);
    final canFreestyle = _unlockedKeys.contains(UnlockKey.freestyle)
        && _level >= HumiliationScale.freestyleMinLevel;
    final candidates = [
      SessionMode.lick,
      if (_includeHand) SessionMode.biffle,
      if (canBeg) SessionMode.beg,
      if (canFreestyle) SessionMode.freestyle,
    ];
    final pool = _filterRepeated(candidates);
    final mode = pool[_rng.nextInt(pool.length)];
    final bpm = 45 + _rng.nextInt(14); // [45, 58]
    final dur = 10 + _rng.nextInt(9); // [10, 18]
    _StepDraft draft;
    if (mode == SessionMode.beg) {
      // Récup vocale par défaut : sans position (= beg libre). Si begLibre
      // n'est pas encore débloqué, on dégrade via _enforceHumiliationRequired
      // qui retombera sur beg head ou lick selon la situation.
      final begDur = 6 + _rng.nextInt(6);
      draft = _StepDraft(
        mode: mode,
        bpm: null,
        from: null,
        to: null,
        duration: begDur,
      );
    } else if (mode == SessionMode.freestyle) {
      // Phase libre : neutre. Encadre le repos sans bip de loop.
      final freeDur = 8 + _rng.nextInt(8);
      draft = _StepDraft(
        mode: mode,
        bpm: null,
        from: null,
        to: null,
        duration: freeDur,
      );
    } else {
      final (from, to) = _sampleFromTo(0.3);
      draft = _StepDraft(
        mode: mode,
        bpm: bpm,
        from: from,
        to: to,
        duration: dur,
      );
    }
    // Gating unlock : si le mode/draft tiré n'est pas encore débloqué (ex :
    // biffle avant niveau 5, beg libre avant niveau 3, freestyle avant
    // niveau 4), on dégrade. Évite que la phase de récup laisse passer une
    // action contractuellement réservée à plus tard.
    if (!_isUnlocked(draft)) {
      return _StepDraft(
        mode: SessionMode.lick,
        bpm: bpm,
        from: Position.tip,
        to: Position.head,
        duration: dur,
      );
    }
    return draft;
  }

  /// Convertit la difficulté `diff ∈ [0, 1]` en step concret. Le budget est
  /// réparti aléatoirement entre les axes BPM, amplitude et durée — donc un
  /// step "hard" peut être lent profond endurant, ou rapide plus court, etc.
  _StepDraft _mapDifficultyToStep(double diff) {
    final candidates = <SessionMode>[];
    if (diff < 0.30) {
      candidates.add(SessionMode.lick);
    }
    if (diff >= 0.20) {
      candidates.add(SessionMode.rhythm);
      candidates.add(SessionMode.hold);
    }
    if (diff >= 0.40 && _includeHand) {
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
    // transverse à toutes les formes de beg, cf. `_isUnlocked`).
    final canBeg = _unlockedKeys.contains(UnlockKey.begLibre);
    if (canBeg) {
      // Sa difficulté effective est portée par `from` (head = doux,
      // full = comme un hold profond), pas par diff.
      candidates.add(SessionMode.beg);
    }
    // breath n'est jamais un step "d'effort" : il n'est tiré que par
    // _buildRecoveryStep quand l'endurance est basse, jamais ici.
    if (candidates.isEmpty) candidates.add(SessionMode.rhythm);
    final mode = _pickWeightedMode(_filterRepeated(candidates));

    final (aBpm, aAmp, aDur) = _sampleSimplex3();
    var bpmScore = (diff * 3 * aBpm).clamp(0.0, 1.0);
    var ampScore = (diff * 3 * aAmp).clamp(0.0, 1.0);
    var durScore = (diff * 3 * aDur).clamp(0.0, 1.0);
    // Bonus de spé sur les axes (capés 1.0).
    bpmScore = (bpmScore + 0.05 * _pts(SpecializationBranch.rythmeBiffle))
        .clamp(0.0, 1.0);
    ampScore = (ampScore + 0.05 * _pts(SpecializationBranch.profondeur))
        .clamp(0.0, 1.0);
    durScore = (durScore + 0.05 * _pts(SpecializationBranch.endurance))
        .clamp(0.0, 1.0);

    switch (mode) {
      case SessionMode.rhythm:
        final bpm = _lerp(60.0, 140.0, bpmScore).round();
        final (from, to) = _sampleFromTo(ampScore);
        final dur = _scaleDuration(
          _lerp(20.0, 60.0, durScore),
          enduranceFactor: 0.05,
          resilienceFactor: 0.04,
        );
        return _StepDraft(mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.biffle:
        final bpm = _lerp(80.0, 140.0, bpmScore).round();
        final (from, to) = _sampleFromTo(ampScore);
        final dur = _scaleDuration(
          _lerp(15.0, 40.0, durScore),
          enduranceFactor: 0.05,
        );
        return _StepDraft(mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.hold:
        final from = _pickHoldPosition(ampScore);
        final dur = _scaleDuration(
          _lerp(8.0, 30.0, max(durScore, bpmScore)),
          enduranceFactor: 0.08,
          resilienceFactor: 0.07,
        );
        return _StepDraft(mode: mode, bpm: null, from: from, to: null, duration: dur);
      case SessionMode.lick:
        // Sloppy : monte le BPM minimum (≥ 65 = lick humide / saliveux).
        final sloppyPts = _pts(SpecializationBranch.sloppy);
        final lickBpmScore =
            sloppyPts > 0 ? max(bpmScore, 0.3) : bpmScore;
        final bpm = _lerp(55.0, 80.0, lickBpmScore).round();
        // Tirage spécifique lick : tip→head forcé tant qu'humiliation < 2,
        // toutes amplitudes (incluant tip → throat/full) à partir de 2.
        final (from, to) = _sampleFromToForLick(ampScore);
        final dur = _scaleDuration(
          _lerp(10.0, 25.0, durScore),
          enduranceFactor: 0.04,
        );
        return _StepDraft(mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.breath:
        final dur = _lerp(6.0, 15.0, durScore).round();
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: null, duration: dur);
      case SessionMode.beg:
        // Obéissance : beg plus profonds (ampScore boosté localement) et
        // plus longs.
        final obPts = _pts(SpecializationBranch.obeissance);
        final begAmp =
            (ampScore + 0.10 * obPts).clamp(0.0, 1.0);
        final from = _pickBegPosition(begAmp);
        final baseDur = _scaleDuration(
          _lerp(7.0, 16.0, durScore),
          enduranceFactor: 0.04,
          extraFactor: obPts * 0.06,
        );
        final chained = _maybePickBegWithChain(
          from: from,
          obPts: obPts,
        );
        if (chained != null) return chained;
        return _StepDraft(
            mode: mode, bpm: null, from: from, to: null, duration: baseDur);
      case SessionMode.hand:
        // Hand sert d'outil d'excitation/endurance pure : sa fréquence peut
        // grimper sans coût d'humiliation. Plage très large pour permettre
        // récup lente (60 BPM) jusqu'à burst frénétique (180 BPM).
        final bpm = _lerp(60.0, 180.0, bpmScore).round();
        // Tirage spécifique hand : la main tient la base de la queue, donc
        // l'amplitude reste dans le haut (jamais plus profond que throat).
        // En revanche tip→head et head→head sont autorisés (le tirage
        // commun les exclut pour les autres modes).
        final (from, to) = _sampleFromToForHand(ampScore);
        final dur = _scaleDuration(
          _lerp(15.0, 30.0, durScore),
          enduranceFactor: 0.04,
        );
        return _StepDraft(mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.freestyle:
        final dur = _lerp(8.0, 18.0, durScore).round();
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: null, duration: dur);
    }
  }

  /// Pondère le tirage du mode selon la spécialisation. Plus de points
  /// dans une branche → plus de chances de tirer les modes correspondants.
  /// Les coefficients restent modérés (0.3–0.6) pour ne pas écraser la
  /// variété — la spé donne une couleur, pas un monomode.
  SessionMode _pickWeightedMode(List<SessionMode> candidates) {
    final weights = <double>[];
    for (final m in candidates) {
      weights.add(_modeWeight(m));
    }
    final total = weights.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      return candidates[_rng.nextInt(candidates.length)];
    }
    var roll = _rng.nextDouble() * total;
    for (var i = 0; i < candidates.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return candidates[i];
    }
    return candidates.last;
  }

  double _modeWeight(SessionMode m) {
    final base = _modeBaseWeight(m);
    final coachFactor = _coachModeWeights[m] ?? 1.0;
    final result = base * coachFactor;
    return result < 0 ? 0 : result;
  }

  /// Pondération issue de la spé seule, sans le filtre coach. Le coach
  /// (s'il en fournit) multiplie ce score dans `_modeWeight`.
  double _modeBaseWeight(SessionMode m) {
    switch (m) {
      case SessionMode.rhythm:
        return 1.0 + 0.20 * _pts(SpecializationBranch.rythmeBiffle);
      case SessionMode.biffle:
        return 1.0 + 0.40 * _pts(SpecializationBranch.rythmeBiffle) +
            0.15 * _pts(SpecializationBranch.sloppy);
      case SessionMode.hold:
        return 1.0 + 0.40 * _pts(SpecializationBranch.endurance) +
            0.20 * _pts(SpecializationBranch.profondeur);
      case SessionMode.lick:
        return 1.0 + 0.50 * _pts(SpecializationBranch.sloppy);
      case SessionMode.beg:
        return 1.0 + 0.60 * _pts(SpecializationBranch.obeissance);
      case SessionMode.hand:
        // Poids un peu boosté : le mode hand doit apparaître plus souvent
        // qu'un mode marginal car il sert de respiration entre les phases
        // « bouche ». Sans ça les bas niveaux n'en voient quasi jamais.
        return 1.4;
      case SessionMode.breath:
      case SessionMode.freestyle:
        return 1.0;
    }
  }

  /// Applique aux durées les multiplicateurs de spé, capés.
  /// `enduranceFactor` = bonus par point Endurance ; `resilienceFactor` =
  /// bonus par point Résilience (allonge les phases dures pour augmenter
  /// la probabilité de fail → la coach a plus à punir, en ligne avec
  /// l'esprit de la branche). `extraFactor` = bonus brut additionnel.
  int _scaleDuration(
    double base, {
    double enduranceFactor = 0.0,
    double resilienceFactor = 0.0,
    double extraFactor = 0.0,
  }) {
    final mul = 1.0 +
        enduranceFactor * _pts(SpecializationBranch.endurance) +
        resilienceFactor * _pts(SpecializationBranch.resilience) +
        extraFactor;
    final capped = mul.clamp(1.0, 1.6);
    return (base * capped).round();
  }

  int _pts(SpecializationBranch b) => _spec.pointsIn(b);

  /// Comptabilité endurance : modes effort consomment (taux ~doublés
  /// par rapport à la v1, qui descendait beaucoup trop lentement), modes
  /// respi ≤ 60 BPM régénèrent (multiplicateur qui monte avec t),
  /// au-dessus c'est neutre.
  ///
  /// Plafond haut respecté (`_staminaMax`) pour éviter qu'un long break
  /// ne capitalise indéfiniment ; pas de plancher bas — on autorise une
  /// dette d'endurance qui sera comblée par le sas breath conditionnel
  /// (cf. `_buildBreathRecovery`). Les bas niveaux ne descendaient jamais
  /// sous 90 à cause du clamp à 0 combiné aux faibles deltas — le sas
  /// breath ne se déclenchait alors quasiment jamais.
  double _applyStaminaChange(
    double stamina,
    _StepDraft draft,
    double progress,
    CareerLevel cfg,
  ) {
    final next = stamina + _staminaDelta(draft, progress, cfg);
    return next > _staminaMax ? _staminaMax : next;
  }

  /// Variante "brute" du delta endurance : retourne le coût (négatif) ou
  /// le gain (positif) sans clamp, pour pouvoir détecter un déficit projeté
  /// (= dette d'endurance qu'il faut combler par un breath, cf. D3).
  double _staminaDelta(
    _StepDraft draft,
    double progress,
    CareerLevel cfg,
  ) {
    final dur = draft.duration ?? 0;
    var next = 0.0;
    switch (draft.mode) {
      case SessionMode.rhythm:
        final bpm = (draft.bpm ?? 60).toDouble();
        final depth = _positionDepth(draft.from, draft.to);
        // Multiplicateur de coût accentué dès que `to` atteint mid
        // (idx 2). Sur les bas niveaux, c'est la profondeur où on tient
        // le rythme la plus longtemps, et l'endurance ne descendait
        // quasiment pas — ajout d'un coup de fatigue plus marqué.
        // to=mid: ×1.45, to=throat: ×1.30, to=full: ×1.15.
        final toIdx = (draft.to ?? draft.from)?.index ?? 0;
        final depthMul = toIdx >= Position.full.index
            ? 1.15
            : toIdx >= Position.throat.index
                ? 1.30
                : toIdx >= Position.mid.index
                    ? 1.45
                    : 1.0;
        next -= (bpm / 100.0) * depth * dur * depthMul / 3.0;
      case SessionMode.hold:
        final depth = _positionDepth(draft.from, draft.from);
        next -= depth * dur / 2.5;
      case SessionMode.biffle:
        // Biffle = effort soutenu (la fille encaisse), conso entre rythme
        // et hold, modulée par la profondeur.
        final bpm = (draft.bpm ?? 80).toDouble();
        final depth = _positionDepth(draft.from, draft.to);
        next -= (bpm / 100.0) * depth * dur / 3.5;
      case SessionMode.beg:
        // Sans `from` ou `from = head` → assimilé à du repos vocal (regen).
        // Avec `from = mid/throat/full` → coût comme un hold à cette
        // profondeur (la position doit être tenue pendant la supplique).
        final from = draft.from;
        if (from == null || from == Position.head) {
          final regen = _lerp(
            cfg.regenStartMultiplier,
            cfg.regenEndMultiplier,
            progress,
          );
          next += dur * 1.0 * regen;
        } else {
          final depth = _positionDepth(from, from);
          next -= depth * dur / 2.5;
        }
      case SessionMode.lick:
        final bpm = draft.bpm ?? 60;
        if (bpm <= 60) {
          // Lick lent = vraie récup vocale.
          final regen = _lerp(
            cfg.regenStartMultiplier,
            cfg.regenEndMultiplier,
            progress,
          );
          next += dur * 1.2 * regen;
        } else {
          // Lick plus vite = effort léger, on ne récupère plus et on
          // s'épuise un peu.
          final depth = _positionDepth(draft.from, draft.to);
          next -= depth * dur / 8.0;
        }
      case SessionMode.breath:
        // Toujours regen : breath n'est jamais un step d'effort.
        final regen = _lerp(
          cfg.regenStartMultiplier,
          cfg.regenEndMultiplier,
          progress,
        );
        next += dur * 1.4 * regen;
      case SessionMode.hand:
        // Hand = effort modéré côté endurance (la bouche se repose, mais
        // la main travaille). On consomme moins que rhythm équivalent.
        final bpm = (draft.bpm ?? 80).toDouble();
        final depth = _positionDepth(draft.from, draft.to);
        next -= (bpm / 100.0) * depth * dur / 6.0;
      case SessionMode.freestyle:
        // Phase libre : neutre côté endurance (ni effort ni vraie regen).
        break;
    }
    return next;
  }

  /// Si [draft] est un `beg` qui suit immédiatement un `lick` ou un
  /// `breath`, retourne une copie sans `from` (récup vocale pure).
  /// Sinon, renvoie [draft] tel quel.
  _StepDraft _stripBegFromAfterSoft(
    _StepDraft draft,
    List<SessionStep> steps,
  ) {
    if (draft.mode != SessionMode.beg) return draft;
    if (draft.from == null) return draft;
    if (steps.isEmpty) return draft;
    final prev = steps.last.mode;
    if (prev != SessionMode.lick && prev != SessionMode.breath) return draft;
    return _StepDraft(
      mode: draft.mode,
      bpm: draft.bpm,
      from: null,
      to: draft.to,
      duration: draft.duration,
    );
  }

  /// Profondeur effective du step : index max du couple (from, to), 1..5.
  /// `tip` = 1, `full` = 5.
  double _positionDepth(Position? from, Position? to) {
    final fIdx = from?.index ?? 0;
    final tIdx = to?.index ?? fIdx;
    return (max(fIdx, tIdx) + 1).toDouble();
  }

  /// Tire un couple (from, to) tel que `from.index < to.index` strictement.
  ///
  /// `ampScore = 0` → head→mid (baseline). `ampScore = 1` → tip→full ou
  /// mid→full. Garantit la contrainte from < to.
  ///
  /// Choix de design : `from = head` est la baseline, `from = tip` reste
  /// possible mais minoritaire (~15%) — sinon on se retrouve avec une
  /// majorité de tip→head en début de session, alors que la position de
  /// référence pour la coach est head.
  (Position, Position) _sampleFromTo(double ampScore) {
    final clamped = ampScore.clamp(0.0, 1.0);
    // Min mid (idx 2) au lieu de head (idx 1) : l'amplitude minimale est
    // head→mid, pas tip→head. Plafond cappé par le niveau via _maxDepthIndex.
    final ceiling = _maxDepthIndex.clamp(2, 4);
    var deepestIdx = _lerp(2.0, ceiling.toDouble(), clamped).round().clamp(2, ceiling);
    // Bonus Profondeur (spé) : remonte la probabilité de profond, dans
    // la limite du plafond niveau.
    final depthPts = _pts(SpecializationBranch.profondeur);
    final boostedDeepProb =
        (_deepProbability + 0.08 * depthPts).clamp(0.0, 1.0);
    // Si le tirage demande une position profonde (≥ throat) mais que la
    // probabilité du niveau ne le permet pas, on rabat sur mid.
    if (deepestIdx >= 3 && _rng.nextDouble() >= boostedDeepProb) {
      deepestIdx = 2;
    }
    final int shallowestIdx;
    if (deepestIdx >= 3 && _rng.nextDouble() < 0.15) {
      // ~15% : tip pour les amplitudes pleines (tip→full marque bien).
      // Réservé aux niveaux qui autorisent throat+ (sinon tip→mid c'est
      // pas vraiment "plein").
      shallowestIdx = 0;
    } else {
      // Sinon : head ou plus profond (jamais tip), uniforme entre les
      // positions admissibles.
      shallowestIdx = 1 + _rng.nextInt(deepestIdx - 1);
    }
    return (
      Position.values[shallowestIdx],
      Position.values[deepestIdx],
    );
  }

  /// Tirage spécifique au mode hand. La main tient la base de la queue,
  /// donc on plafonne la profondeur à throat (jamais full, contrairement
  /// au tirage générique). On autorise l'amplitude courte tip→head qui
  /// est exclue du tirage générique. Cap supplémentaire par
  /// `_maxDepthIndex` (ne dépassera jamais throat même si le niveau
  /// autorise full).
  ///
  /// **Règle transverse** : `from` et `to` désignent toujours deux zones
  /// différentes (`from.index < to.index` strict). Pas de stimulation sur
  /// place (head/head, mid/mid…) — ça n'a pas de sens sémantique pour un
  /// mode rythmé qui alterne entre deux positions.
  (Position, Position) _sampleFromToForHand(double ampScore) {
    final clamped = ampScore.clamp(0.0, 1.0);
    // Profondeur cible bornée à throat (idx 3). Et également capée par
    // _maxDepthIndex pour les bas niveaux qui n'ont pas encore throat.
    // Floor à 1 (head) pour pouvoir avoir tip→head comme amplitude
    // minimale ; mais si _maxDepthIndex <= 0 (cas pathologique), on
    // remonte à au moins 1 pour garder un from < to possible.
    final ceiling = min(3, _maxDepthIndex.clamp(1, 4));
    // ampScore=0 → idx 1 (head). ampScore=1 → ceiling (throat ou max niveau).
    var deepestIdx =
        _lerp(1.0, ceiling.toDouble(), clamped).round().clamp(1, ceiling);
    // Si throat tiré mais le niveau ne le permet probabilistiquement pas,
    // on rabat sur mid (cohérent avec la logique de _sampleFromTo).
    if (deepestIdx >= 3 &&
        _rng.nextDouble() >= _deepProbability.clamp(0.0, 1.0)) {
      deepestIdx = 2;
    }
    // shallowestIdx : strictement plus petit que deepestIdx. Avec
    // deepestIdx=1 (head), seul tip est possible → tip→head garanti.
    // Avec deepestIdx ∈ {2 (mid), 3 (throat)}, parmi tip ou head.
    final int shallowestIdx;
    if (deepestIdx == 1) {
      shallowestIdx = 0;
    } else {
      shallowestIdx = _rng.nextInt(2);
    }
    return (
      Position.values[shallowestIdx],
      Position.values[deepestIdx],
    );
  }

  /// Tirage spécifique au mode lick. Tant que `_humiliationScore < 2`,
  /// le lick reste sur tip→head (l'utilisatrice n'a pas encore appris à
  /// lécher plus profond). À partir de 2, toutes les amplitudes du tirage
  /// générique sont autorisées, y compris tip→throat/full pour les
  /// amplitudes pleines.
  (Position, Position) _sampleFromToForLick(double ampScore) {
    if (_humiliationScore < 2.0) {
      return (Position.tip, Position.head);
    }
    return _sampleFromTo(ampScore);
  }

  /// Choix de la position d'un hold selon ampScore : mid / throat / full.
  /// Bornée par `_maxDepthIndex` et `_deepProbability` du niveau, avec
  /// bonus de spé Profondeur.
  Position _pickHoldPosition(double ampScore) {
    final ceiling = _maxDepthIndex;
    final depthPts = _pts(SpecializationBranch.profondeur);
    // Bonus Profondeur : décale les seuils de tirage vers le profond.
    final adjusted = (ampScore + 0.06 * depthPts).clamp(0.0, 1.0);
    final boostedDeepProb =
        (_deepProbability + 0.08 * depthPts).clamp(0.0, 1.0);
    Position pick;
    if (adjusted < 0.33) {
      pick = Position.mid;
    } else if (adjusted < 0.66) {
      pick = Position.throat;
    } else {
      pick = Position.full;
    }
    if (pick.index > ceiling) pick = Position.values[ceiling];
    if (pick.index >= 3 && _rng.nextDouble() >= boostedDeepProb) {
      pick = Position.mid;
    }
    return pick;
  }

  /// Choix de la position du hold final selon le niveau. Bas niveau : on
  /// reste sur mid/throat, pour ne pas demander un full d'entrée. Niveau
  /// intermédiaire : tirage parmi mid/throat/full. Haut niveau : full.
  /// Capé en plus par `_maxDepthIndex` (niveau 1 = mid forcé).
  Position _pickFinisherPosition(int level) {
    Position pick;
    if (level <= 1) {
      pick = Position.mid;
    } else if (level <= 2) {
      pick = _rng.nextBool() ? Position.mid : Position.throat;
    } else if (level <= 4) {
      final r = _rng.nextDouble();
      if (r < 0.30) {
        pick = Position.mid;
      } else if (r < 0.70) {
        pick = Position.throat;
      } else {
        pick = Position.full;
      }
    } else {
      pick = Position.full;
    }
    if (pick.index > _maxDepthIndex) pick = Position.values[_maxDepthIndex];
    return pick;
  }

  /// Tente de transformer un beg simple en beg + action enchaînée
  /// (« dis X et continue à me sucer »). Retourne `null` quand aucun
  /// template ne passe les unlocks ou quand le tirage aléatoire l'emporte.
  /// Probabilité 0.20 → 0.60 selon l'obéissance investie.
  ///
  /// **Palette V1** (gating naturel par `_isUnlocked` sur les composants) :
  /// 1. beg libre 12 s + rhythm tip→head 80 BPM 18 s
  /// 2. beg libre 10 s + lick tip→head 70 BPM 14 s
  /// 3. beg libre 12 s + hold head 6 s
  /// 4. beg head 8 s + lick head→mid 65 BPM 12 s (gated begThroat)
  ///
  /// Le tirage est uniforme parmi les templates dont les deux composants
  /// passent `_isUnlocked`. `null` si aucun ne passe.
  _StepDraft? _maybePickBegWithChain({
    required Position? from,
    required int obPts,
  }) {
    // Pour V1, on n'attache une chain que sur un beg libre (from == null).
    // Les beg avec position tenue (mid/throat/full) sont déjà mécaniquement
    // chargés, on ne veut pas y greffer une seconde action en plus.
    if (from != null) return null;
    final probability = 0.20 + 0.05 * obPts;
    if (_rng.nextDouble() > probability.clamp(0.20, 0.60)) return null;

    final candidates = <(_StepDraft, _StepDraft)>[];
    for (final tpl in _begChainTemplates) {
      if (!_isUnlocked(tpl.$1) || !_isUnlocked(tpl.$2)) continue;
      candidates.add(tpl);
    }
    if (candidates.isEmpty) return null;
    final pick = candidates[_rng.nextInt(candidates.length)];
    return _StepDraft(
      mode: pick.$1.mode,
      bpm: pick.$1.bpm,
      from: pick.$1.from,
      to: pick.$1.to,
      duration: pick.$1.duration,
      chainNext: pick.$2,
    );
  }

  /// Templates `(beg, chainAction)` pour la palette `_maybePickBegWithChain`.
  /// La durée du beg est l'enveloppe : pour un beg libre on l'écrase par
  /// `baseDuration` clampé entre les deux bornes définies ici (utilisé
  /// comme min/max). Pour un beg ancré (`from != null`), on garde tel quel.
  static const List<(_StepDraft, _StepDraft)> _begChainTemplates = [
    // Beg libre + rhythm tip→head 80 BPM 18 s.
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 12,
      ),
      _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 80,
        from: Position.tip,
        to: Position.head,
        duration: 18,
      ),
    ),
    // Beg libre + lick tip→head 70 BPM 14 s.
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 10,
      ),
      _StepDraft(
        mode: SessionMode.lick,
        bpm: 70,
        from: Position.tip,
        to: Position.head,
        duration: 14,
      ),
    ),
    // Beg libre + hold head 6 s.
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 12,
      ),
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: Position.head,
        to: null,
        duration: 6,
      ),
    ),
    // Beg head + lick head→mid 65 BPM 12 s — profil obéissance avancée
    // (gated par begThroat car beg from non-null).
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: Position.head,
        to: null,
        duration: 8,
      ),
      _StepDraft(
        mode: SessionMode.lick,
        bpm: 65,
        from: Position.head,
        to: Position.mid,
        duration: 12,
      ),
    ),
  ];

  /// Choix de la position d'un beg selon ampScore. Retourne null pour
  /// `ampScore < 0.40` → beg libre (sans position). Sinon : mid → throat
  /// → full. Jamais head ou tip (pas de sens : un beg léger doit être
  /// libre, ancrer la position de tenue ne commence qu'à mid).
  Position? _pickBegPosition(double ampScore) {
    if (ampScore < 0.40) return null;
    if (ampScore < 0.65) return Position.mid;
    if (ampScore < 0.85) return Position.throat;
    return Position.full;
  }

  /// Tire un point uniforme sur le simplexe 3D (a + b + c = 1, tous > 0).
  /// Méthode des "barres de Dirichlet" : 2 cuts uniformes dans [0,1] triés
  /// délimitent 3 segments.
  (double, double, double) _sampleSimplex3() {
    final a = _rng.nextDouble();
    final b = _rng.nextDouble();
    final lo = min(a, b);
    final hi = max(a, b);
    return (lo, hi - lo, 1.0 - hi);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

  void _fillProfile(List<double> profile, int from, int count, double value) {
    final end = min(profile.length, from + count);
    for (var i = max(0, from); i < end; i++) {
      profile[i] = value;
    }
  }

  /// Simule le passage d'un step sur l'engine [eng] et retourne la valeur
  /// finale d'excitation. Mute [eng] : pour un preview sans effet de bord,
  /// passer un fork via [_forkEngine].
  double _runOnEngine(ExcitationEngine eng, _StepDraft draft) {
    final dur = draft.duration ?? 0;
    if (dur <= 0) return eng.value;
    eng.setCurrentMode(
      mode: draft.mode,
      from: draft.from,
      to: draft.to,
    );
    final beatsPerSecond = (draft.bpm ?? 0) / 60.0;
    var beatAccumulator = 0.0;
    for (var s = 0; s < dur; s++) {
      if (beatsPerSecond > 0) {
        beatAccumulator += beatsPerSecond;
        while (beatAccumulator >= 1.0) {
          eng.onBeat(
            mode: draft.mode,
            to: draft.to,
            from: draft.from,
          );
          beatAccumulator -= 1.0;
        }
      }
      eng.onTickSecond();
    }
    return eng.value;
  }

  /// Choisit le **final** (= action de clôture après la phase de boosts
  /// qui amène l'excitation à sa cible). Distinct du finish (= bursts), le
  /// final est volontairement contemplatif : hand lent, lick / biffle bas,
  /// ou un hold tenu sur une position de plus en plus profonde.
  ///
  /// Palette ordonnée par humiliation requise (hardcodée — la req
  /// "intrinsèque" calculée par `HumiliationScale.requiredFor` est parfois
  /// surcotée volontairement pour réserver l'action à des comptes plus
  /// avancés. La surcote représente la **charge humiliante de la finition**
  /// — sauce sur la langue, le visage, dans la bouche, jusqu'au fond de la
  /// gorge — qui n'est pas dans l'action mécanique elle-même).
  ///
  /// - hand head→mid 40-60 BPM 14s — req 0 (baseline universelle)
  /// - hold tip ~12s — req 5 (sauce sur la langue)
  /// - lick tip→head 60 BPM 16s — req 8 (sauce sur la bouche en lent)
  /// - hold head ~12s — req 8 (sauce sur le gland/bouche)
  /// - hold mid ~12s — req 10 (sauce profonde dans la bouche)
  /// - biffle 40-60 BPM 14s — req 13 (coups + sauce sur le visage)
  /// - hold throat 10-(30+endPts*2)s — req calculée (sauce gorge)
  /// - hold full 10-(60+endPts*3)s — req calculée (au fond)
  ///
  /// La durée des holds throat/full **scale avec le niveau ET la
  /// spécialisation Endurance**. Cap par humilCap : on tronque la durée
  /// pour que la req reste atteignable.
  ///
  /// Algorithme : on collecte toutes les options valides (humilCap +
  /// unlocks), puis on retourne celle de **req maximale**. Plus de
  /// dépendance à l'ordre des `offer` (l'ancienne version "le dernier
  /// écrase" était fragile face à des req hardcodées non-strictement
  /// croissantes).
  _StepDraft _pickFinal({
    required double humilCap,
    required bool includeHand,
    required int maxDepth,
    required int level,
    required double finishMul,
  }) {
    final endPts = _pts(SpecializationBranch.endurance);
    final fastDur = ((14 + endPts) * finishMul).round().clamp(14, 60);
    final shortHoldDur = ((12 + endPts) * finishMul).round().clamp(12, 60);
    // Tuple : (draft, req_humiliation, gate). Le `gate` est l'`UnlockKey?`
    // dédié au final, qui doit être présent dans `_unlockedKeys` pour
    // que le candidat soit retenu. `null` = libre par défaut (cas hand
    // baseline : c'est le fallback universel). Ce gating remplace
    // l'ancien `minLevel` : la progression d'un final est désormais
    // gouvernée par sa milestone d'introduction dédiée (intro_final_*),
    // pas par un seuil de niveau implicite.
    final candidates = <(_StepDraft, double, UnlockKey?)>[];

    // Hand baseline : non humiliant, BPM tiré dans [40, 60] pour rester
    // dans la zone "lent contemplatif". Pas de gate dédiée — c'est le
    // fallback universel quand aucun autre final n'est unlocké.
    final handBpm = 40 + _rng.nextInt(21);
    candidates.add((
      _StepDraft(
        mode: SessionMode.hand,
        bpm: handBpm,
        from: Position.head,
        to: Position.mid,
        duration: fastDur,
      ),
      0.0,
      null,
    ));

    // Hold tip : surcote 5 (faible profondeur mais sauce sur la langue).
    // Gate : intro_final_hold_tip (niveau 2).
    candidates.add((
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: Position.tip,
        to: null,
        duration: shortHoldDur,
      ),
      5.0,
      UnlockKey.finalHoldTip,
    ));

    // Lick tip→head 60 BPM lent : palier intermédiaire (req 8).
    // Gate : intro_final_lick_tip_head (niveau 3).
    candidates.add((
      const _StepDraft(
        mode: SessionMode.lick,
        bpm: 60,
        from: Position.tip,
        to: Position.head,
        duration: 16,
      ),
      8.0,
      UnlockKey.finalLickTipHead,
    ));

    // Hold head : surcote 14 (sauce sur le gland/bouche).
    // Gate : intro_final_hold_head (niveau 4).
    candidates.add((
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: Position.head,
        to: null,
        duration: shortHoldDur,
      ),
      14.0,
      UnlockKey.finalHoldHead,
    ));

    // Hold mid : surcote 10 (sauce profonde dans la bouche).
    // Gate : intro_final_hold_mid (niveau 5, requires hold_mid_short).
    candidates.add((
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: Position.mid,
        to: null,
        duration: shortHoldDur,
      ),
      10.0,
      UnlockKey.finalHoldMid,
    ));

    if (includeHand) {
      // Biffle 40-60 BPM : coups lents + sauce sur le visage.
      // Gate : intro_final_biffle (niveau 5, requires biffle_basic).
      final biffleBpm = 40 + _rng.nextInt(21);
      candidates.add((
        _StepDraft(
          mode: SessionMode.biffle,
          bpm: biffleBpm,
          from: null,
          to: null,
          duration: fastDur,
        ),
        13.0,
        UnlockKey.finalBiffle,
      ));
    }

    if (maxDepth >= Position.throat.index) {
      // Cible : 10s niveau 4, +2s par niveau, +2s par point Endurance.
      // Cap relâché à 40s pour laisser respirer la branche endurance maxée.
      final targetDur = (10 + (level - 4) * 2 + endPts * 2).clamp(10, 40);
      final dur = _trimHoldFinalDuration(
        target: targetDur,
        humilCap: humilCap,
        baseReq: 21.5, // hold throat 10s
        bonusPerSec: 1.5,
        finishMul: finishMul,
        maxDur: 40,
      );
      final req = 8.0 + (dur - 1) * 1.5;
      // Gate : intro_final_hold_throat (niveau 6, requires throat_hold_short).
      candidates.add((
        _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: Position.throat,
          to: null,
          duration: dur,
        ),
        req,
        UnlockKey.finalHoldThroat,
      ));
    }

    if (maxDepth >= Position.full.index) {
      // Cible : 10s niveau 8, +3s par niveau, +3s par point Endurance.
      // Cap relâché à 80s.
      final targetDur = (10 + (level - 8) * 3 + endPts * 3).clamp(10, 80);
      final dur = _trimHoldFinalDuration(
        target: targetDur,
        humilCap: humilCap,
        baseReq: 49.0, // hold full 10s
        bonusPerSec: 3.0,
        finishMul: finishMul,
        maxDur: 80,
      );
      final req = 22.0 + (dur - 1) * 3.0;
      // Gate : intro_final_hold_full (niveau 11, requires full_hold_short).
      candidates.add((
        _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: Position.full,
          to: null,
          duration: dur,
        ),
        req,
        UnlockKey.finalHoldFull,
      ));
    }

    // Filtre humilCap + gate + unlocks composants, prend le plus humiliant
    // valide. Le gate est un `UnlockKey?` dédié au final ; null = libre.
    // `_isUnlocked` couvre les composants du draft (pour cohérence avec le
    // reste du générateur), `_finalUnlocked` couvre la gate du final.
    final valid = <(_StepDraft, double, UnlockKey?)>[];
    for (final c in candidates) {
      if (!_finalUnlocked(c.$3)) continue;
      if (humilCap >= c.$2 && _isUnlocked(c.$1)) valid.add(c);
    }
    if (valid.isEmpty) {
      // Fallback dur : hand head→mid 50 BPM. Toujours unlocked, req=0,
      // garanti même si la palette change ou si humilCap est négatif.
      return _StepDraft(
        mode: SessionMode.hand,
        bpm: 50,
        from: Position.head,
        to: Position.mid,
        duration: fastDur,
      );
    }
    valid.sort((a, b) => a.$2.compareTo(b.$2));
    return valid.last.$1;
  }

  /// Tronque la durée d'un hold final pour qu'elle reste finançable par
  /// `humilCap`. Le `target` peut être visé si l'humil suffit, sinon on
  /// redescend par paliers d'1s jusqu'à 10s minimum (= seuil d'unlock).
  /// Scaled par finishMul (mode encore). `maxDur` borne le cap haut, ouvert
  /// à 80s pour hold full + spé endurance maxée (cf. `_pickFinal`).
  int _trimHoldFinalDuration({
    required int target,
    required double humilCap,
    required double baseReq,
    required double bonusPerSec,
    required double finishMul,
    int maxDur = 60,
  }) {
    final scaledTarget = (target * finishMul).round();
    var dur = scaledTarget.clamp(10, maxDur);
    while (dur > 10) {
      final req = baseReq + (dur - 10) * bonusPerSec;
      if (req <= humilCap) return dur;
      dur--;
    }
    return 10;
  }

  /// Force une variation de BPM si le proposé est dans ±10 du précédent.
  /// Décale de 18–30 BPM dans la direction opposée (clampé [40, 200]).
  /// Fenêtre élargie par rapport à la v1 (±5/15-25) — sinon enchaîner 2
  /// rythmes à 95 et 100 BPM passe pour deux fois la même chose à
  /// l'oreille. La diversité du tempo est l'un des leviers principaux de
  /// variabilité perçue dans la même session.
  int _diversifyBpm(int proposed) {
    final last = _lastBpm;
    if (last == null) return proposed;
    if ((proposed - last).abs() > 10) return proposed;
    final shift = 18 + _rng.nextInt(13);
    final delta = proposed <= last ? -shift : shift;
    return (proposed + delta).clamp(40, 200);
  }

  /// Si [d] est un step long (>40s) en mode rythmique (rhythm/lick/hand),
  /// le découpe en 2 ou 3 sous-segments contigus, chacun avec une variation
  /// de BPM (±10-20) ou de profondeur cible (+/-1 cran). Sert à éviter
  /// qu'une phase d'1 minute sonne comme un loop monotone : chaque sous-
  /// segment se distingue, et la transition entre eux est l'occasion idéale
  /// pour une phrase « plus vite », « plus profond » (cf. C2).
  ///
  /// Les variations restent **égales ou plus douces** que le draft d'origine
  /// (BPM ne dépasse jamais le BPM initial, profondeur ne descend pas
  /// au-delà du `to` initial). Cap de difficulté préservé : pas besoin de
  /// re-passer par `_enforceHumiliationRequired`.
  ///
  /// Retourne `[d]` si pas de split applicable.
  List<_StepDraft> _diversifyLongSegment(_StepDraft d) {
    final dur = d.duration ?? 0;
    if (dur < 40) return [d];
    final mode = d.mode;
    if (mode != SessionMode.rhythm &&
        mode != SessionMode.lick &&
        mode != SessionMode.hand) {
      return [d];
    }
    final parts = dur >= 60 ? 3 : 2;
    final basePart = dur ~/ parts;
    final result = <_StepDraft>[];
    for (var i = 0; i < parts; i++) {
      var bpm = d.bpm;
      var to = d.to;
      if (i > 0) {
        // Variation : alterner entre BPM (down ou up dans la limite) et to.
        if (bpm != null && _rng.nextBool()) {
          // Décalage BPM entre -20 et +20, sans dépasser le BPM initial
          // de plus de 10. On accepte de descendre jusqu'à 30 BPM sous le
          // base pour offrir un vrai contraste.
          final shift = -20 + _rng.nextInt(31); // [-20, 10]
          bpm = (d.bpm! + shift).clamp(40, d.bpm! + 10);
        } else if (to != null &&
            d.from != null &&
            to.index > d.from!.index + 1) {
          // Décale `to` d'un cran vers from. Condition stricte
          // `to.index > from.index + 1` : il faut au moins 2 crans d'écart
          // pour pouvoir descendre to sans collision. À head→mid (écart 1),
          // on n'a pas la marge → on garde to inchangé pour ce sous-segment
          // (la variation se fera via BPM uniquement).
          to = Position.values[to.index - 1];
        }
      }
      final partDur = i == parts - 1 ? dur - i * basePart : basePart;
      result.add(_StepDraft(
        mode: d.mode,
        bpm: bpm,
        from: d.from,
        to: to,
        duration: partDur,
      ));
    }
    return result;
  }

  /// Applique `_diversifyBpm` au draft si pertinent (modes avec BPM,
  /// hors hold/beg/breath/freestyle qui n'en ont pas), et met à jour
  /// `_lastBpm`. Retourne le draft (potentiellement modifié).
  _StepDraft _applyBpmDiversity(_StepDraft d) {
    final bpm = d.bpm;
    if (bpm == null) return d;
    final newBpm = _diversifyBpm(bpm);
    _lastBpm = newBpm;
    if (newBpm == bpm) return d;
    return _StepDraft(
      mode: d.mode,
      bpm: newBpm,
      from: d.from,
      to: d.to,
      duration: d.duration,
    );
  }

  /// Force une légère variation de la cible `to` (ou de `from` si `to`
  /// est null) si le draft a exactement la même amplitude que le step
  /// précédent. Sert pour rhythm/lick/hand/biffle : empêche d'enchaîner
  /// deux head→mid identiques. Décale d'un cran vers le haut ou le bas
  /// selon ce qui est possible (en respectant `_maxDepthIndex`).
  _StepDraft _diversifyAmplitude(_StepDraft d) {
    if (d.mode != SessionMode.rhythm &&
        d.mode != SessionMode.lick &&
        d.mode != SessionMode.hand &&
        d.mode != SessionMode.biffle) {
      return d;
    }
    final lastFrom = _lastFrom;
    final lastTo = _lastTo;
    if (lastFrom == null || lastTo == null) return d;
    if (d.from != lastFrom || d.to != lastTo) return d;
    // Même amplitude que le step précédent : on décale `to` d'un cran.
    final toIdx = d.to?.index;
    if (toIdx == null) return d;
    final ceil = d.mode == SessionMode.hand
        ? min(3, _maxDepthIndex)
        : _maxDepthIndex;
    final fromIdx = d.from?.index ?? 0;
    final canUp = toIdx + 1 <= ceil;
    final canDown = toIdx - 1 > fromIdx;
    final int newToIdx;
    if (canUp && canDown) {
      newToIdx = _rng.nextBool() ? toIdx + 1 : toIdx - 1;
    } else if (canUp) {
      newToIdx = toIdx + 1;
    } else if (canDown) {
      newToIdx = toIdx - 1;
    } else {
      // Impossible de varier `to` : tente sur `from`.
      if (fromIdx > 0 && fromIdx + 1 < toIdx) {
        return _StepDraft(
          mode: d.mode,
          bpm: d.bpm,
          from: Position.values[fromIdx - 1],
          to: d.to,
          duration: d.duration,
        );
      }
      return d;
    }
    return _StepDraft(
      mode: d.mode,
      bpm: d.bpm,
      from: d.from,
      to: Position.values[newToIdx],
      duration: d.duration,
    );
  }

  /// Convertit un [_StepDraft] interne en [SessionStep] sérialisable.
  /// Pour les modes hold/beg, swap `from` (position cible interne au draft)
  /// vers `to` côté SessionStep — sémantique « on tient jusqu'à cette
  /// position ». Les autres modes (rhythm/lick/hand/biffle) gardent
  /// from/to inchangés (alternance from↔to).
  SessionStep _draftToStep(_StepDraft draft,
      {required int time, String text = ''}) {
    final isHoldLike =
        draft.mode == SessionMode.hold || draft.mode == SessionMode.beg;
    return SessionStep(
      time: time,
      text: text,
      mode: draft.mode,
      bpm: draft.bpm,
      from: isHoldLike ? null : draft.from,
      to: isHoldLike ? (draft.to ?? draft.from) : draft.to,
      duration: draft.duration,
    );
  }

  /// Crée une copie de [src] partageant son cap et sa valeur courante.
  /// Sert au preview (« et si on jouait ce draft maintenant ? ») sans
  /// muter l'engine principal.
  ExcitationEngine _forkEngine(ExcitationEngine src) {
    return ExcitationEngine()
      ..setMax(src.maxValue)
      ..seed(src.value);
  }

  /// Catégorise le draft retenu par `_pickFinal` pour piocher la bonne
  /// variante de `finale_chime` côté `BeepEngine`. Mapping :
  /// - hand any, hold tip → easy
  /// - hold head, hold mid, biffle → medium
  /// - hold throat → hard
  /// - hold full → extreme
  /// Cas non couverts (ne devraient pas survenir vu les options de
  /// `_pickFinal`) → `medium` par défaut.
  FinalCategory _categorizeFinal(_StepDraft d) {
    if (d.mode == SessionMode.hand) return FinalCategory.easy;
    if (d.mode == SessionMode.biffle) return FinalCategory.medium;
    if (d.mode == SessionMode.hold) {
      switch (d.from) {
        case Position.tip:
          return FinalCategory.easy;
        case Position.head:
        case Position.mid:
          return FinalCategory.medium;
        case Position.throat:
          return FinalCategory.hard;
        case Position.full:
          return FinalCategory.extreme;
        case null:
          return FinalCategory.medium;
      }
    }
    return FinalCategory.medium;
  }

  /// Retourne l'`UnlockKey` requise pour jouer [draft], `null` si l'action
  /// est libre par défaut. Le mapping se base sur les milestones existantes
  /// (cf. `assets/career/milestones.json`).
  UnlockKey? _unlockKeyFor(_StepDraft d) {
    switch (d.mode) {
      case SessionMode.hold:
        final from = d.from;
        if (from == null || from == Position.tip) return UnlockKey.holdTip;
        if (from == Position.head) return UnlockKey.holdHead;
        if (from == Position.mid) return UnlockKey.holdMidShort;
        final dur = d.duration ?? 0;
        if (from == Position.throat) {
          return dur > 10 ? UnlockKey.throatHoldLong : UnlockKey.throatHoldShort;
        }
        if (from == Position.full) {
          return dur > 10 ? UnlockKey.fullHoldLong : UnlockKey.fullHoldShort;
        }
        return null;
      case SessionMode.rhythm:
        if (d.to == Position.full) return UnlockKey.fullPulse;
        if (d.to == Position.throat) return UnlockKey.throatPulse;
        if (d.to == Position.mid) return UnlockKey.rhythmMidBasic;
        if (d.to == Position.head && d.from == Position.tip) {
          return UnlockKey.rhythmTipHead;
        }
        if ((d.bpm ?? 0) >= 160) return UnlockKey.rhythmExtreme;
        return null;
      case SessionMode.biffle:
        return (d.bpm ?? 0) > 100 ? UnlockKey.biffleFast : UnlockKey.biffleBasic;
      case SessionMode.freestyle:
        return UnlockKey.freestyle;
      case SessionMode.beg:
        if (d.from == null) return UnlockKey.begLibre;
        if (d.from == Position.full) return UnlockKey.begFull;
        // Toute supplique avec position tenue (head/mid/throat) reste
        // gated par begThroat (palier niveau 14). Avant ça, seule la
        // supplique libre (from=null) doit apparaître. Évite que le
        // générateur produise des beg head/mid après l'unlock de
        // begLibre alors qu'aucun milestone ne les a explicitement
        // introduits.
        return UnlockKey.begThroat;
      case SessionMode.lick:
        // Lick X→full nécessite la milestone niveau 2. Sinon, lick from=tip
        // (toutes amplitudes ≤ throat) est couvert par la base intro.
        if (d.to == Position.full) return UnlockKey.lickFull;
        if (d.from == Position.tip) return UnlockKey.lickTipBasic;
        return null;
      case SessionMode.hand:
        return UnlockKey.handBasic;
      case SessionMode.breath:
        return null;
    }
  }

  /// Vrai si [d] n'est pas gaté par une `UnlockKey` ou si la clé requise
  /// est dans `_unlockedKeys`.
  ///
  /// **Prérequis transverse `begLibre`** : « beg libre » signifie « bouche
  /// libre, supplique facile ». Toutes les autres formes de beg (avec
  /// `from` = position tenue) sont mécaniquement plus dures (la bouche
  /// reste sur la position pendant la supplique). On les bloque donc tant
  /// que begLibre n'est pas acquise — elle reste la fondation pédagogique.
  ///
  /// Les call sites du générateur sont tenus de passer un `unlockedKeys`
  /// non vide — un set vide bloquerait quasi tous les modes. Pour un test
  /// qui veut désactiver le gating, passer un set contenant
  /// `UnlockKey.values.toSet()`.
  bool _isUnlocked(_StepDraft d) {
    if (d.mode == SessionMode.beg &&
        !_unlockedKeys.contains(UnlockKey.begLibre)) {
      return false;
    }
    final key = _unlockKeyFor(d);
    return key == null || _unlockedKeys.contains(key);
  }

  /// Vrai si la gate `UnlockKey?` d'un final candidat est accessible :
  /// soit `null` (final libre), soit présente dans `_unlockedKeys`.
  /// Distinct de `_isUnlocked` parce qu'un final est gaté par sa propre
  /// clé `finalXxx` dédiée — pas par la clé du composant. Ex : un final
  /// `hold mid` est gaté par `finalHoldMid` (sa milestone d'introduction
  /// dédiée), pas par `holdMidShort` qui couvre l'usage en corps de séance.
  bool _finalUnlocked(UnlockKey? key) =>
      key == null || _unlockedKeys.contains(key);

  /// Si l'humiliation requise par [draft] dépasse [available], OU si la
  /// clé d'unlock requise n'est pas acquittée, dégrade progressivement
  /// (baisse profondeur, BPM, durée de hold, change de mode pour quelque
  /// chose de plus doux) jusqu'à acceptation. Fallback ultime sur un
  /// lick tip→head.
  _StepDraft _enforceHumiliationRequired(_StepDraft draft, double available) {
    var current = draft;
    for (var i = 0; i < 12; i++) {
      final r = HumiliationScale.requiredFor(
        mode: current.mode,
        from: current.from,
        to: current.to,
        bpm: current.bpm,
        duration: current.duration,
      );
      if (r <= available && _isUnlocked(current)) return current;
      current = _stepDownOne(current);
    }
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: 60,
      from: Position.tip,
      to: Position.head,
      duration: draft.duration ?? 12,
    );
  }

  /// Stratégie de dégradation : raccourcir un hold long, baisser `to`
  /// d'un cran, sinon `from`, sinon ramener un BPM rapide à 80, sinon
  /// transformer en mode plus doux.
  ///
  /// **Garde-fou from < to** : la descente de `to` saute l'étape si elle
  /// ferait collision avec `from` (head→mid → head→head interdit). Dans
  /// ce cas on passe directement à descendre `from`.
  _StepDraft _stepDownOne(_StepDraft d) {
    // Hold throat/full long → raccourcir d'abord (la durée pèse beaucoup
    // sur l'humiliation requise, la position reste contractuelle).
    if (d.mode == SessionMode.hold &&
        (d.from == Position.throat || d.from == Position.full) &&
        (d.duration ?? 0) > 5) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: d.from,
        to: d.to,
        duration: max(2, (d.duration ?? 0) ~/ 2),
      );
    }
    if (d.to != null && d.to!.index > Position.head.index) {
      final newToIdx = d.to!.index - 1;
      // Skip si la descente collisionne avec `from` (cas typique :
      // head→mid → head→head interdit). On passe à descendre `from`.
      final fromIdx = d.from?.index ?? -1;
      if (newToIdx > fromIdx) {
        return _StepDraft(
          mode: d.mode,
          bpm: d.bpm,
          from: d.from,
          to: Position.values[newToIdx],
          duration: d.duration,
        );
      }
    }
    if (d.from != null && d.from!.index > Position.tip.index) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: Position.values[d.from!.index - 1],
        to: d.to,
        duration: d.duration,
      );
    }
    if ((d.mode == SessionMode.rhythm || d.mode == SessionMode.biffle) &&
        (d.bpm ?? 0) > 80) {
      return _StepDraft(
        mode: d.mode,
        bpm: 80,
        from: d.from,
        to: d.to,
        duration: d.duration,
      );
    }
    if (d.mode == SessionMode.biffle) {
      return _StepDraft(
        mode: SessionMode.lick,
        bpm: d.bpm ?? 60,
        from: d.from ?? Position.tip,
        to: d.to ?? Position.head,
        duration: d.duration,
      );
    }
    if (d.mode == SessionMode.beg && d.from != null) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: null,
        to: d.to,
        duration: d.duration,
      );
    }
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: 60,
      from: Position.tip,
      to: Position.head,
      duration: d.duration ?? 12,
    );
  }

  /// Retire `_lastMode` des candidats si une alternative existe — empêche
  /// qu'un même mode (typiquement breath ou beg) se déclenche deux steps
  /// d'affilé. Si la liste tombe à 0 (cas pathologique : un seul candidat
  /// déjà égal au précédent), on revient à la liste d'origine.
  List<SessionMode> _filterRepeated(List<SessionMode> candidates) {
    if (_lastMode == null || candidates.length <= 1) return candidates;
    final filtered = candidates.where((m) => m != _lastMode).toList();
    if (filtered.isEmpty) return candidates;
    return filtered;
  }

  /// Tire une phrase pour [mode]/[tier] en évitant la même qu'au step
  /// précédent (`_lastText`). Quelques essais suffisent : si la banque ne
  /// contient qu'une seule entrée pour ce couple, on accepte la répétition.
  ///
  /// **Auto-bump par obédiance** : plus l'obédiance lifetime est haute,
  /// plus la coach pioche dans les tiers durs. Tu obéis bien → on durcit
  /// le ton. Le bump n'affecte pas les tiers `boost` et `finale` (qui ont
  /// leur dramaturgie propre, indépendante de l'obédiance).
  /// - obed ≥ 30 : `soft` → `medium` à 30 %
  /// - obed ≥ 80 : `soft` → `medium` à 70 % ; `medium` → `hard` à 30 %
  /// - obed ≥ 150 : `soft` → `medium` à 90 % ; `medium` → `hard` à 60 %
  ///
  /// Si le tier ciblé n'a pas de phrase pour ce mode, le `pickFor` retombe
  /// transparentement sur le tier d'origine — pas de risque de chaîne vide.
  String _pickPhrase(PhraseBank bank, SessionMode mode, String tier) {
    final effectiveTier = _bumpTierByObedience(tier);
    for (var i = 0; i < 4; i++) {
      final phrase = bank.pickFor(mode, effectiveTier, _rng);
      if (phrase.isEmpty || phrase != _lastText) return phrase;
    }
    return bank.pickFor(mode, effectiveTier, _rng);
  }

  /// Bump conditionnel d'un tier de phrase selon `_obedience`. Cf. doc
  /// de `_pickPhrase`. Ne touche pas aux tiers `boost`/`finale`.
  String _bumpTierByObedience(String tier) {
    if (tier == 'boost' || tier == 'finale') return tier;
    final obed = _obedience;
    final roll = _rng.nextDouble();
    if (tier == 'soft') {
      double pSoftToMedium;
      if (obed >= 150) {
        pSoftToMedium = 0.90;
      } else if (obed >= 80) {
        pSoftToMedium = 0.70;
      } else if (obed >= 30) {
        pSoftToMedium = 0.30;
      } else {
        return tier;
      }
      return roll < pSoftToMedium ? 'medium' : tier;
    }
    if (tier == 'medium') {
      double pMediumToHard;
      if (obed >= 150) {
        pMediumToHard = 0.60;
      } else if (obed >= 80) {
        pMediumToHard = 0.30;
      } else {
        return tier;
      }
      return roll < pMediumToHard ? 'hard' : tier;
    }
    return tier;
  }
}

/// Brouillon de step interne au générateur, avant matérialisation en
/// `SessionStep` (il manque `time` et `text` qui sont décidés au push).
class _StepDraft {
  final SessionMode mode;
  final int? bpm;
  final Position? from;
  final Position? to;
  final int? duration;

  /// Action enchaînée optionnelle. Émise comme step indépendant juste
  /// après le step parent par le générateur. Sert aux beg « guidés »
  /// (« dis X et continue à me sucer »). Le combo n'est jouable que si
  /// les deux composants passent `_isUnlocked` ET `humilCap`.
  final _StepDraft? chainNext;

  const _StepDraft({
    required this.mode,
    required this.bpm,
    required this.from,
    required this.to,
    required this.duration,
    this.chainNext,
  });

  SessionStep copyWithTime(int t) => SessionStep(
        time: t,
        mode: mode,
        bpm: bpm,
        from: from,
        to: to,
        duration: duration,
      );
}
