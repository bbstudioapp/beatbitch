import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/final_category.dart';
import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/humiliation_engine.dart';
import '../../services/saliva_engine.dart';
import '../models/career_level.dart';
import '../models/level_milestone.dart';
import '../models/phrase_bank.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';

/// Résultat d'une génération : la session figée à passer au controller +
/// le profil d'endurance projeté (utile à l'overlay debug `StaminaBar`).
class CareerGenerationResult {
  final Session session;
  final List<double> staminaProfile;

  const CareerGenerationResult({
    required this.session,
    required this.staminaProfile,
  });
}

/// Génère une session procédurale en fonction du niveau choisi et de la
/// durée demandée. Voir `(plan local)`
/// pour la spec complète de l'algorithme.
class CareerSessionGenerator {
  static const int _finisherBudgetSeconds = 12;
  static const double _staminaMax = 100.0;

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

  /// Niveau global du joueur passé à `generate`. Utilisé pour gater les
  /// branches de tirage qui n'ont de sens qu'à un certain niveau (ex :
  /// post-final humiliant biaisé par spé sloppy/obeissance, réservé aux
  /// niveaux avancés où la dramaturgie peut sortir du cadre doux).
  int _level = 1;

  /// `time` (en secondes) à partir duquel une **mini-vague** peut être
  /// insérée dans la boucle main. Cf. `_shouldEmitMiniWave` pour les
  /// conditions cumulatives. Initialisée à 5-6 min dans `generate`. Une
  /// vague émise repousse à `time + 6-7 min`. Vise à casser la diagonale
  /// d'intensité unique du début au finish sur les sessions longues —
  /// 1 à 3 mini-vagues sur une session de 25-45 min.
  int _nextMiniWaveAt = 0;

  /// `time` du dernier ordre de déglutition forcé (`swallow_order`).
  /// Sert au cooldown 90 s entre deux ordres : sans ça, une joueuse spé
  /// sloppy avec lick à fond sature en permanence et le coach radoterait
  /// « avale » toutes les 30 s. Initialisée à -120 dans `generate` pour
  /// laisser un premier ordre arriver dès la fin de la rampe initiale
  /// si la salive monte vite.
  int _lastSwallowOrderAt = -120;

  /// Dernier mode poussé dans la séance, pour éviter qu'un même mode
  /// (breath, beg, …) se déclenche deux steps d'affilé. Reset dans `generate`.
  SessionMode? _lastMode;

  /// Durée cumulée (en secondes) des steps `rhythm` poussés consécutivement.
  /// Tout step d'un autre mode (breath compris) reset à 0. Sert au cap
  /// « rythme soutenu » : tant que `rhythmHeadMidSustained` n'est pas
  /// débloqué, la chaîne rythme consécutive est plafonnée à 60 s par
  /// `_capRhythmConsecutive` / `_canChainRhythm` dans `_mapDifficultyToStep`.
  /// La milestone `intro_rhythm_sustained` enseigne et débloque ce
  /// dépassement.
  int _consecutiveRhythmSeconds = 0;

  /// Type effectif du dernier step poussé (= cluster sémantique :
  /// bouche / langue / libre-main). Sert à forcer une continuité par
  /// type sur plusieurs steps consécutifs : la séance est censée se
  /// concentrer sur la bouche, les autres types sont des intros / des
  /// respirations entre deux phases bouche.
  ///
  /// Les steps `transit` (breath / freestyle) sont des parenthèses
  /// transparentes : ils ne touchent ni `_lastType` ni `_stepsInLastType`,
  /// pour qu'un breath de récup au milieu d'une série bouche n'efface pas
  /// la continuité.
  _StepType? _lastType;
  int _stepsInLastType = 0;

  /// Nombre de steps **consécutifs** posés en dehors du type `bouche`.
  /// Reset à 0 dès qu'un step bouche est poussé. Sert à imposer un cap
  /// dur sur la durée d'une excursion hors bouche : passé un certain
  /// nombre de steps cumulés (peu importe que ce soit langue ou
  /// libre-main), on force le retour à bouche.
  ///
  /// Distinct de `_stepsInLastType` qui reset à chaque changement de
  /// type — ce compteur-là tient sur tout l'écart bouche → bouche.
  int _stepsOutsideBouche = 0;

  /// Dernière phrase TTS poussée, pour éviter de répéter la même phrase
  /// scriptée d'un step à l'autre. Reset dans `generate`.
  String _lastText = '';

  /// Dernier BPM appliqué à un step (rhythm/lick/biffle/hand). Sert à
  /// forcer la variété : un nouveau BPM trop proche du précédent est
  /// décalé de 18–30 BPM par `_diversifyBpm`.
  int? _lastBpm;

  /// Dernier couple (from, to) appliqué pour les modes à amplitude
  /// (rhythm/lick/hand/biffle). Sert à forcer une variation de profondeur
  /// quand le step suivant tombe sur exactement la même paire.
  Position? _lastFrom;
  Position? _lastTo;

  /// Buffer roulant des 3 derniers steps rythmés émis (mode + from + to +
  /// bpm). Sert à détecter un **pattern plat** sur une fenêtre élargie :
  /// même mode + même profondeur cible + variance BPM < 10 sur 3 steps
  /// consécutifs = monotone, on force une diversification au step suivant.
  /// Sans cette fenêtre, `_diversifyAmplitude` ne regardait que le step
  /// strictement précédent et laissait passer des séries du genre
  /// `head→mid 90 / head→mid 92 / head→mid 88` (BPMs proches mais différents
  /// donc check classique satisfait, alors que l'oreille perçoit un plat).
  /// Les steps transit (breath / freestyle) sont **ignorés** : un breath
  /// de récup au milieu d'une série rythmée ne casse pas la perception du
  /// pattern, on veut qu'il continue à compter.
  final List<_RecentEmit> _recentEmits = [];

  /// Simulateur de salive utilisé pendant la génération. Mime le
  /// comportement du `SalivaEngine` runtime : production par mode/position,
  /// auto-déglutition au-dessus de 75. Sert à projeter la lubrification
  /// au moment du draft d'un step throat/full (cf. Phase 4). En V1 le
  /// SwallowMode est assumé `allowed` (le générateur n'émet pas encore de
  /// steps forbidden auto-générés ; les milestones les portent en dur).
  late SalivaEngine _salivaSim;
  int _salivaSimSecond = 0;

  /// Set des `UnlockKey` débloquées pour la génération en cours. Une action
  /// dont la clé n'est pas dedans est rejetée par `_isUnlocked` et dégradée
  /// par `_stepDownOne`. Vide = aucune clé requise (mode héritage).
  Set<UnlockKey> _unlockedKeys = const {};

  /// Multiplicateur de poids par mode, fourni par le coach actif. Combiné
  /// **multiplicativement** par-dessus la pondération spé dans `_modeWeight`.
  /// Mode absent = 1.0 (neutre). Cf. CoachMeta.modeWeights.
  Map<SessionMode, double> _coachModeWeights = const {};

  /// Score career d'humiliation (persisté lifetime) au démarrage de la
  /// session. Sert au tirage spécifique de certains modes (lick :
  /// amplitudes complètes seulement à partir de 2).
  double _humiliationCareer = 0.0;

  /// Score session d'humiliation (intra-session) au moment de la
  /// génération. Vaut 0 pour une session normale, > 0 sur encore
  /// enchaîné ou régénération en cours de séance (Supplier / retry
  /// milestone). Le générateur projette une rampe par-dessus ce score
  /// basée sur le tick automatique (cf. [_humilCapAt]).
  double _humiliationSession = 0.0;

  /// Score d'obédiance au démarrage de la session (cf. param `obedience`
  /// de `generate`). Pilote le tier de phrase auto-bumpé dans `_pickPhrase`
  /// (plus c'est élevé, plus la coach pioche dans `medium`/`hard`) et le
  /// `recoveryThreshold` (plus c'est élevé, plus on respecte l'endurance).
  double _obedience = 0.0;

  CareerSessionGenerator({int? seed})
      : _rng = seed != null ? Random(seed) : Random();

  /// Cap effectif d'humiliation projeté au temps `seconds` depuis le
  /// début de la session générée. Modèle 2 thermomètres :
  ///
  ///   `cap(t) = career + min(session + tickRate × t/60, sessionCap)`
  ///
  /// avec `tickRate = 1 × accel(obed)` (cf. `HumiliationEngine.onTickSecond`).
  /// La projection ne tient pas compte des bumps évènementiels (punition
  /// complétée, hold profond complété…) — c'est volontairement
  /// conservateur, le runtime peut accepter des actions un poil plus
  /// dures que ce que la rampe seule prédit.
  double _humilCapAt(int seconds) {
    final accel = (1.0 + _obedience / 100.0).clamp(1.0, 3.0);
    final tickRate = HumiliationEngine.bumpPerInterval * accel; // par minute
    final added = tickRate * seconds / 60.0;
    final session = (_humiliationSession + added)
        .clamp(0.0, HumiliationEngine.sessionCap);
    return _humiliationCareer + session;
  }

  CareerGenerationResult generate({
    required int level,
    required PhraseBank bank,
    int? durationSeconds,
    bool includeHand = true,
    int encoreChainIndex = 0,
    String? openingPhrase,
    bool quickie = false,
    SpecializationAllocation? specialization,
    bool intense = false,
    double obedience = 100.0,
    double humiliationCareer = 0.0,
    double humiliationSession = 0.0,
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
    // Première mini-vague entre 4 et 5 minutes : laisse l'intro et le
    // début de chauffe se dérouler sans rupture, puis le générateur peut
    // poser un mini-finish pour casser la monotonie. Cadence resserrée
    // (vs 5-6 min initial) pour viser 3 vagues sur une session 19 min.
    _nextMiniWaveAt = 240 + _rng.nextInt(61);
    _lastSwallowOrderAt = -120;
    _lastMode = null;
    _lastText = '';
    _lastBpm = null;
    _lastFrom = null;
    _lastTo = null;
    _lastType = null;
    _stepsInLastType = 0;
    _stepsOutsideBouche = 0;
    _consecutiveRhythmSeconds = 0;
    _recentEmits.clear();
    _unlockedKeys = unlockedKeys;
    _coachModeWeights = coachModeWeights;
    _humiliationCareer = humiliationCareer;
    _humiliationSession = humiliationSession;
    _obedience = obedience;
    // Mode "Session bâclée" : 6 min par défaut, intense tout du long. Floor
    // d'intensité appliqué au tirage de difficulté + on saute l'intro douce
    // et la pré-finition. Une durée explicite reste prioritaire (cas de la
    // session surprise qui demande 60-240s avec dramaturgie quickie).
    //
    // Mode "intense" : régénération post-Supplier. On garde la durée
    // demandée mais on supprime le soft intro et on applique un plancher
    // de difficulté solide pour que la suite ressente vraiment le level up.
    final effectiveDuration =
        durationSeconds ?? (quickie ? 6 * 60 : cfg.durationSeconds);
    final intensityFloor =
        quickie ? 0.65 : (intense ? 0.55 : 0.0);
    // Nombre de boosts en phase finish : table par niveau + bonus encore
    // (chaîne encore = +2 boosts par cran, sans plafond explicite côté
    // générateur). Le caller borne le nombre d'encores enchaînés via le
    // gating `_canEncore`.
    final boostsCount = cfg.boostsCount + max(0, encoreChainIndex) * 2;
    _salivaSim = SalivaEngine()..reset();
    _salivaSimSecond = 0;
    final steps = <SessionStep>[];
    final profile = List<double>.filled(effectiveDuration + 60, _staminaMax);

    var time = 0;
    var stamina = _staminaMax;

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
          swallowMode: mStep.swallowMode,
        ));
        // Simulation stamina/salive pour chaque step de la séquence, pour
        // que la projection reste cohérente.
        final mDraft = _stepToDraft(mStep, SessionMode.rhythm);
        final staminaBefore = stamina;
        stamina = _applyStaminaChange(
            stamina, mDraft, time / effectiveDuration, cfg);
        _advanceSalivaSim(mDraft);
        _fillProfile(profile, time + mStep.time, mStep.duration ?? 0, stamina,
            valueStart: staminaBefore);
        // Tracking de continuité par type — chaque step de la séquence
        // compte (la séquence peut elle-même alterner bouche/transit).
        if (mStep.mode != null && !mStep.isTextOnly) {
          _trackPushedStep(mStep.mode!, mStep.to,
              from: mStep.from, bpm: mStep.bpm, duration: mStep.duration);
        }
      }
      // Met à jour le « dernier mode/texte » avec le dernier step de la
      // milestone — sert au filtrage anti-répétition de la suite générée.
      final lastStep = milestone.sequence.last;
      _lastMode = lastStep.mode ?? _lastMode;
      _lastText = lastStep.text;
      time += milestone.durationSeconds;
      milestoneDurationSeconds = milestone.durationSeconds;
      milestoneInserted = true;
      // Réutilisation post-acquittement : les unlocks de la milestone
      // deviennent disponibles pour les steps générés APRÈS la séquence
      // (corps restant, pré-finisher, boosts, final). On suppose succès au
      // runtime — sur fail la session est replanifiée par le contrôleur, ce
      // qui régénère un set d'unlocks cohérent.
      if (milestone.unlocks.isNotEmpty) {
        _unlockedKeys = {..._unlockedKeys, ...milestone.unlocks};
      }
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
      _trackPushedStep(first.mode, first.to,
          from: first.from, bpm: first.bpm, duration: first.duration);
      final staminaBefore = stamina;
      stamina = _applyStaminaChange(stamina, first, 0.0, cfg);
      _fillProfile(profile, 0, first.duration ?? 1, stamina,
          valueStart: staminaBefore);
      _advanceSalivaSim(first);
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
      // Mini-vague : 2-3 steps enchaînés à BPM montant qui cassent la
      // diagonale d'intensité unique du début au finish. Inséré toutes
      // les ~4-5 minutes sur les sessions longues (≥ 12 min) à partir du
      // niveau 5. Cf. `_shouldEmitMiniWave`.
      if (_shouldEmitMiniWave(time, effectiveDuration, stamina, genUntil)) {
        final progressForWave = time / effectiveDuration;
        final humilCapForWave = _humilCapAt(time);
        final waveDrafts = _buildMiniWave(humilCapForWave);
        for (final wd in waveDrafts) {
          final waveText = _pickPhrase(bank, wd.mode, 'hard');
          steps.add(_draftToStep(wd, time: time, text: waveText));
          final staminaBefore = stamina;
          stamina = _applyStaminaChange(stamina, wd, progressForWave, cfg);
          _advanceSalivaSim(wd);
          _fillProfile(profile, time, wd.duration!, stamina,
              valueStart: staminaBefore);
          _lastMode = wd.mode;
          _lastText = waveText;
          _lastFrom = wd.from;
          _lastTo = wd.to;
          _lastBpm = wd.bpm ?? _lastBpm;
          _trackPushedStep(wd.mode, wd.to,
              from: wd.from, bpm: wd.bpm, duration: wd.duration);
          time += wd.duration!;
        }
        // Pause longue post-vague : breath dédié dimensionné pour viser
        // ~95 stamina, sortie volontaire du cap [4,12] du sas breath
        // standard — la vague est un mini-finish, on s'autorise une vraie
        // respiration scénarisée derrière pour repartir de plein. Borne
        // [12, 20] s : 12 = baseline minimale même si stamina déjà haute,
        // 20 = plafond pour ne pas casser le rythme dramaturgique de la
        // session. À niveau 9 milieu de séance (regen ≈ 1.6, ≈ 4.5/s),
        // 15-20 s rendent ~70-90 stamina.
        final postWaveProgress = time / effectiveDuration;
        final postWaveBreath = _buildPostWaveBreath(
            stamina, postWaveProgress, cfg, genUntil - time);
        if (postWaveBreath != null) {
          final breathText = _pickPhrase(bank, SessionMode.breath, 'soft');
          steps.add(_draftToStep(postWaveBreath, time: time, text: breathText));
          final staminaBefore = stamina;
          stamina =
              _applyStaminaChange(stamina, postWaveBreath, postWaveProgress, cfg);
          _advanceSalivaSim(postWaveBreath);
          _fillProfile(profile, time, postWaveBreath.duration!, stamina,
              valueStart: staminaBefore);
          _lastMode = SessionMode.breath;
          _lastText = breathText;
          _trackPushedStep(SessionMode.breath, null,
              duration: postWaveBreath.duration);
          time += postWaveBreath.duration!;
        }
        // Replanification : 4-5 minutes après la fin de la vague émise.
        // La séance enchaîne ensuite sur du tirage classique — la stamina
        // restaurée par la pause longue permet d'enchaîner sereinement
        // jusqu'à la prochaine vague.
        _nextMiniWaveAt = time + 240 + _rng.nextInt(61);
        continue;
      }
      // Ordre de déglutition forcé : quand la simulation salive sature,
      // on transforme la jauge silencieuse en mécanique gameplay — un
      // beg libre court « avale tout » avec phrase dédiée. Cf.
      // `_maybeBuildSwallowOrder` pour les conditions.
      final swallowDraft = _maybeBuildSwallowOrder(time, genUntil);
      if (swallowDraft != null) {
        final swallowText =
            bank.pickSwallowOrder(_rng) ?? _pickPhrase(bank, SessionMode.beg, 'hard');
        steps.add(_draftToStep(swallowDraft, time: time, text: swallowText));
        final staminaBefore = stamina;
        stamina = _applyStaminaChange(
            stamina, swallowDraft, time / effectiveDuration, cfg);
        // Conséquence simulée de l'ordre : la sim retombe à 0, comme si
        // la joueuse obéissait. En runtime le SessionController fera de
        // même via `SalivaEngine.forceSwallow()`.
        _salivaSim.forceSwallow();
        _fillProfile(profile, time, swallowDraft.duration!, stamina,
            valueStart: staminaBefore);
        _lastMode = SessionMode.beg;
        _lastText = swallowText;
        _trackPushedStep(SessionMode.beg, null,
            duration: swallowDraft.duration);
        time += swallowDraft.duration!;
        _lastSwallowOrderAt = time;
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

      // Filtre humiliation requise : on garde uniquement ce que le cap
      // effectif (career + session projeté à `time`) permet. La rampe
      // session (+1/min en clean, ×3 max avec obed, capée à sessionCap)
      // est intégrée par `_humilCapAt`.
      final humilCap = _humilCapAt(time);
      draft = _enforceHumiliationRequired(draft, humilCap);

      // Variété BPM : évite d'enchaîner des steps au même tempo.
      draft = _applyBpmDiversity(draft);
      // Variété amplitude : évite d'enchaîner deux fois exactement la
      // même paire from/to dans le même mode.
      draft = _diversifyAmplitude(draft);
      // Rampe BPM intra-step : pour les steps longs (≥ 30 s) sur amplitude
      // moyenne (≤ mid), pose `bpmEnd` distinct pour raconter une
      // montée / descente sur la durée. Skip throat/full pour ne pas
      // violer le cap pulses (cf. `_capRhythmDurationByPulses`).
      draft = _maybeApplyBpmRamp(draft, progress);

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
          final staminaBefore = stamina;
          stamina = _applyStaminaChange(stamina, breathDraft, progress, cfg);
          _advanceSalivaSim(breathDraft);
          _fillProfile(profile, time, breathDraft.duration!, stamina,
              valueStart: staminaBefore);
          time += breathDraft.duration!;
          _lastMode = SessionMode.breath;
          _lastText = breathText;
          // breath = transit → ne touche pas _lastType (parenthèse
          // transparente). On l'appelle quand même pour cohérence si la
          // règle évoluait.
          _trackPushedStep(SessionMode.breath, null,
              duration: breathDraft.duration);
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
        final staminaBefore = stamina;
        stamina = _applyStaminaChange(stamina, partDraft, progress, cfg);
        _advanceSalivaSim(partDraft);
        steps.add(_draftToStep(partDraft, time: time, text: partText));
        _lastMode = partDraft.mode;
        _lastText = partText;
        _lastFrom = partDraft.from;
        _lastTo = partDraft.to;
        _trackPushedStep(partDraft.mode, partDraft.to,
            from: partDraft.from, bpm: partDraft.bpm,
            duration: partDraft.duration);
        _fillProfile(profile, time, partDraft.duration!, stamina,
            valueStart: staminaBefore);
        time += partDraft.duration!;
      }

      // **Fake breath** (à partir du niveau 12) : après un step intense
      // (rythme to=throat/full ou hold throat/full), on a une chance
      // d'insérer un breath très court (2-3 s) qui mime une vraie pause
      // mais qui ne suffit pas à reconstituer la stamina. La step suivante
      // tirée par la boucle continuera sur sa lancée — la joueuse croit
      // souffler, en fait elle reprend direct. Effet de surprise validé
      // pour les niveaux avancés où la dramaturgie peut se permettre
      // d'être trompeuse. Pas en dernière minute (on respecte le finish
      // scriptée), pas si on est déjà en déficit (un vrai breath était
      // déjà inséré plus haut).
      final fakeBreath = _maybeBuildFakeBreath(
        lastEmitted: emitDrafts.isNotEmpty ? emitDrafts.last : draft,
        currentStamina: stamina,
        time: time,
        genUntil: genUntil,
        bank: bank,
      );
      if (fakeBreath != null) {
        final staminaBeforeFake = stamina;
        stamina = _applyStaminaChange(stamina, fakeBreath.draft, progress, cfg);
        _advanceSalivaSim(fakeBreath.draft);
        steps.add(_draftToStep(fakeBreath.draft, time: time, text: fakeBreath.text));
        _lastMode = SessionMode.breath;
        _lastText = fakeBreath.text;
        _trackPushedStep(SessionMode.breath, null,
            duration: fakeBreath.draft.duration);
        _fillProfile(profile, time, fakeBreath.draft.duration!, stamina,
            valueStart: staminaBeforeFake);
        time += fakeBreath.draft.duration!;
      }

      // Chain action attachée au draft principal (beg + suite continue) :
      // émise immédiatement après les sous-segments, sans nouveau texte
      // d'intro (la consigne est déjà dans la phrase du beg).
      final chain = draft.chainNext;
      if (chain != null && chain.duration != null) {
        final staminaBefore = stamina;
        stamina = _applyStaminaChange(stamina, chain, progress, cfg);
        _advanceSalivaSim(chain);
        steps.add(_draftToStep(chain, time: time, text: ''));
        _lastMode = chain.mode;
        _lastText = '';
        _lastFrom = chain.from;
        _lastTo = chain.to;
        _trackPushedStep(chain.mode, chain.to,
            from: chain.from, bpm: chain.bpm, duration: chain.duration);
        _fillProfile(profile, time, chain.duration!, stamina,
            valueStart: staminaBefore);
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
          swallowMode: mStep.swallowMode,
        ));
        final mDraft = _stepToDraft(mStep, SessionMode.rhythm);
        final staminaBeforeFinal = stamina;
        stamina = _applyStaminaChange(
            stamina, mDraft, time / effectiveDuration, cfg);
        _advanceSalivaSim(mDraft);
        _fillProfile(profile, time + mStep.time, mStep.duration ?? 0, stamina,
            valueStart: staminaBeforeFinal);
        if (mStep.mode != null && !mStep.isTextOnly) {
          _trackPushedStep(mStep.mode!, mStep.to,
              from: mStep.from, bpm: mStep.bpm, duration: mStep.duration);
        }
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
      _trackPushedStep(SessionMode.rhythm, preDraft.to,
          from: preDraft.from, bpm: preDraft.bpm, duration: preDraft.duration);
      final staminaBeforePre = stamina;
      stamina = _applyStaminaChange(
          stamina, preDraft, time / effectiveDuration, cfg);
      _fillProfile(profile, time, preDur, stamina,
          valueStart: staminaBeforePre);
      _advanceSalivaSim(preDraft);
      time += preDur;
    }

    // Choix du template de finish : `hand_burst` (non humiliant, pure
    // intensité) ou `rhythm_burst` (humiliant). Voir B1 du plan.
    // - humiliation faible (<5) ET niveau ≤ 3 : 70% hand, 30% rhythm
    //   (rhythm sera de toute façon doux à ce niveau, autant pousser via hand)
    // - sinon : 75% rhythm, 25% hand (variété)
    final preferHand =
        _humiliationCareer < 5 && level <= 3 ? 0.70 : 0.25;
    final useHandBurst = _rng.nextDouble() < preferHand;
    final burstMode =
        useHandBurst ? SessionMode.hand : SessionMode.rhythm;

    // Plafond humiliation pour les bursts. Hand n'est pas gating par
    // humiliation (cap inutile), mais on laisse `_enforceHumiliationRequired`
    // tourner — il rejettera juste si la profondeur du draft demande trop.
    // Cap assoupli pour les boosts : projection au temps `time` du début
    // de la phase finish, +8 de tolérance pour permettre des bursts un
    // poil au-dessus du cap mécanique strict (tradition du finish).
    final boostHumilCap = _humilCapAt(time) + 8.0;
    // Nombre total de boosts : table par niveau + bonus encore (fixé en
    // amont via `boostsCount`). Plus de boucle conditionnelle sur la
    // jauge — le sprint est entièrement déterministe.
    final totalBoosts = max(1, boostsCount);
    // **BPM cap qui scale par niveau ET par chaîne d'encore** : niveau 1
    // plafonne à ~110 BPM (hand) / 130 (rhythm), niveau 18 à 170/180. Le
    // mode encore ajoute +8 BPM par cran de chaîne pour intensifier le
    // sprint sans changer le nombre de boosts.
    final levelBpmBoost =
        ((level - 1) * 4 + max(0, encoreChainIndex) * 8).clamp(0, 70);
    final bpmCap = useHandBurst
        ? (110 + levelBpmBoost).clamp(110, 170)
        : (130 + levelBpmBoost).clamp(130, 180);
    final bpmFloor = useHandBurst ? 80 : 100;
    // BPM "ancre" du burst : varie autour de bpmCap selon deficit. Chaque
    // step varie de ±15 par-dessus pour éviter de répéter exactement le
    // même tempo tout en restant clairement en mode finish. La cible (`to`)
    // varie également d'un cran selon le step — sinon on enchaîne 5 fois le
    // même tip→mid à 148 BPM, sensation de stagnation.
    // Cap de profondeur des boosts gaté par les milestones effectivement
    // acquittées (cf. `_milestoneRhythmCeilingIdx`) : throat ouvert si
    // `throatPulse` débloqué (intro_throat_pulse), full si `fullPulse`
    // (intro_full_pulse). Indépendant du niveau seul — sauter des milestones
    // ne donne pas accès aux profondeurs. Borné par `_maxDepthIndex` en
    // sécurité, et par mid (idx 2) au minimum (un boost ne descend jamais
    // sous mid pour rester reconnaissable comme un sprint).
    final boostMaxToIdx =
        max(2, _milestoneRhythmCeilingIdx());
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
    // **Ramp progressif** : la phase finish doit s'entendre comme une
    // accélération, pas comme un sprint plat à 100% dès le 1er boost.
    // On échelonne BPM et profondeur sur la totalité des boosts prévus.
    // Plancher 0.4 : premier boost à ~40 % de la dynamique floor↔cap pour
    // rester reconnaissable comme un sprint dès l'attaque.
    final plannedBoosts = totalBoosts;
    for (var boostsAdded = 0; boostsAdded < totalBoosts; boostsAdded++) {
      // Durée variable : 12 à 16 s par défaut, +1s par cran de chaîne
      // encore pour allonger un peu chaque sprint.
      final boostDur =
          12 + _rng.nextInt(5) + max(0, encoreChainIndex).clamp(0, 4);
      // Progression linéaire 0→1 sur les `plannedBoosts`. Plancher 0.4 :
      // pas de démarrage mou.
      final progress = plannedBoosts <= 1
          ? 1.0
          : ((boostsAdded + 1) / plannedBoosts).clamp(0.4, 1.0);
      final targetBpm =
          (bpmFloor + progress * (bpmCap - bpmFloor)).round();
      // Jitter ±5 BPM autour de la cible pour ne pas répéter exactement
      // le même tempo deux boosts d'affilée. Capé par bpmCap (jamais
      // au-delà du plafond du niveau).
      final shift = _rng.nextInt(11) - 5;
      final bpmRaw = (targetBpm + shift).clamp(bpmFloor, bpmCap);
      // Plancher monotone : on ne descend jamais sous le BPM du boost
      // précédent. Si bpmRaw repassait sous (jitter négatif sur un palier
      // déjà haut), on remonte à prevBoostBpm + 4 pour entendre la montée.
      final bpm = bpmRaw <= prevBoostBpm
          ? min(prevBoostBpm + 4, bpmCap)
          : bpmRaw;
      // Profondeur : ramp aussi sur la progression. boost 1 vise
      // `boostMaxToIdx - 2`, boost 2 vise -1, boost 3+ vise le max.
      // Toujours capé entre mid (idx 2) et le plafond. Le plancher
      // `prevBoostToIdx` garantit la monotonie (jamais de descente).
      final rampDenom = plannedBoosts <= 1 ? 1 : (plannedBoosts - 1);
      final progressionToIdx = (boostMaxToIdx -
              2 +
              2 * (boostsAdded / rampDenom).clamp(0.0, 1.0))
          .round()
          .clamp(2, boostMaxToIdx);
      final toIdx = max(prevBoostToIdx, progressionToIdx);
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
      _trackPushedStep(boostDraft.mode, boostDraft.to,
          from: boostDraft.from, bpm: boostDraft.bpm,
          duration: boostDraft.duration);
      final staminaBeforeBoost = stamina;
      stamina = _applyStaminaChange(stamina, boostDraft, 1.0, cfg);
      _advanceSalivaSim(boostDraft);
      _fillProfile(profile, time, boostDur, stamina,
          valueStart: staminaBeforeBoost);
      time += boostDur;
      // Mémorise BPM/profondeur retenus (post-dégradation humil) pour que le
      // boost suivant ne puisse pas redescendre sous ce palier.
      prevBoostBpm = boostDraft.bpm ?? prevBoostBpm;
      if (boostDraft.to != null) {
        prevBoostToIdx = max(prevBoostToIdx, boostDraft.to!.index);
      }
    }

    // Final : action longue tenue qui clôture la séance. Distinct de la
    // phase « finish » (boosts) ; le final est l'apothéose contemplative.
    // Choisi parmi les candidats valides selon le score d'humiliation, le
    // plafond de profondeur du niveau, et la durée des holds profonds qui
    // scale avec le niveau et la chaîne d'encore.
    // Cap effectif au moment du final (=quasi fin de session, sessionCap
    // probablement saturé). Le générateur ne bénéficie pas des bumps
    // évènementiels (punition complétée etc.) — uniquement de la rampe
    // automatique — donc c'est volontairement conservateur.
    final finalHumilCap = _humilCapAt(time);
    // En chaîne encore, on allonge le final pour que la dramaturgie de
    // « tu en veux encore » se traduise aussi côté apothéose. Bornée par
    // le clamp de `_pickFinal` pour rester raisonnable.
    final finishMul = 1.0 + max(0, encoreChainIndex) * 0.10;
    final finisherDraft = _pickFinal(
      humilCap: finalHumilCap,
      includeHand: includeHand,
      maxDepth: _maxDepthIndex,
      finishMul: finishMul,
    );
    final finalCategory = _categorizeFinal(finisherDraft);
    final finalMode = finisherDraft.mode;

    // **Annonce du final** : si le finisher change de mode (ex: dernier
    // boost = hand, finisher = lick), on prépare une phrase qui annonce le
    // changement physique imminent (« sors ta langue, j'arrive »). On la
    // pose **sur le step final lui-même** (pas sur le dernier boost) pour
    // qu'elle retentisse juste avant le `finale_chime` — feedback : annoncée
    // 12-16 s en avance sur un boost, l'effet « ça arrive » se diluait. Si
    // le finisher reste dans le même mode, on retombe sur la phrase d'action
    // (« ouvre ta bouche », « avale tout »…) qui guide l'exécution.
    final announcePhrase = (lastBoostIndex != null && burstMode != finalMode)
        ? bank.pickFinalAnnouncement(
            preMode: burstMode,
            finalMode: finalMode,
            rng: _rng,
          )
        : null;
    final finalActionPhrase = bank.pickFinalAction(
      mode: finalMode,
      holdPosition: finalMode == SessionMode.hold ? finisherDraft.from : null,
      rng: _rng,
    );
    final finalStepText =
        (announcePhrase != null && announcePhrase.isNotEmpty)
            ? announcePhrase
            : (finalActionPhrase ?? '');
    final finalStepStartTime = time;
    final finisherStep =
        _draftToStep(finisherDraft, time: time, text: finalStepText);
    _lastMode = finalMode;
    _lastText = finalStepText;
    _trackPushedStep(finalMode, finisherDraft.to,
        from: finisherDraft.from, bpm: finisherDraft.bpm,
        duration: finisherDraft.duration);
    final finisherDuration = finisherDraft.duration!;
    steps.add(finisherStep);
    final staminaBeforeFinisher = stamina;
    stamina = _applyStaminaChange(stamina, finisherDraft, 1.0, cfg);
    _fillProfile(profile, time, finisherDuration, stamina,
        valueStart: staminaBeforeFinisher);
    _advanceSalivaSim(finisherDraft);
    time += finisherDuration;

    // **Phase post-final** : ~12 s d'action douce après l'orgasme — la
    // coach ne lâche pas l'utilisatrice net, on profite de la fin. Mode
    // contrastant avec le step final (alternance) pour que l'oreille
    // perçoive bien la bascule « apothéose → calme ». Phrase de compliment
    // douce piochée dans `post_final` (fallback `congrats` si vide).
    // Le pool d'actions est tieré par humiliation : lick (= nettoyer après)
    // est l'aftercare humiliant qui n'apparaît qu'au-dessus d'un seuil.
    final postFinalDraft = _buildPostFinalDraft(finalMode, _humilCapAt(time));
    // Phrase : un step `beg` doit porter une CONSIGNE de supplique
    // (« remercie-moi », « supplie-moi de revenir »), pas un compliment
    // doux qui sonnerait à côté. De même un step `lick` post-final
    // attaqué pour la spé sloppy doit porter une consigne d'aftercare
    // humiliant (« lèche pour nettoyer »). Cascade de fallback pour ne
    // jamais tomber sur un text vide.
    final String postFinalText;
    if (postFinalDraft.mode == SessionMode.beg) {
      postFinalText = bank.pickPostFinalBeg(_rng) ??
          bank.pickPostFinal(_rng) ??
          bank.pickCongrats(_rng);
    } else if (postFinalDraft.mode == SessionMode.lick) {
      postFinalText = bank.pickPostFinalLick(_rng) ??
          bank.pickPostFinal(_rng) ??
          bank.pickCongrats(_rng);
    } else {
      postFinalText = bank.pickPostFinal(_rng) ?? bank.pickCongrats(_rng);
    }
    final postFinalDuration = postFinalDraft.duration!;
    steps.add(_draftToStep(postFinalDraft, time: time, text: postFinalText));
    final staminaBeforePostFinal = stamina;
    stamina = _applyStaminaChange(stamina, postFinalDraft, 1.0, cfg);
    _fillProfile(profile, time, postFinalDuration, stamina,
        valueStart: staminaBeforePostFinal);
    _advanceSalivaSim(postFinalDraft);
    time += postFinalDuration;
    _lastMode = postFinalDraft.mode;
    _lastText = postFinalText;
    _trackPushedStep(postFinalDraft.mode, postFinalDraft.to,
        from: postFinalDraft.from, bpm: postFinalDraft.bpm,
        duration: postFinalDraft.duration);

    final finalDuration = time + 2;
    final trimmedProfile = List<double>.generate(
      finalDuration,
      (i) => i < profile.length ? profile[i] : stamina,
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
    );
  }

  /// Vrai si on doit émettre une **mini-vague** au pas courant de la
  /// boucle main. Conditions cumulatives :
  /// - durée totale ≥ 12 min (sinon pas le temps de respirer entre la
  ///   vague et le finish ; les sessions courtes gardent leur diagonale
  ///   d'intensité simple).
  /// - niveau ≥ 5 (pédagogie : on ne surprend pas une débutante avec
  ///   un mini-finish dramatique au milieu de la séance).
  /// - `time >= _nextMiniWaveAt` (replanifié après chaque vague).
  /// - `genUntil - time >= 90 s` (laisse une marge avant la phase finish
  ///   pour ne pas chevaucher pré-finisher / boosts).
  /// - stamina ≥ 35 (assoupli vs 50 initial : sur les profils profondeur
  ///   + endurance basse, la stamina creuse vite et la vague était
  ///   skippée systématiquement aux 5-6 min. La pause longue post-vague
  ///   replenit derrière, donc on peut émettre depuis une stamina plus
  ///   modeste sans casser la dramaturgie).
  bool _shouldEmitMiniWave(
      int time, int effectiveDuration, double stamina, int genUntil) {
    if (effectiveDuration < 720) return false;
    if (_level < 5) return false;
    if (time < _nextMiniWaveAt) return false;
    if (genUntil - time < 90) return false;
    if (stamina < 35) return false;
    return true;
  }

  /// Construit la séquence de la mini-vague : 2 à 3 steps rythmés à BPM
  /// montant, chacun à profondeur progressive (head→mid puis head→mid
  /// puis head→throat si débloqué). Variations de `to` choisies pour ne
  /// pas trigger le détecteur de pattern plat (`_isFlatRhythmicPattern`)
  /// et pour matérialiser la montée à l'oreille (BPMs espacés de 20).
  ///
  /// Chaque step est filtré par `_enforceHumiliationRequired(humilCap)` :
  /// si la vague propose un step trop humiliant pour le cap courant, il
  /// dégrade vers du plus doux automatiquement (ex throat → mid). Si après
  /// dégradation un step duplique le précédent, il est skip plutôt que
  /// re-poussé — la vague peut donc se réduire à 2 steps en pratique.
  List<_StepDraft> _buildMiniWave(double humilCap) {
    final hasThroat = _unlockedKeys.contains(UnlockKey.throatHoldShort) ||
        _maxDepthIndex >= Position.throat.index;
    // Steps montants : BPMs espacés de 20 pour que la variance détectée
    // par `_isFlatRhythmicPattern` (< 10) ne déclenche pas. Choix
    // mode=rhythm sur les 3 steps pour cohérence dramaturgique (un seul
    // mode = montée homogène). `to` qui change évite aussi le pattern
    // plat — la diversification interne ne peut pas le casser.
    final raw = <_StepDraft>[
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 100,
        from: Position.head,
        to: Position.mid,
        duration: 12,
      ),
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 120,
        from: Position.head,
        to: Position.mid,
        duration: 10,
      ),
      _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 135,
        from: Position.head,
        to: hasThroat ? Position.throat : Position.mid,
        duration: 8,
      ),
    ];
    final out = <_StepDraft>[];
    Position? prevTo;
    int? prevBpm;
    for (final s in raw) {
      final filtered = _enforceHumiliationRequired(s, humilCap);
      // Skip si la dégradation rend ce step identique au précédent
      // (mêmes from/to/bpm) — la vague compresserait sinon en plat.
      if (filtered.to == prevTo && filtered.bpm == prevBpm) continue;
      out.add(filtered);
      prevTo = filtered.to;
      prevBpm = filtered.bpm;
    }
    // Garde au minimum 2 steps : si la cascade a tout aplati (cas humil
    // très basse en début de niveau 5), on retombe sur les 2 premiers
    // steps de `raw` sans filtre, qui sont volontairement modérés
    // (head→mid 100/120 — req mécanique très basse).
    if (out.length < 2) {
      return raw.take(2).toList();
    }
    return out;
  }

  /// Construit la **pause longue post-vague** : breath dédié dont la
  /// durée vise à remonter la stamina à ~95 (`_postWaveBreathTarget`).
  /// Distinct du sas breath standard (`_buildBreathRecovery`) qui cap à
  /// 12 s — ici on s'autorise jusqu'à 20 s parce que la vague est un
  /// mini-finish dramatique : on assume une vraie respiration scénarisée
  /// derrière, pas un soupir de 6 s.
  ///
  /// Borne basse 12 s : même si la stamina est déjà haute (cas vague
  /// dégradée par humilCap qui n'a pas creusé), on garde une pause
  /// audible — le silence post-vague est un moment dramaturgique.
  ///
  /// Borne haute 20 s : au-delà, la pause devient plus longue que la
  /// vague elle-même (~30 s) et le coach radoterait du soft. La regen
  /// finit le job sur les phases libres suivantes si besoin.
  ///
  /// Retourne null si moins de 12 s sont disponibles avant `genUntil`
  /// (rare : la vague checke déjà `genUntil - time >= 90`, mais la
  /// vague elle-même consomme jusqu'à 30 s, donc on revérifie ici).
  _StepDraft? _buildPostWaveBreath(
    double stamina,
    double progress,
    CareerLevel cfg,
    int remainingSeconds,
  ) {
    if (remainingSeconds < 12) return null;
    final regen = _lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    final regenPerSec = 2.8 * regen;
    const target = 95.0;
    final deficit = (target - stamina).clamp(0.0, target);
    final raw = regenPerSec <= 0 ? 12.0 : deficit / regenPerSec;
    // Borne dur entre [12, 20] et capée par le temps restant avant le
    // pré-finisher / boosts pour ne pas marcher sur la dramaturgie de
    // fin de session.
    final upperBound = remainingSeconds < 20 ? remainingSeconds : 20;
    final dur = raw.ceil().clamp(12, upperBound);
    return _StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Construit éventuellement un step **swallow_order** : beg libre court
  /// (5-7 s) qui matérialise l'ordre coach « avale tout » quand la sim
  /// salive sature. Sans ce mécanisme, `SalivaEngine` est un compteur
  /// silencieux — la jauge monte, l'auto-déglutition se déclenche
  /// silencieusement, et la mécanique "saliva" n'a aucun rendu côté
  /// dramaturgie. Avec ce step, un overflow projeté devient un moment
  /// audible : phrase impérative + mini-pause beg libre.
  ///
  /// Conditions cumulatives :
  /// - `_salivaSim.value >= 80` : marge de 10 sous le seuil overflow (90)
  ///   pour anticiper et ne pas attendre que ça déborde réellement
  ///   (l'auto-swallow runtime peut intercepter à 75 et masquer).
  /// - `time - _lastSwallowOrderAt >= 90` : cooldown 90 s pour ne pas
  ///   spammer les ordres en série (cas spé sloppy à fond sur lick).
  /// - `genUntil - time >= 60` : marge avant le finish — la dramaturgie
  ///   scriptée ne doit pas être interrompue par un ordre opportuniste.
  /// - `begLibre` débloqué (sinon on imposerait une mécanique avant la
  ///   pédagogie qui la déverrouille).
  ///
  /// Retourne null si une condition manque.
  _StepDraft? _maybeBuildSwallowOrder(int time, int genUntil) {
    if (_salivaSim.value < 80.0) return null;
    if (time - _lastSwallowOrderAt < 90) return null;
    if (genUntil - time < 60) return null;
    if (!_unlockedKeys.contains(UnlockKey.begLibre)) return null;
    final dur = 5 + _rng.nextInt(3); // [5, 7]
    return _StepDraft(
      mode: SessionMode.beg,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
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
      SessionMode finalMode, double humilCap) {
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
          from: null,
          to: Position.tip,
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
          from: null,
          to: Position.head,
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
          from: null,
          to: Position.head,
          duration: dur,
        );
    // Échelle ordonnée. `blocked` exclut le mode du final (alternance) et,
    // pour les beg, vérifie l'unlock `begLibre` (sinon on demanderait à
    // une utilisatrice qui n'a pas encore validé la milestone d'introduction
    // au beg de supplier post-orgasme — pédagogiquement faux).
    //
    // Holds tip/head : bloqués dès que la joueuse a débloqué un palier de
    // hold plus profond (`holdMidShort` ou plus). Cohérent avec la philo
    // design « le seul hold qui a du sens est le plus profond que tu sais
    // tenir » — un hold tip/head post-orgasme alors que mid est acquis
    // est juste une régression arbitraire.
    final isFinalHold = finalMode == SessionMode.hold;
    final canBeg =
        _unlockedKeys.isEmpty || _unlockedKeys.contains(UnlockKey.begLibre);
    final holdCeilingIdx = _milestoneHoldCeilingIdx();
    final holdTipObsolete = holdCeilingIdx > Position.tip.index;
    final holdHeadObsolete = holdCeilingIdx > Position.head.index;
    final candidates = <(double req, bool blocked, _StepDraft Function() build)>[
      (0.0, false, breath),
      (8.0, !_includeHand || finalMode == SessionMode.hand, hand),
      (20.0, isFinalHold || holdTipObsolete, holdTip),
      (25.0, !canBeg, begLibre),
      (35.0, finalMode == SessionMode.lick, lick),
      (55.0, finalMode == SessionMode.rhythm, rhythm),
      (60.0, !canBeg, begHead),
      (70.0, isFinalHold || holdHeadObsolete, holdHead),
    ];
    final valid = candidates
        .where((c) => c.$1 <= humilCap && !c.$2)
        .toList()
      ..sort((a, b) => b.$1.compareTo(a.$1)); // req décroissante
    if (valid.isEmpty) return breath();
    // Biais spé pour les niveaux avancés : sloppy → lick (« lèche pour
    // nettoyer »), obeissance → beg (« remercie-moi », supplique
    // post-orgasme). Conditions cumulatives : level ≥ 7 (bas niveau on
    // garde le cadre doux pour ne pas brutaliser une débutante après son
    // orgasme), humilCap ≥ 30 (la chauffe doit être suffisante pour que
    // le ton tienne), spé ≥ 2 pts dans la branche concernée. 60 % de
    // chance — assez pour que la couleur de la spé soit perceptible
    // post-orgasme, mais 40 % de tirage standard pour conserver de la
    // variété (sinon chaque session avance signe la même fin).
    if (_level >= 7 && humilCap >= 30) {
      final sloppyPts = _pts(SpecializationBranch.sloppy);
      final obPts = _pts(SpecializationBranch.obeissance);
      // Tirage prioritaire si les deux branches sont présentes : on
      // privilégie celle qui a le plus de pts. À égalité, sloppy d'abord
      // (l'aftercare de nettoyage colle mieux au ton « finition »).
      if (sloppyPts >= 2 && sloppyPts >= obPts && _rng.nextDouble() < 0.60) {
        final lickCandidate = valid.where((c) {
          final draft = c.$3();
          return draft.mode == SessionMode.lick;
        }).firstOrNull;
        if (lickCandidate != null) return lickCandidate.$3();
      }
      if (obPts >= 2 && _rng.nextDouble() < 0.60) {
        final begCandidate = valid.where((c) {
          final draft = c.$3();
          return draft.mode == SessionMode.beg;
        }).firstOrNull;
        if (begCandidate != null) return begCandidate.$3();
      }
    }
    // Top 3 : tirage uniforme dans les 3 plus humiliantes accessibles.
    // Donne de la variété sans casser la progression d'humiliation.
    final top = valid.take(3).toList();
    return top[_rng.nextInt(top.length)].$3();
  }

  /// Convertit un [SessionStep] (issu du JSON ou d'une milestone) en
  /// [_StepDraft] interne pour pouvoir le passer à `_applyStaminaChange`.
  /// Convention uniforme : hold/beg portent leur position dans `to` ;
  /// aucun swap.
  _StepDraft _stepToDraft(SessionStep step, SessionMode defaultMode) {
    final mode = step.mode ?? defaultMode;
    return _StepDraft(
      mode: mode,
      bpm: step.bpm,
      from: step.from,
      to: step.to,
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
      // Profondeur plafonnée par les milestones acquittées (jamais throat
      // sans `throat_pulse`, jamais full sans `full_pulse`) — on borne aussi
      // à throat (idx 3) pour ne jamais lancer un intense full d'amorce.
      final to = Position.values[_milestoneRhythmCeilingIdx().clamp(2, 3)];
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
    // Panel de variantes filtré par milestones : `rhythm_mid_basic`
    // (intro_deeper_basics, niveau 2) gate les variantes head→mid /
    // tip→mid. Sans cette milestone, on retombe sur lick / rhythm tip→head
    // / hand tip→head (toutes débloquées via intro_basics niveau 1).
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
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 70,
        from: Position.head,
        to: Position.mid,
        duration: 14,
      ),
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
    final allowed = variants.where(_isUnlocked).toList();
    if (allowed.isEmpty) return variants.first;
    return allowed[_rng.nextInt(allowed.length)];
  }

  /// Construit un step `breath` dont la durée est calculée pour combler
  /// exactement un déficit d'endurance projeté. Borné à [3, 15] secondes :
  /// au-delà, on préfère raccourcir la step suivante plutôt qu'imposer
  /// une respi interminable.
  /// Tente de générer un « faux breath » : un breath ultra-court (2-3 s)
  /// inséré juste après un step intense pour faire croire à une pause,
  /// alors que la step suivante reprendra direct sur son tirage normal.
  /// Effet de surprise réservé aux profils déjà habitués à l'humiliation
  /// — sur les débutantes (humil career bas), le contrat pédagogique
  /// reste « breath = vraie respiration » ; mentir à une joueuse qui
  /// vient d'apprendre à respirer briserait sa confiance dans le moteur.
  ///
  /// Conditions cumulatives :
  /// - humiliation career ≥ 20 (seuil = la joueuse a déjà été poussée
  ///   suffisamment pour que le ton taquin/dominateur fasse sens)
  /// - dernier step émis = effort intense (rhythm/hand to ∈ {throat, full}
  ///   à BPM ≥ 90, ou hold to ∈ {throat, full})
  /// - pas dans la dernière minute (on laisse le finish scripté tranquille)
  /// - stamina courante ≥ 30 (sinon un vrai breath était déjà inséré, pas
  ///   besoin de tromperie supplémentaire)
  /// - probabilité 25 % (rare = surprise ; trop fréquent = effet usé)
  ///
  /// Retourne null si une condition n'est pas remplie.
  ({_StepDraft draft, String text})? _maybeBuildFakeBreath({
    required _StepDraft lastEmitted,
    required double currentStamina,
    required int time,
    required int genUntil,
    required PhraseBank bank,
  }) {
    if (_humiliationCareer < 20.0) return null;
    if (genUntil - time < 30) return null; // pas trop près du finish
    if (currentStamina < 30) return null; // déjà en dette, vrai breath plus bas
    final isIntenseRhythm = (lastEmitted.mode == SessionMode.rhythm ||
            lastEmitted.mode == SessionMode.hand) &&
        (lastEmitted.to == Position.throat ||
            lastEmitted.to == Position.full) &&
        (lastEmitted.bpm ?? 0) >= 90;
    final isIntenseHold = lastEmitted.mode == SessionMode.hold &&
        (lastEmitted.to == Position.throat ||
            lastEmitted.to == Position.full);
    if (!isIntenseRhythm && !isIntenseHold) return null;
    if (_rng.nextDouble() >= 0.25) return null;
    // 2-3 s : assez pour entendre un soupir, trop peu pour vraiment
    // récupérer (à 2.8 stamina/s = 5-8 stamina rendus, peanuts face au
    // coût d'un step intense ~25-40).
    final dur = 2 + _rng.nextInt(2);
    final draft = _StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
    // Phrase : on tire d'abord dans le tier `fake_breath` (phrases taquines
    // « une seconde, c'est tout », « tu crois qu'on s'arrête ? »). Fallback
    // sur `hard` si la bank n'a pas encore le pool dédié — au moins le ton
    // reste sec/dominateur, pas une phrase douce qui casse la surprise.
    var text = _pickPhrase(bank, SessionMode.breath, 'fake_breath');
    if (text.isEmpty) {
      text = _pickPhrase(bank, SessionMode.breath, 'hard');
    }
    return (draft: draft, text: text);
  }

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
    // Cohérent avec `_staminaDelta` pour breath : `dur * 2.8 * regen`
    // (vitesse de récup poussée pour que le breath reste plus court
    // que les steps d'action — cf. règle de design dans `_staminaDelta`).
    final regenPerSec = 2.8 * regen;
    // Cible : combler le déficit ET reconstruire un petit buffer de
    // stamina pour pouvoir enchaîner 2-3 steps derrière. Buffer baissé
    // (35 → 22) : à 2.8 stamina/s, 22 = 8 s déjà — au-delà le breath
    // devient plus long que l'action qu'il sépare. Cap haut 18 → 12 s
    // dans la même logique : un soupir, pas une vraie phase. Si la
    // dette reste après 12 s, c'est au moteur d'insérer un nouveau
    // breath plus tard, pas à un breath unique de tout absorber.
    const targetBuffer = 22.0;
    final raw = (deficit + targetBuffer) /
        (regenPerSec <= 0 ? 1.0 : regenPerSec);
    final dur = raw.ceil().clamp(4, 12);
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
    // Convention `_unlockedKeys.isEmpty` = mode hérité : pas de gating, tous
    // les modes sont candidats (cf. `_isUnlocked`). Pour les modes carrière,
    // on ne propose que ceux dont la milestone d'introduction est acquittée.
    final heritage = _unlockedKeys.isEmpty;
    final canBeg = heritage || _unlockedKeys.contains(UnlockKey.begLibre);
    final canBiffleRecovery =
        heritage || _unlockedKeys.contains(UnlockKey.biffleBasic);
    // Freestyle gaté uniquement par sa milestone (intro_freestyle, niveau
    // 7) — on ne double-check plus le niveau, l'acquittement de la
    // milestone est l'unique source de vérité.
    final canFreestyle =
        heritage || _unlockedKeys.contains(UnlockKey.freestyle);
    final candidates = [
      SessionMode.lick,
      if (_includeHand && canBiffleRecovery) SessionMode.biffle,
      if (canBeg) SessionMode.beg,
      if (canFreestyle) SessionMode.freestyle,
      // Rhythm très doux comme « récup en bouche » : BPM bas, tip→head,
      // coût stamina modéré. Toujours candidat — la friction de continuité
      // décide s'il gagne (en bouche : ×3.0, hors bouche : ×3.0 voire +
      // selon la durée d'excursion). Sans ça, une recovery déclenchée
      // depuis bouche reste systématiquement bloquée hors bouche, et le
      // pattern « rhythm → recovery → rhythm » fait des séries de 1 step.
      SessionMode.rhythm,
      // Hold court tip/head : bisou prolongé / immobilisation douce. Sert
      // à insérer l'alternance rhythm/hold même pendant les phases où la
      // stamina est basse (sinon on n'a que des hold sur les rares moments
      // hors recovery). Coût stamina faible à cette profondeur.
      SessionMode.hold,
    ];
    final pool = _filterRepeated(candidates);
    // Tirage pondéré pour que la friction de continuité par type s'applique
    // aussi à la recovery (sans ça, une recovery uniforme repousse souvent
    // langue/libre alors que la séance vient juste de quitter bouche).
    final mode = _pickWeightedMode(pool);
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
    } else if (mode == SessionMode.rhythm) {
      // Rhythm en recovery = bouche douce. La baseline (tip→head) reste
      // ouverte tant que la joueuse n'a pas appris la gorge — gate sur
      // `throatHoldShort` plutôt que `holdMidShort` : les premiers paliers
      // ont besoin de variété (tip→head, tip→mid, head→mid se mélangent),
      // ce serait trop pauvre de tout aligner sur head→mid dès le niveau 4.
      // À partir du moment où la gorge est débloquée, le rhythm de
      // recovery passe à head→mid — la baseline doit refléter le niveau.
      // BPM bas — le coût stamina reste modéré pour ne pas creuser la
      // dette d'endurance qu'on cherche justement à combler ailleurs.
      final hasThroat = _unlockedKeys.contains(UnlockKey.throatHoldShort);
      draft = _StepDraft(
        mode: mode,
        bpm: bpm,
        from: hasThroat ? Position.head : Position.tip,
        to: hasThroat ? Position.mid : Position.head,
        duration: dur,
      );
    } else if (mode == SessionMode.hold) {
      // Hold court en recovery — la position dépend du niveau de la
      // joueuse : tant qu'elle n'a pas dépassé hold mid, c'est tip ou head
      // (bisou / gland tenu, vraie respiration). Dès que throat est
      // débloqué, le hold de récup n'a plus de sens à profondeur basse —
      // on garde le hold mais à la profondeur max (= throat ou full),
      // assumée comme l'unique geste de tenue. La durée courte (4-7s)
      // garde une marge de respi avant de redescendre.
      final ceilingIdx = _milestoneHoldCeilingIdx();
      final holdDur = 4 + _rng.nextInt(4);
      final Position to;
      if (ceilingIdx >= Position.throat.index) {
        // Throat ou full débloqué : on tient profond même en récup.
        // Le user a explicitement validé la règle — pas de hold doux quand
        // tu sais tenir gorge.
        to = ceilingIdx >= Position.full.index && _rng.nextDouble() < 0.30
            ? Position.full
            : Position.throat;
      } else if (ceilingIdx >= Position.mid.index) {
        to = Position.mid;
      } else {
        to = _rng.nextBool() ? Position.tip : Position.head;
      }
      draft = _StepDraft(
        mode: mode,
        bpm: null,
        from: null,
        to: to,
        duration: holdDur,
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
    if (diff >= 0.20 ||
        (_lastType == _StepType.bouche && diff >= 0.10)) {
      candidates.add(SessionMode.hold);
    }
    // biffle : candidat seulement si `biffleBasic` est débloqué (pré-filtre
    // sur le mode pour éviter une cascade systématique de dégradation
    // biffle → lick quand la milestone n'est pas acquise). Le pré-filtre
    // respecte la convention héritée (`_unlockedKeys.isEmpty` = pas de
    // gating) pour ne pas casser les sessions hors carrière.
    final canBiffle = _unlockedKeys.isEmpty ||
        _unlockedKeys.contains(UnlockKey.biffleBasic);
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
    final canBeg = _unlockedKeys.isEmpty ||
        _unlockedKeys.contains(UnlockKey.begLibre);
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
        final bpm = _lerp(60.0, 140.0, bpmScore).round();
        final (from, to) = _sampleFromTo(ampScore);
        var dur = _scaleDuration(
          _lerp(20.0, 60.0, durScore),
          enduranceFactor: 0.05,
          resilienceFactor: 0.04,
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
        return _StepDraft(mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.biffle:
        // Biffle = coups de queue sur le visage : pas de notion de
        // position. from/to restent null.
        final bpm = _lerp(80.0, 140.0, bpmScore).round();
        final dur = _scaleDuration(
          _lerp(15.0, 40.0, durScore),
          enduranceFactor: 0.05,
        );
        return _StepDraft(
            mode: mode, bpm: bpm, from: null, to: null, duration: dur);
      case SessionMode.hold:
        // Convention uniforme hold/beg : la position tenue est dans `to`
        // (matche BeepEngine et le format SessionStep des JSON).
        final to = _pickHoldPosition(ampScore);
        final dur = _scaleDuration(
          _lerp(8.0, 30.0, max(durScore, bpmScore)),
          enduranceFactor: 0.08,
          resilienceFactor: 0.07,
        );
        return _StepDraft(mode: mode, bpm: null, from: null, to: to, duration: dur);
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
        // Convention uniforme hold/beg : la position tenue est dans `to`.
        // Obéissance : beg plus profonds (ampScore boosté localement) et
        // plus longs.
        final obPts = _pts(SpecializationBranch.obeissance);
        final begAmp =
            (ampScore + 0.10 * obPts).clamp(0.0, 1.0);
        final to = _pickBegPosition(begAmp);
        final baseDur = _scaleDuration(
          _lerp(7.0, 16.0, durScore),
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
    final continuity = _continuityMultiplier(m);
    final result = base * coachFactor * continuity;
    return result < 0 ? 0 : result;
  }

  /// Multiplicateur appliqué à `_modeWeight` pour favoriser la continuité
  /// par type de step. Le but est que la séance ressente une cohérence :
  /// on reste plusieurs steps consécutifs sur le même type, avec variation
  /// par paramètres (BPM, profondeur, phrases) plutôt que de sauter d'un
  /// type à l'autre à chaque step. La bouche est le cœur de l'app —
  /// continuité forte, friction marquée pour en sortir, retour activement
  /// favorisé après une excursion.
  ///
  /// Échelle (réglée pour que la bouche reste le type majoritaire en
  /// nombre de steps) :
  /// - même type que le précédent :
  ///     * bouche → bouche : ×3.0 (très collant — on n'en sort pas pour rien)
  ///     * langue → langue, libre → libre :
  ///         - 1er step : ×1.8 (continuité tolérée)
  ///         - 2e step+ : ×0.6 (dégradation rapide — une excursion hors
  ///           bouche doit rester courte, c'est une intro/transition)
  /// - changement vers bouche depuis langue/libre :
  ///     * 1 step hors bouche : ×1.4 (variété tolérée mais on encourage)
  ///     * 2 steps hors bouche : ×3.0 (forcer le retour)
  ///     * 3+ steps hors bouche : ×6.0 (verrouiller le retour)
  /// - changement DEPUIS bouche vers langue/libre :
  ///     * < 2 steps de bouche : ×0.30 (très peu de chances de partir)
  ///     * 2-3 steps de bouche : ×0.55
  ///     * 4+ steps de bouche : ×0.80 (variété tolérée après une vraie phase)
  /// - changement entre langue ↔ libre/main : ×0.50 (friction marquée —
  ///   on ne saute pas d'un type secondaire à l'autre, on repasse par
  ///   bouche)
  ///
  /// Cas neutres (×1.0) :
  /// - pas de _lastType encore (premier step)
  /// - dernier type = transit (breath/freestyle ne reset pas, donc rare)
  /// - candidat = beg (ambivalent — son type effectif dépend du `to`
  ///   tiré APRÈS le pick, donc on ne biaise pas le tirage du mode)
  /// - candidat = breath/freestyle (sont tirés par d'autres voies, jamais
  ///   par `_pickWeightedMode`, mais on reste neutre par sécurité)
  double _continuityMultiplier(SessionMode candidate) {
    final last = _lastType;
    if (last == null) return 1.0;
    if (last == _StepType.transit) return 1.0;

    if (candidate == SessionMode.breath ||
        candidate == SessionMode.freestyle) {
      return 1.0;
    }

    // beg est ambivalent au moment du tirage : son `to` est décidé après
    // dans `_mapDifficultyToStep`. À diff bas (= début de session,
    // chauffe), `ampScore` tend vers 0 et le beg sort en libre (`to=null`).
    // Si on le traitait neutre (×1.0), il sortait ~14 % du temps en plein
    // milieu d'une série bouche et la fragmentait. On le classe donc en
    // libre/main par défaut — quitte à manquer un peu les beg-non-libre
    // (rares, n'apparaissent qu'à ampScore haut, donc à diff haut).
    final cand = candidate == SessionMode.beg
        ? _StepType.libreMain
        : _classifyStep(candidate, null);
    if (cand == _StepType.transit) return 1.0;

    // Verrou strict : si on a déjà 2+ steps consécutifs hors bouche
    // (peu importe lequel), on pousse fortement pour rebasculer sur
    // bouche. Plus on s'écarte longtemps, plus le retour est verrouillé.
    if (_stepsOutsideBouche >= 2) {
      if (cand == _StepType.bouche) return 6.0 + _stepsOutsideBouche * 1.5;
      return 0.05; // quasi banni — sert juste de fallback si bouche bloqué
    }

    if (cand == last) {
      if (last == _StepType.bouche) return 3.0;
      // langue / libre/main : continuité dégradée pour ne pas s'éterniser.
      // 1 step de plus est OK, mais au-delà on pousse le retour à bouche.
      return _stepsInLastType >= 2 ? 0.6 : 1.8;
    }
    if (cand == _StepType.bouche) {
      // Retour à bouche : encouragé dès la 1re excursion, fort dès 2.
      if (_stepsOutsideBouche >= 1) return 3.0;
      return 1.4;
    }
    if (last == _StepType.bouche) {
      // Quitter bouche est très onéreux : on n'en sort qu'après une vraie
      // phase de bouche (3+ steps), et même là la friction reste marquée.
      if (_stepsInLastType < 3) return 0.10;
      if (_stepsInLastType < 5) return 0.30;
      return 0.55;
    }
    return 0.50;
  }

  /// Met à jour `_lastType` / `_stepsInLastType` après push d'un step,
  /// et alimente `_recentEmits` (buffer 3 derniers, modes rythmés
  /// uniquement) pour la détection de pattern plat.
  ///
  /// Les steps `transit` (breath / freestyle) sont une parenthèse
  /// transparente : ils ne touchent ni le tracking de type ni le buffer
  /// `_recentEmits` — un breath de récup au milieu d'une série rythmée ne
  /// doit pas remettre le compteur à zéro côté détection de monotonie.
  /// Plafond (en secondes) de la chaîne `rhythm` consécutive sans
  /// `rhythmHeadMidSustained`. La milestone `intro_rhythm_sustained` ouvre
  /// la possibilité de pomper plus d'une minute d'affilée — sans elle, le
  /// générateur force une rupture (autre mode ou breath).
  static const int _rhythmChainCapSeconds = 60;

  /// Plancher de durée d'un step `rhythm` poussé via `_mapDifficultyToStep`.
  /// Sert à éviter qu'un step soit tronqué à 1-2 s par `_capRhythmConsecutive`
  /// quand on est presque au cap. En dessous, on retire `rhythm` des
  /// candidats au tirage (`_canChainRhythm`).
  static const int _minRhythmStepSeconds = 8;

  /// Vrai si on peut encore ajouter un step `rhythm` à la chaîne sans
  /// dépasser le cap (ou si l'unlock `rhythmHeadMidSustained` est acquis,
  /// auquel cas le cap est désactivé).
  bool _canChainRhythm() {
    if (_unlockedKeys.contains(UnlockKey.rhythmHeadMidSustained)) return true;
    return _consecutiveRhythmSeconds + _minRhythmStepSeconds
        <= _rhythmChainCapSeconds;
  }

  /// Tronque la durée d'un step `rhythm` pour respecter le cap chaîne
  /// consécutive. No-op si l'unlock est acquis ou si la marge restante
  /// est suffisante.
  int _capRhythmConsecutive(int dur) {
    if (_unlockedKeys.contains(UnlockKey.rhythmHeadMidSustained)) return dur;
    final remaining = _rhythmChainCapSeconds - _consecutiveRhythmSeconds;
    if (remaining <= 0) return dur; // _canChainRhythm aurait dû filtrer
    return min(dur, remaining);
  }

  void _trackPushedStep(SessionMode mode, Position? to,
      {Position? from, int? bpm, int? duration}) {
    // Cap rythme soutenu : on cumule la durée des `rhythm` consécutifs.
    // Tout autre mode (breath compris — c'est une vraie pause de souffle)
    // remet le compteur à zéro.
    if (mode == SessionMode.rhythm) {
      _consecutiveRhythmSeconds += duration ?? 0;
    } else {
      _consecutiveRhythmSeconds = 0;
    }
    final type = _classifyStep(mode, to);
    if (type == _StepType.transit) return;
    if (type == _StepType.bouche) {
      _stepsOutsideBouche = 0;
    } else {
      _stepsOutsideBouche++;
    }
    if (type == _lastType) {
      _stepsInLastType++;
    } else {
      _lastType = type;
      _stepsInLastType = 1;
    }
    // Buffer pattern plat : on n'enregistre que les modes à amplitude
    // (rhythm / lick / hand / biffle) — ce sont les seuls où la notion de
    // « même profondeur + même BPM » fait sens. Les hold / beg ne portent
    // pas de BPM, et leur monotonie est gérée ailleurs (variation de
    // position dans `_pickHoldPosition` / `_lastFrom`).
    if (mode == SessionMode.rhythm ||
        mode == SessionMode.lick ||
        mode == SessionMode.hand ||
        mode == SessionMode.biffle) {
      _recentEmits.add((mode: mode, from: from, to: to, bpm: bpm));
      while (_recentEmits.length > 3) {
        _recentEmits.removeAt(0);
      }
    }
  }

  /// Vrai si le draft proposé prolongerait un **pattern plat** : les 3
  /// derniers émis + le draft sont tous (a) du même mode rythmé,
  /// (b) à la même profondeur cible `to`, (c) avec une variance BPM
  /// < 10 sur les 4 valeurs. Sans cette fenêtre élargie, une série
  /// `head→mid 88 / head→mid 92 / head→mid 90` glissait à travers le
  /// check classique (BPMs « différents ») alors que l'oreille perçoit
  /// un plat. Le seuil < 10 reste serré : 10 BPM de variance c'est déjà
  /// audible, on n'intervient que sous ce seuil.
  bool _isFlatRhythmicPattern(_StepDraft d) {
    if (_recentEmits.length < 3) return false;
    if (d.bpm == null || d.to == null) return false;
    if (!_recentEmits.every((e) => e.mode == d.mode)) return false;
    if (!_recentEmits.every((e) => e.to == d.to)) return false;
    final bpms = <int>[
      for (final e in _recentEmits)
        if (e.bpm != null) e.bpm!,
      d.bpm!,
    ];
    if (bpms.length < 4) return false;
    final maxB = bpms.reduce(max);
    final minB = bpms.reduce(min);
    return (maxB - minB) < 10;
  }

  /// Pondération issue de la spé seule, sans le filtre coach. Le coach
  /// (s'il en fournit) multiplie ce score dans `_modeWeight`.
  double _modeBaseWeight(SessionMode m) {
    // Coefficients de spé renforcés (passe de +0.20..+0.60 à +0.35..+0.90
    // par point investi). À 5 pts dans la branche, le mode correspondant
    // pèse jusqu'à ×5.5 pour beg/obeissance, ×4.5 pour lick/sloppy, etc.
    // — assez pour que la couleur de la séance soit clairement audible
    // dès 3 pts dans une branche.
    switch (m) {
      case SessionMode.rhythm:
        return 1.0 +
            0.35 * _pts(SpecializationBranch.rythmeBiffle) +
            0.10 * _pts(SpecializationBranch.profondeur);
      case SessionMode.biffle:
        return 1.0 +
            0.60 * _pts(SpecializationBranch.rythmeBiffle) +
            0.25 * _pts(SpecializationBranch.sloppy);
      case SessionMode.hold:
        return 1.0 +
            0.60 * _pts(SpecializationBranch.endurance) +
            0.40 * _pts(SpecializationBranch.profondeur);
      case SessionMode.lick:
        return 1.0 + 0.70 * _pts(SpecializationBranch.sloppy);
      case SessionMode.beg:
        return 1.0 +
            0.90 * _pts(SpecializationBranch.obeissance) +
            0.20 * _pts(SpecializationBranch.resilience);
      case SessionMode.hand:
        // Poids neutre + boost léger rythmeBiffle (hand est un mode
        // rythmé — cohérent qu'une joueuse rythmeBiffle en voie un peu
        // plus). La friction de continuité par type pilote toujours son
        // apparition principale (intro + reprises de souffle).
        return 1.0 + 0.15 * _pts(SpecializationBranch.rythmeBiffle);
      case SessionMode.breath:
        return 1.0;
      case SessionMode.freestyle:
        // Freestyle = vraie pause libre, sans bip ni guidage. Seul mode
        // tiré uniquement par `_buildRecoveryStep`, donc son poids doit
        // rester marginal pour ne pas dominer toutes les récup une fois
        // débloqué (sinon ~25 % des récup partaient en freestyle parce
        // que son multiplicateur de continuité est neutre — `transit` —
        // alors que les autres candidats prennent la friction de quitter
        // bouche). Un poids bas le garde comme option ponctuelle.
        return 0.25;
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
        // Bénéfice respiration : un step à grande amplitude (ex tip→full,
        // mid→throat) laisse une fenêtre de respi au creux du va-et-vient.
        // À l'inverse, un step throat/full ou throat/throat = pas de
        // respiration, coût plein. À haute vitesse, le bénéfice s'évanouit
        // (la respi n'a plus le temps de s'installer entre deux beats).
        // Formule : amplitudeFactor ∈ [0,1] = (toIdx - fromIdx) / 4
        //          bpmFactor ∈ [0,1] = clamp((100-bpm)/40, 0, 1)
        //          respiBenefit = amplitudeFactor × bpmFactor × 0.40
        // → tip→full 60bpm : −40 % de coût
        // → mid→full 60bpm : −20 %
        // → throat→full 60bpm : −10 %
        // → mid→full 100bpm : 0 % (BPM trop haut)
        final fromIdx = (draft.from)?.index ?? toIdx;
        final amplitude = (toIdx - fromIdx).clamp(0, 4);
        final amplitudeFactor = amplitude / 4.0;
        final respiBpmFactor = ((100.0 - bpm) / 40.0).clamp(0.0, 1.0);
        final respiBenefit = amplitudeFactor * respiBpmFactor * 0.40;
        final costFactor = (1.0 - respiBenefit).clamp(0.6, 1.0);
        next -= (bpm / 100.0) * depth * dur * depthMul * costFactor / 3.0;
      case SessionMode.hold:
        // Convention uniforme : hold/beg portent leur position dans `to`.
        final depth = _positionDepth(draft.to, draft.to);
        next -= depth * dur / 2.5;
      case SessionMode.biffle:
        // Biffle = effort soutenu (la fille encaisse), conso entre rythme
        // et hold, modulée par la profondeur.
        final bpm = (draft.bpm ?? 80).toDouble();
        final depth = _positionDepth(draft.from, draft.to);
        next -= (bpm / 100.0) * depth * dur / 3.5;
      case SessionMode.beg:
        // Convention uniforme : hold/beg portent leur position dans `to`.
        // Sans `to` ou `to = head` → assimilé à du repos vocal (regen).
        // Avec `to = mid/throat/full` → coût comme un hold à cette
        // profondeur (la position doit être tenue pendant la supplique).
        final to = draft.to;
        if (to == null || to == Position.head) {
          final regen = _lerp(
            cfg.regenStartMultiplier,
            cfg.regenEndMultiplier,
            progress,
          );
          next += dur * 1.0 * regen;
        } else {
          final depth = _positionDepth(to, to);
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
        // Toujours regen : breath n'est jamais un step d'effort. Vitesse
        // poussée à 2.8 stamina/s — règle de design : un breath doit être
        // plus court que les steps d'action qu'il sépare, sinon la
        // dramaturgie ressemble à « action / longue pause / action /
        // longue pause ». À 2.8/s, 8 s rendent ~22 stamina, ce qui couvre
        // un step rythme moyen (~20 de coût) et permet d'enchaîner.
        final regen = _lerp(
          cfg.regenStartMultiplier,
          cfg.regenEndMultiplier,
          progress,
        );
        next += dur * 2.8 * regen;
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
  /// `breath`, retourne une copie sans position tenue (récup vocale pure).
  /// Sinon, renvoie [draft] tel quel.
  _StepDraft _stripBegFromAfterSoft(
    _StepDraft draft,
    List<SessionStep> steps,
  ) {
    if (draft.mode != SessionMode.beg) return draft;
    if (draft.to == null) return draft;
    if (steps.isEmpty) return draft;
    final prev = steps.last.mode;
    if (prev != SessionMode.lick && prev != SessionMode.breath) return draft;
    return _StepDraft(
      mode: draft.mode,
      bpm: draft.bpm,
      from: draft.from,
      to: null,
      duration: draft.duration,
    );
  }

  /// Cap la durée d'un step rythmé par le **nombre d'aller-retours** sur
  /// la profondeur cible. Évite qu'un step `to=throat` à 90 bpm dure 60 s
  /// (= 45 pulses = la joueuse n'a aucune respi). Au-delà de mid, on borne
  /// le nombre de pulses par step. Mid et plus haut : pas de cap.
  ///
  /// Convention : 1 pulse = 1 aller-retour from↔to (= 2 beats à BPM donné).
  /// Donc `durMax = maxPulses × 120 / bpm` secondes.
  ///
  /// **Cap dynamique selon l'humiliation career** : à la première fois où
  /// la joueuse aborde la profondeur, son humil career est faible (juste
  /// au seuil de la milestone : ~10 pour throat, ~25 pour full), donc cap
  /// bas (6/4 pulses). À mesure qu'elle accumule l'humil, le cap monte —
  /// et la spé pertinente (profondeur, rythmeBiffle) le pousse encore.
  /// On se base sur l'humil plutôt que le niveau global parce que c'est
  /// l'humil qui mesure la pratique réelle de la profondeur, pas le
  /// passage de palier (un niveau 20 spé sloppy a peu d'humil profondeur,
  /// un niveau 12 spé profondeur en a beaucoup plus).
  int _capRhythmDurationByPulses(int dur, int bpm, Position? to) {
    if (to == null || bpm <= 0) return dur;
    if (to != Position.throat && to != Position.full) return dur;
    // Seuil d'humil au déblocage (approx les `humilRequired` des milestones
    // throat_pulse / full_pulse). Au-dessus de ce seuil, chaque point
    // d'humil supplémentaire ajoute des pulses. throat = pratique plus
    // courante donc rampe plus rapide ; full = profondeur extrême donc
    // rampe plus lente.
    final unlockHumil = to == Position.full ? 25.0 : 10.0;
    final humilBonus = max(0.0, _humiliationCareer - unlockHumil);
    // Spé : rythmeBiffle pour les pulses, profondeur pour la durée
    // d'engagement profond. Coefs modérés pour ne pas écraser la diff.
    final rythmePts = _pts(SpecializationBranch.rythmeBiffle);
    final profondeurPts = _pts(SpecializationBranch.profondeur);
    final maxPulses = to == Position.full
        ? 4 + humilBonus * 0.18 + profondeurPts * 1.0 + rythmePts * 0.4
        : 6 + humilBonus * 0.30 + rythmePts * 0.7 + profondeurPts * 0.5;
    final cap = (maxPulses * 120 / bpm).floor().clamp(3, 60);
    return min(dur, cap);
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
  /// [capByDepth] = true → ceiling et probabilité de profondeur appliqués
  /// (rythme : la profondeur est gated par milestone). false → toutes
  /// profondeurs autorisées (lick : la langue n'a pas de tension de
  /// profondeur ; le filtre se fait en aval via `_isUnlocked` quand `to`
  /// requiert une milestone, ex: `lick_full`).
  (Position, Position) _sampleFromTo(double ampScore,
      {bool capByDepth = true}) {
    final clamped = ampScore.clamp(0.0, 1.0);
    // Min mid (idx 2) au lieu de head (idx 1) : l'amplitude minimale est
    // head→mid, pas tip→head.
    final ceiling = capByDepth ? _maxDepthIndex.clamp(2, 4) : 4;
    var deepestIdx =
        _lerp(2.0, ceiling.toDouble(), clamped).round().clamp(2, ceiling);
    // Bonus Profondeur (spé) : remonte la probabilité de profond, dans
    // la limite du plafond du tirage.
    final depthPts = _pts(SpecializationBranch.profondeur);
    final effectiveDeepProb = capByDepth ? _deepProbability : 1.0;
    final boostedDeepProb =
        (effectiveDeepProb + 0.08 * depthPts).clamp(0.0, 1.0);
    // Si le tirage demande une position profonde (≥ throat) mais que la
    // probabilité ne le permet pas, on rabat sur mid.
    if (deepestIdx >= 3 && _rng.nextDouble() >= boostedDeepProb) {
      deepestIdx = 2;
    }
    final int shallowestIdx;
    if (deepestIdx >= 3 && _rng.nextDouble() < 0.15) {
      // ~15% : tip pour les amplitudes pleines (tip→full marque bien).
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

  /// Tirage spécifique au mode hand. **Une seule variation** en standalone :
  /// `head→throat`. La main enveloppe la base de la verge ; aller plus haut
  /// que les lèvres (= head) n'a pas de sens anatomique, et la varier sur
  /// 3-4 amplitudes brouillait la lecture acoustique sans gain dramaturgique.
  /// Le BPM (60–180, choisi par `bpmScore`) reste le levier de variété.
  ///
  /// `ampScore` est ignoré ici — la variation viendra des futurs combos
  /// hand+rhythm où `from` du hand s'aligne sur le `from` du rhythm
  /// (ex. rhythm mid→throat → hand mid→throat, parce que la main ne peut
  /// pas être plus haut que les lèvres pendant le combo).
  (Position, Position) _sampleFromToForHand(double ampScore) {
    return (Position.head, Position.throat);
  }

  /// Tirage spécifique au mode lick. Tant que `_humiliationCareer < 2`,
  /// le lick reste sur tip→head (l'utilisatrice n'a pas encore appris à
  /// lécher plus profond). À partir de 2, toutes les amplitudes sont
  /// autorisées sans cap niveau — la langue n'a pas de tension de
  /// profondeur (`capByDepth: false`). Si le tirage tombe sur to=full
  /// sans la milestone `lick_full`, le filtre `_isUnlocked` en cascade
  /// dégrade.
  (Position, Position) _sampleFromToForLick(double ampScore) {
    if (_humiliationCareer < 2.0) {
      return (Position.tip, Position.head);
    }
    return _sampleFromTo(ampScore, capByDepth: false);
  }

  /// Profondeur max débloquée pour un hold, basée sur les milestones :
  /// fullHoldShort > throatHoldShort > holdMidShort > head/tip de base.
  /// Capée aussi par `_maxDepthIndex` (cohérence niveau).
  ///
  /// Sémantique design : « le seul hold qui a du sens est le plus profond
  /// que tu sais tenir ». Aller moins profond perd le côté narratif —
  /// l'utilisatrice qui sait tenir gorge n'a aucune raison de tenir mid
  /// pendant une session normale, c'est juste de la baisse arbitraire.
  int _milestoneHoldCeilingIdx() {
    final int milestoneCap;
    if (_unlockedKeys.contains(UnlockKey.fullHoldShort)) {
      milestoneCap = Position.full.index;
    } else if (_unlockedKeys.contains(UnlockKey.throatHoldShort)) {
      milestoneCap = Position.throat.index;
    } else if (_unlockedKeys.contains(UnlockKey.holdMidShort)) {
      milestoneCap = Position.mid.index;
    } else if (_unlockedKeys.contains(UnlockKey.holdHead) ||
        _unlockedKeys.contains(UnlockKey.holdHeadShort)) {
      milestoneCap = Position.head.index;
    } else if (_unlockedKeys.contains(UnlockKey.holdTip)) {
      milestoneCap = Position.tip.index;
    } else {
      // Hérité (sans unlocks renseignés) : on retombe sur le cap de niveau.
      // Évite que le mode démo non-carrière se fige sur tip.
      milestoneCap = _maxDepthIndex;
    }
    return min(milestoneCap, _maxDepthIndex);
  }

  /// Choix de la position d'un hold. Règle : on ne tient **que la profondeur
  /// max débloquée**. Si full est ouverte, on tire entre throat et full
  /// (ampScore + spé profondeur biaisent vers full). Si throat est le max,
  /// on ne tient que throat — pas de retour à mid arbitraire. Au tout début
  /// (mid max), on tient mid.
  Position _pickHoldPosition(double ampScore) {
    final ceilingIdx = _milestoneHoldCeilingIdx();
    final depthPts = _pts(SpecializationBranch.profondeur);
    // Cas full ouvert : choix throat / full pondéré par ampScore + spé.
    if (ceilingIdx >= Position.full.index) {
      final adjusted = (ampScore + 0.10 * depthPts).clamp(0.0, 1.0);
      final boostedFullProb =
          (_deepProbability + 0.10 * depthPts).clamp(0.0, 1.0);
      // Plus ampScore est haut, plus on penche full ; mais on respecte
      // aussi `_deepProbability` du niveau pour ne pas spammer du full
      // dès le palier d'ouverture.
      final wantsFull =
          adjusted >= 0.55 && _rng.nextDouble() < boostedFullProb;
      return wantsFull ? Position.full : Position.throat;
    }
    // Cap inférieur ou égal à throat : on tient strictement le max.
    return Position.values[ceilingIdx];
  }

  /// Cap de profondeur autorisé pour les modes rythmés (rhythm/hand) en
  /// `to`, basé sur les milestones effectivement acquittées :
  /// - `fullPulse` (intro_full_pulse) → full ouvert
  /// - `throatPulse` (intro_throat_pulse) → throat ouvert
  /// - sinon → plafond mid (la joueuse n'a pas encore appris la profondeur)
  ///
  /// Capé aussi par `_maxDepthIndex` en sécurité (cohérence niveau).
  /// Indépendant du niveau : c'est l'acquittement de la milestone qui
  /// débloque, pas le passage de palier.
  int _milestoneRhythmCeilingIdx() {
    final int milestoneCap;
    if (_unlockedKeys.contains(UnlockKey.fullPulse)) {
      milestoneCap = Position.full.index;
    } else if (_unlockedKeys.contains(UnlockKey.throatPulse)) {
      milestoneCap = Position.throat.index;
    } else {
      milestoneCap = Position.mid.index;
    }
    return min(milestoneCap, _maxDepthIndex);
  }

  /// Choix de la position du pré-finisher (transition rythmée juste avant
  /// les boosts, bas niveaux). Le cap suit `_milestoneRhythmCeilingIdx`
  /// — gating par milestones acquittées, jamais par niveau seul.
  Position _pickFinisherPosition(int level) {
    final ceilingIdx = _milestoneRhythmCeilingIdx();
    if (ceilingIdx <= Position.mid.index) return Position.mid;
    if (ceilingIdx == Position.throat.index) {
      // throatPulse acquis : 30% mid (variété) / 70% throat.
      return _rng.nextDouble() < 0.30 ? Position.mid : Position.throat;
    }
    // ceilingIdx == full → fullPulse acquis : tirage parmi mid/throat/full.
    final r = _rng.nextDouble();
    if (r < 0.30) return Position.mid;
    if (r < 0.70) return Position.throat;
    return Position.full;
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
    required Position? to,
    required int obPts,
  }) {
    // Pour V1, on n'attache une chain que sur un beg libre (to == null).
    // Les beg avec position tenue (mid/throat/full) sont déjà mécaniquement
    // chargés, on ne veut pas y greffer une seconde action en plus.
    if (to != null) return null;
    final probability = 0.20 + 0.05 * obPts;
    if (_rng.nextDouble() > probability.clamp(0.20, 0.60)) return null;

    final holdCeilingIdx = _milestoneHoldCeilingIdx();
    final candidates = <(_StepDraft, _StepDraft)>[];
    for (final tpl in _begChainTemplates) {
      // Si le chainNext est un hold à profondeur sous le palier de hold
      // débloqué par milestones, on filtre — un hold tip/head qui suit
      // un beg alors qu'on maîtrise mid est une régression. On NE le
      // promote pas en silence (durée 6 s d'un template tip/head ne
      // tient pas une bouchée à throat ou full) — on retire juste le
      // template du tirage.
      final chain = tpl.$2;
      if (chain.mode == SessionMode.hold &&
          chain.to != null &&
          chain.to!.index < holdCeilingIdx) {
        continue;
      }
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
  /// comme min/max). Pour un beg ancré (`to != null`), on garde tel quel.
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
        from: null,
        to: Position.head,
        duration: 6,
      ),
    ),
    // Beg head + lick head→mid 65 BPM 12 s — profil obéissance avancée
    // (gated par begThroat car beg to non-null).
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: Position.head,
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

  /// Remplit le profil stamina sur l'intervalle `[from, from+count)` avec
  /// une **rampe linéaire** entre [valueStart] (stamina au début du step)
  /// et [valueEnd] (stamina à la fin, après application du delta du step).
  ///
  /// Sans cette interpolation, l'affichage debug montre une valeur unique
  /// pour toute la durée du step, ce qui est trompeur — un breath de 12s
  /// affichait 70 % d'endurance pendant 12 s alors qu'il démarre justement
  /// quand on est en déficit (stamina < 0). La rampe permet de voir la
  /// chute pendant un step rythmique et la remontée pendant un breath /
  /// recovery, ce qui colle à l'intuition de l'utilisatrice.
  ///
  /// Compatibilité : si [valueStart] est omis, on retombe sur le
  /// comportement historique (valeur constante). Conservé pour la phase
  /// de génération (séquences milestone) où on ne calcule pas la valeur
  /// avant.
  void _fillProfile(List<double> profile, int from, int count, double valueEnd,
      {double? valueStart}) {
    final end = min(profile.length, from + count);
    final start = max(0, from);
    if (start >= end) return;
    final span = end - start;
    if (valueStart == null || span <= 1) {
      for (var i = start; i < end; i++) {
        profile[i] = valueEnd;
      }
      return;
    }
    // Rampe linéaire : profile[start] = valueStart, profile[end-1] = valueEnd.
    final dx = (valueEnd - valueStart) / (span - 1);
    for (var i = 0; i < span; i++) {
      profile[start + i] = valueStart + dx * i;
    }
  }

  /// Avance la simulation salive pour un draft. Mute `_salivaSim` et
  /// `_salivaSimSecond`. Appelé en parallèle de chaque simulation excit
  /// principale via [_emitDraftOnSims].
  void _advanceSalivaSim(_StepDraft draft) {
    final dur = draft.duration ?? 0;
    if (dur <= 0) return;
    for (var s = 0; s < dur; s++) {
      _salivaSim.onTickSecond(
        mode: draft.mode,
        from: draft.from,
        to: draft.to,
        swallowMode: SwallowMode.allowed,
        elapsedSecond: _salivaSimSecond,
      );
      _salivaSimSecond++;
    }
  }

  /// Choisit le **final** (= action de clôture après la phase de boosts).
  /// Distinct du finish (= bursts), le final est volontairement contemplatif :
  /// hand lent, lick / biffle bas, ou un hold tenu sur une position de plus
  /// en plus profonde.
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
        from: null,
        to: Position.tip,
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
        from: null,
        to: Position.head,
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
        from: null,
        to: Position.mid,
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
      // Cible évolutive avec l'humiliation accumulée (humilCap = score
      // courant + rampe de finish). Seuil d'introduction throat ≈ 10
      // d'humiliation (req intrinsèque hold throat 10s = 8, marge
      // de tolérance) : à humilCap=10 on tient le minimum (10s) ;
      // +2s par tranche de 5 points d'humil au-dessus. Cap relâché
      // à 40s pour laisser respirer la branche endurance maxée.
      final humilOver = max(0.0, humilCap - 10.0);
      final targetDur =
          (10 + (humilOver / 5).floor() * 2 + endPts * 2).clamp(10, 40);
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
          from: null,
          to: Position.throat,
          duration: dur,
        ),
        req,
        UnlockKey.finalHoldThroat,
      ));
    }

    if (maxDepth >= Position.full.index) {
      // Cible évolutive avec l'humiliation accumulée. Seuil d'introduction
      // full ≈ 30 d'humiliation (req intrinsèque hold full 10s = 22,
      // marge de tolérance) : à humilCap=30 on tient le minimum (10s) ;
      // +3s par tranche de 8 points d'humil au-dessus. Cap relâché à 80s.
      final humilOver = max(0.0, humilCap - 30.0);
      final targetDur =
          (10 + (humilOver / 8).floor() * 3 + endPts * 3).clamp(10, 80);
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
          from: null,
          to: Position.full,
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
  /// deux head→mid identiques **et** détecte une monotonie sur fenêtre
  /// élargie (3 derniers émis + draft = même mode + même `to` + BPMs
  /// resserrés). Quand l'un des deux cas se déclenche, décale d'un cran
  /// vers le haut ou le bas selon le mode :
  /// - rhythm : `_milestoneRhythmCeilingIdx()` (gating milestone)
  /// - lick / hand : full ouvert (pas de tension de profondeur)
  /// - biffle : pas concerné (from/to null par convention)
  _StepDraft _diversifyAmplitude(_StepDraft d) {
    if (d.mode != SessionMode.rhythm &&
        d.mode != SessionMode.lick &&
        d.mode != SessionMode.hand &&
        d.mode != SessionMode.biffle) {
      return d;
    }
    final lastFrom = _lastFrom;
    final lastTo = _lastTo;
    final exactSameAsLast = lastFrom != null &&
        lastTo != null &&
        d.from == lastFrom &&
        d.to == lastTo;
    // Le détecteur fenêtre 3 ne déclenche que si on a déjà 3 émissions
    // rythmées en buffer. Tant qu'il n'y en a pas (début de session), on
    // s'appuie uniquement sur le check classique sur le step précédent.
    final flatPattern = _isFlatRhythmicPattern(d);
    if (!exactSameAsLast && !flatPattern) return d;
    // Même amplitude que le step précédent OU pattern plat sur 3 steps :
    // on décale `to` d'un cran.
    final toIdx = d.to?.index;
    if (toIdx == null) return d;
    final ceil = d.mode == SessionMode.rhythm
        ? _milestoneRhythmCeilingIdx()
        : 4;
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

  /// Pose éventuellement une rampe `bpmEnd` sur le draft : sur les steps
  /// rythmés (rhythm / lick / hand) longs (≥ 30 s) à profondeur ≤ mid,
  /// avec 50 % de probabilité, retourne une copie où `bpmEnd` est décalé
  /// de ±15..25 BPM. Sens biaisé par la position dans la séance : 70 %
  /// montée quand `progress > 0.5` (la séance pousse vers le finish),
  /// 50/50 sinon.
  ///
  /// **Pourquoi seulement ≤ mid** : un step throat ou full a sa propre
  /// tension (la profondeur), pas besoin d'ajouter une rampe ; et
  /// surtout, accélérer un step throat/full ferait dépasser le cap
  /// pulses calculé sur le BPM de départ (cf. `_capRhythmDurationByPulses`).
  /// On garde la rampe pour les phases de bouche moyennes où l'oreille
  /// a vraiment le temps de se lasser sans contraste de profondeur.
  ///
  /// **Bornes** : le BPM cible est clampé entre 50 (sinon on tombe dans
  /// du quasi-statique) et le cap niveau pour le mode (170 hand / 180
  /// rhythm pour les niveaux hauts, plus bas pour les débutantes).
  _StepDraft _maybeApplyBpmRamp(_StepDraft d, double progress) {
    if (d.mode != SessionMode.rhythm &&
        d.mode != SessionMode.lick &&
        d.mode != SessionMode.hand) {
      return d;
    }
    final bpm = d.bpm;
    final dur = d.duration;
    final to = d.to;
    if (bpm == null || dur == null || to == null) return d;
    if (dur < 30) return d;
    if (to.index > Position.mid.index) return d;
    if (_rng.nextDouble() >= 0.5) return d;

    // Direction : 70 % montée passé la moitié de la séance, sinon 50/50.
    final goesUp =
        progress > 0.5 ? _rng.nextDouble() < 0.70 : _rng.nextBool();
    final delta = 15 + _rng.nextInt(11); // [15, 25]
    // Cap BPM par mode + niveau, miroir de la logique boost (`110 +
    // (level-1)*4` pour hand, `130 + ...` pour rhythm). Lick suit rhythm
    // — c'est aussi un mode rythmé bouche.
    final hardCap = d.mode == SessionMode.hand
        ? (110 + (_level - 1) * 4).clamp(60, 170)
        : (130 + (_level - 1) * 4).clamp(60, 180);
    final raw = goesUp ? bpm + delta : bpm - delta;
    final clamped = raw.clamp(50, hardCap);
    if (clamped == bpm) return d; // Rampe nulle = pas la peine.
    return _StepDraft(
      mode: d.mode,
      bpm: d.bpm,
      bpmEnd: clamped,
      from: d.from,
      to: d.to,
      duration: d.duration,
      chainNext: d.chainNext,
    );
  }

  /// Convertit un [_StepDraft] interne en [SessionStep] sérialisable.
  /// Pour les modes hold/beg, swap `from` (position cible interne au draft)
  /// vers `to` côté SessionStep — sémantique « on tient jusqu'à cette
  /// position ». Convention uniforme : hold/beg portent leur position dans
  /// `to`, les autres modes (rhythm/lick/hand/biffle) utilisent from→to
  /// pour l'alternance. Plus de swap, le draft interne et le SessionStep
  /// produit utilisent la même convention.
  SessionStep _draftToStep(_StepDraft draft,
      {required int time, String text = ''}) {
    return SessionStep(
      time: time,
      text: text,
      mode: draft.mode,
      bpm: draft.bpm,
      bpmEnd: draft.bpmEnd,
      from: draft.from,
      to: draft.to,
      duration: draft.duration,
    );
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
      switch (d.to) {
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
        // Convention : hold/beg portent leur position dans `to`.
        final to = d.to;
        if (to == null || to == Position.tip) return UnlockKey.holdTip;
        if (to == Position.head) return UnlockKey.holdHead;
        if (to == Position.mid) return UnlockKey.holdMidShort;
        final dur = d.duration ?? 0;
        if (to == Position.throat) {
          return dur > 10 ? UnlockKey.throatHoldLong : UnlockKey.throatHoldShort;
        }
        if (to == Position.full) {
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
        // Convention : hold/beg portent leur position dans `to`.
        if (d.to == null) return UnlockKey.begLibre;
        if (d.to == Position.full) return UnlockKey.begFull;
        // Toute supplique avec position tenue (head/mid/throat) reste
        // gated par begThroat (palier niveau 14). Avant ça, seule la
        // supplique libre (to=null) doit apparaître. Évite que le
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
  /// **Convention `_unlockedKeys.isEmpty` = mode hérité** : aucun gating
  /// appliqué. Sert aux scénarios hors carrière (sessions JSON statiques,
  /// tests) qui n'ont pas de chaîne milestones à consulter — sans cette
  /// convention, un `generate(...)` sans `unlockedKeys` deviendrait
  /// injouable (cascade systématique sur la baseline). Les call sites
  /// carrière passent toujours un set non vide (au minimum les unlocks
  /// d'`intro_basics` après le niveau 1).
  ///
  /// **Prérequis transverse `begLibre`** : « beg libre » signifie « bouche
  /// libre, supplique facile ». Toutes les autres formes de beg (avec
  /// `from` = position tenue) sont mécaniquement plus dures (la bouche
  /// reste sur la position pendant la supplique). On les bloque donc tant
  /// que begLibre n'est pas acquise — elle reste la fondation pédagogique.
  bool _isUnlocked(_StepDraft d) {
    if (_unlockedKeys.isEmpty) return true;
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
      // Lubrification : la salive projetée module le cap pour les actions
      // qui exigent un fond lubrifié (throat/full). Sous-lubrifié → cap
      // réduit (l'action est dégradée plus probablement). Bien lubrifié →
      // cap augmenté (la coach peut pousser plus loin).
      final lubeDelta = _lubricationCapDelta(current);
      final effectiveAvailable = available + lubeDelta;
      if (r <= effectiveAvailable && _isUnlocked(current)) return current;
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

  /// Retourne un offset au cap d'humiliation selon la lubrification projetée
  /// par `_salivaSim`. S'applique uniquement aux actions qui sollicitent une
  /// pénétration profonde (rhythm/lick avec deepest ≥ throat, hold throat/full).
  /// - saliva < 25 → -5 (sec, l'action coûte plus cher)
  /// - saliva ≥ 60 → +3 (humide, on peut pousser un peu plus)
  /// - sinon : 0
  double _lubricationCapDelta(_StepDraft d) {
    final deepest = _deepestOf(d.from, d.to);
    final needsLube = (d.mode == SessionMode.rhythm ||
            d.mode == SessionMode.lick ||
            d.mode == SessionMode.hold) &&
        deepest != null &&
        deepest.index >= Position.throat.index;
    if (!needsLube) return 0.0;
    final saliva = _salivaSim.value;
    if (saliva < 25.0) return -5.0;
    if (saliva >= 60.0) return 3.0;
    return 0.0;
  }

  Position? _deepestOf(Position? a, Position? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
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
        (d.to == Position.throat || d.to == Position.full) &&
        (d.duration ?? 0) > 5) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: d.from,
        to: d.to,
        duration: max(2, (d.duration ?? 0) ~/ 2),
      );
    }
    // Hold/beg : descendre `to` (la position tenue) d'un cran avant
    // d'aller plus loin.
    final isHoldLike =
        d.mode == SessionMode.hold || d.mode == SessionMode.beg;
    if (isHoldLike && d.to != null && d.to!.index > Position.tip.index) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: d.from,
        to: Position.values[d.to!.index - 1],
        duration: d.duration,
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
    if (d.mode == SessionMode.beg && d.to != null) {
      // Beg avec position tenue → repli sur beg libre.
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: null,
        to: null,
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

  /// Retire `_lastMode` des candidats si une alternative existe et que le
  /// mode est « ponctuel » (breath / beg / biffle / hold / freestyle) — deux
  /// events identiques d'affilé y sonneraient comme un bug.
  ///
  /// Pour les modes « flow » (rhythm / lick / hand), on **accepte la
  /// répétition** : la variété passe par les paramètres (BPM via
  /// `_applyBpmDiversity` qui force ≥18 BPM de delta, profondeur via
  /// `_diversifyAmplitude` qui décale d'un cran). Sans cette fenêtre de
  /// rester sur le même mode, on sortait nécessairement de rythme à chaque
  /// step ; l'utilisateur a relevé que la séance ressemblait à une rotation
  /// stricte au lieu de phases prolongées avec variation.
  List<SessionMode> _filterRepeated(List<SessionMode> candidates) {
    final last = _lastMode;
    if (last == null || candidates.length <= 1) return candidates;
    const flowModes = {
      SessionMode.rhythm,
      SessionMode.lick,
      SessionMode.hand,
    };
    if (flowModes.contains(last)) return candidates;
    final filtered = candidates.where((m) => m != last).toList();
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

/// Cluster sémantique d'un step, utilisé pour assurer la cohérence de
/// la séance : on doit rester plusieurs steps consécutifs sur le même
/// type avant d'en changer (sauf `transit` qui est une parenthèse
/// transparente : breath de récup, freestyle).
///
/// - `bouche` (rhythm, hold, beg-non-libre) : cœur de l'app, on y
///   passe la majorité du temps.
/// - `langue` (lick) : variante douce, intros et transitions.
/// - `libreMain` (hand, biffle, beg-libre) : la bouche est libre, la
///   stim vient de la main / d'un coup / d'une supplique vocale pure.
/// - `transit` (breath, freestyle) : pause neutre, ne casse pas la
///   continuité du type courant.
enum _StepType { bouche, langue, libreMain, transit }

/// Snapshot léger d'un step rythmé déjà émis, conservé dans le buffer
/// roulant `_recentEmits`. Sert à `_isFlatRhythmicPattern` pour détecter
/// une monotonie sur fenêtre 3 (mêmes mode + to + BPMs proches).
typedef _RecentEmit = ({
  SessionMode mode,
  Position? from,
  Position? to,
  int? bpm,
});

/// Classe un step (mode + position éventuelle) en `_StepType`. La
/// position est nécessaire pour `beg` : un beg avec `to` tenu = la
/// bouche reste sur la verge pendant la supplique → `bouche` ; un
/// beg libre (sans `to`) = supplique purement vocale → `libreMain`.
_StepType _classifyStep(SessionMode mode, Position? to) {
  switch (mode) {
    case SessionMode.rhythm:
    case SessionMode.hold:
      return _StepType.bouche;
    case SessionMode.lick:
      return _StepType.langue;
    case SessionMode.hand:
    case SessionMode.biffle:
      return _StepType.libreMain;
    case SessionMode.beg:
      return to == null ? _StepType.libreMain : _StepType.bouche;
    case SessionMode.breath:
    case SessionMode.freestyle:
      return _StepType.transit;
  }
}

/// Brouillon de step interne au générateur, avant matérialisation en
/// `SessionStep` (il manque `time` et `text` qui sont décidés au push).
class _StepDraft {
  final SessionMode mode;
  final int? bpm;

  /// BPM cible en fin de step pour les rampes intra-step (cf. doc de
  /// `SessionStep.bpmEnd`). Null = pas de rampe (BPM constant).
  final int? bpmEnd;
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
    this.bpmEnd,
    this.chainNext,
  });

  SessionStep copyWithTime(int t) => SessionStep(
        time: t,
        mode: mode,
        bpm: bpm,
        bpmEnd: bpmEnd,
        from: from,
        to: to,
        duration: duration,
      );
}
