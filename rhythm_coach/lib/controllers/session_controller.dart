import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../career/models/career_generation_inputs.dart';
import '../career/models/challenge.dart';
import '../career/models/level_milestone.dart';
import '../career/models/phrase_bank.dart';
import '../career/services/generation/career_session_generator.dart';
import '../career/services/specialization_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show milestoneService;
import '../models/punishment.dart';
import '../models/session.dart';
import '../services/ambience_engine.dart';
import '../services/backgrounds_service.dart';
import '../services/badge_service.dart';
import '../services/beep_engine.dart';
import '../services/capability_axis.dart';
import '../services/capability_service.dart';
import '../services/capability_tracker.dart';
import '../services/hold_verifier.dart';
import '../services/humiliation_engine.dart';
import '../services/obedience_engine.dart';
import '../services/punishment_loader.dart';
import '../services/random_comments_loader.dart';
import '../services/saliva_engine.dart';
import '../services/stamina_engine.dart';
import '../services/stats_service.dart';
import '../services/tts_service.dart';

enum SessionState { idle, running, paused, finished, failing }

/// Sous-état pendant le flow fail. Permet à l'UI d'afficher
/// précisément où on en est (« Punition en cours », « Respiration »…).
enum FailPhase { phrase, breath, punishment }

class SessionController extends ChangeNotifier {
  static const Duration _tickInterval = Duration(milliseconds: 200);

  /// Référence mutable de la session : peut être remplacée à chaud par
  /// [requestUpgrade] (action « Supplier » du mode Carrière) sans détruire
  /// le controller. Lue via le getter [session].
  Session _session;
  final TtsService _tts;
  final BeepEngine _beep;
  final AmbienceEngine _ambience;
  final PunishmentBundle _punishmentBundle;
  final RandomCommentsBundle _randomComments;
  final StatsService _stats;
  final BadgeService _badges;

  /// Persistance du profil de capacités. Toujours instancié, mais n'écrit
  /// que si [_capabilityTracker] a produit un rapport — donc en pratique
  /// uniquement sur les sessions carrière (cf. [_capabilityTracker]).
  final CapabilityService _capabilities;

  /// Suivi live du profil de capacités — non null UNIQUEMENT sur les
  /// sessions carrière (`trackCapabilities`). Custom et scénarios JSON ne
  /// l'instancient pas (sandbox / hors carrière).
  final CapabilityTracker? _capabilityTracker;

  /// Plafonds figés sur les appuis FAIL de la session en cours (§6 de la
  /// spec) — le mode carrière les relit pour les passer aux régénérations
  /// (Supplier / retry milestone) et au premier maillon d'un encore
  /// enchaîné, comme il relit l'obédiance live. Vide hors carrière ou tant
  /// qu'aucun fail n'a eu lieu.
  Map<CapabilityAxis, double> get capabilitySessionCeilings =>
      _capabilityTracker?.sessionCeilings ?? const {};

  /// Niveau carrière de la séance — dose la fréquence des phrases du profil
  /// de capacités (Phase 4, `CapabilityRegulator.progressPhraseChanceForLevel`).
  /// 0 hors carrière (le profil n'y est de toute façon pas suivi).
  final int _careerLevel;

  /// Axe de capacité surchargé sur cette séance (`null` hors carrière / profil
  /// neuf). Sert aux phrases `record` : l'exploit annoncé en fin de séance est
  /// celui qu'on a poussé exprès (cohérent avec la phrase `attempt` injectée
  /// par le générateur en début de séance).
  final CapabilityAxis? _capabilityOverloadAxis;

  /// Snapshot du profil de capacités pris au début de la séance (mode
  /// carrière). Sert à l'attribution mid-session du tap-out (phrase `tapout`)
  /// et à détecter un record battu (phrase `record`, en comparant `reached`
  /// au `best` pré-séance). `null` hors carrière.
  final CapabilityProfile? _capabilityProfile;

  /// `UnlockKey` acquittés à l'ouverture de la séance — passés tel quels au
  /// `CareerSessionGenerator` quand on lui demande de produire une punition
  /// carrière (Phase 5). Vide hors carrière → la génération de punition est
  /// inhibée par `_generateCareerPunishmentOrNull` de toute façon, mais on
  /// reste cohérent : pas de set partiel.
  final Set<UnlockKey> _unlockedKeys;

  /// Mirroir du toggle `hand` propagé au générateur principal — repassé au
  /// générateur de punition carrière (Phase 5) pour exclure les compositions
  /// qui impliquent la main (`biffle_burst`) si la joueuse a désactivé hand
  /// pour la séance.
  final bool _includeHand;

  /// Vrai si la séance est une **session bâclée** (mode quickie). Passé à
  /// `CapabilityService.commit` au `_finish` : le `best` du profil de capacités
  /// est enregistré normalement mais la cible adaptative `comfort` n'est pas
  /// recalibrée (cf. §2 de la spec — une séance bâclée est de la niaque
  /// ponctuelle, pas un palier consolidé). Sans effet hors carrière (pas de
  /// tracker → pas de `commit`).
  final bool _isQuickie;

  final HumiliationEngine _humiliation = HumiliationEngine();
  HumiliationEngine get humiliation => _humiliation;
  final ObedienceEngine _obedience = ObedienceEngine();
  ObedienceEngine get obedience => _obedience;
  final SalivaEngine _saliva = SalivaEngine();
  SalivaEngine get saliva => _saliva;

  /// Mode de déglutition courant. Sticky entre steps : un step text-only
  /// avec champ `swallow_mode` change l'état, qui persiste tant qu'aucun
  /// autre step ne le change. Reset à [SwallowMode.allowed] au start et
  /// après un fail. Forçage à `allowed` si l'unlock `sloppySwallowControl`
  /// n'est pas acquis (guard câblé en Phase 3).
  SwallowMode _swallowMode = SwallowMode.allowed;
  SwallowMode get swallowMode => _swallowMode;

  /// Nombre de débordements salive comptabilisés cette session (cap 3
  /// pour le bonus humiliation).
  int _salivaOverflowsThisSession = 0;
  static const int _salivaOverflowsCap = 3;

  /// Endurance live : descend à chaque beat consommateur, regen en breath/
  /// freestyle/idle. Distincte du `_staminaProfile` projeté par le générateur
  /// (qui sert de filigrane « cible théorique »). La barre d'endurance UI
  /// est branchée sur ce live engine.
  final StaminaEngine _stamina = StaminaEngine();
  StaminaEngine get stamina => _stamina;

  /// Vérifie pendant les holds que la position attendue est tenue (caméra +
  /// rappel vocal). `null` = vérification désactivée, le SessionController
  /// fonctionne exactement comme avant.
  final HoldVerifier? _holdVerifier;

  /// Banque de phrases optionnelle, fournie pour les sessions carrière.
  /// Sert à tirer les commentaires TTS aux franchissements de seuils de
  /// progression de la séance. `null` pour les sessions statiques (le
  /// déclenchement est alors un no-op).
  final PhraseBank? _phraseBank;

  /// Seuils de progression (en pourcent de durée écoulée) déjà annoncés
  /// pour la session en cours. Évite de relire la même phrase deux fois.
  final Set<int> _announcedProgressMarkers = <int>{};

  /// Pourcentages canoniques aux franchissements desquels on tire une
  /// phrase TTS via `PhraseBank.pickProgress`.
  static const List<int> _progressMarkers = [25, 50, 75, 90];

  /// Profil d'endurance projeté seconde par seconde, fourni par le
  /// générateur procédural (mode Carrière). Sert au flow fail pour
  /// décider de sauter la phase de respiration quand l'utilisatrice
  /// n'est pas censée être épuisée. `null` pour les sessions statiques.
  List<double>? _staminaProfile;

  /// Seuil au-dessus duquel on considère qu'un breath de récupération
  /// post-fail est inutile.
  static const double _breathSkipStaminaThreshold = 60.0;

  final Stopwatch _stopwatch = Stopwatch();

  /// Offset cumulatif ajouté à `_stopwatch.elapsed` pour calculer le temps
  /// effectif de la séance. Permet de « sauter » dans la timeline (ex:
  /// reprendre à la section suivante après un fail) sans avoir à recréer
  /// la Stopwatch (qui ne peut pas être avancée arbitrairement).
  Duration _timelineOffset = Duration.zero;

  final Random _random = Random();
  Timer? _ticker;

  SessionState _state = SessionState.idle;
  int _nextStepIndex = 0;
  SessionStep? _lastSpoken;

  /// Version **résolue** (placeholders `{name}` substitués) du dernier texte
  /// scripté envoyé au TTS. Sert à l'affichage : on veut que ce qui est
  /// montré à l'écran corresponde exactement à ce qui est lu, pas la version
  /// brute avec le placeholder. Mémorisée au moment du speak pour rester
  /// stable entre rebuilds (le resolver tire un surnom différent à chaque
  /// appel).
  String? _lastSpokenResolvedText;

  /// Dernière étape avec configuration de bip qui a été appliquée.
  /// Sert à restaurer le loop courant après un fail.
  SessionStep? _lastConfigStep;

  /// True dès que le `finale_chime` a été déclenché (par `_checkSteps` au
  /// passage du step final si `Session.finalStepTime` est défini, sinon par
  /// `_finish` en fallback). Évite le double déclenchement et permet à
  /// `_finish` de skipper la phrase finale + chime quand ils ont déjà été
  /// joués pendant le step final.
  bool _finalChimePlayed = false;

  /// True quand le `finale_chime` **sonne réellement** (après l'attente de
  /// la fin de la phrase d'action du step final). Distinct de
  /// [_finalChimePlayed] qui est posé dès l'identification du step final
  /// (donc avant le speak). Consommé par l'overlay de finale pour caler le
  /// halo blanc crémeux pile sur le chime.
  bool _finaleChimeStarted = false;

  // ─── État du flow fail ─────────────────────────────────────────────────

  FailPhase? _failPhase;
  String? _currentFailPhrase;
  Punishment? _currentPunishment;

  /// True tant que le flow fail est en cours.
  /// Mis à false par stop() pour interrompre proprement les phases async.
  bool _failActive = false;

  /// Compteur incrémenté à chaque entrée dans un flow fail (`triggerFail`,
  /// `_runMiniPunishmentFlow`). Permet aux awaits longs (TTS speak, breath,
  /// punition) de détecter qu'ils ont été interrompus par un `stop()` puis
  /// remplacés par un nouveau flow — sans cette garde, le flag booléen seul
  /// peut être réarmé entre l'await et le check, et l'ancien flow continue
  /// son chemin par-dessus le nouveau.
  int _failGen = 0;
  bool _isFailFlowAlive(int gen) => _failActive && _failGen == gen;

  Timer? _punishmentTicker;

  /// Permet à `abandonPunishment()` (déclenché par un appui sur FAIL pendant
  /// la phase punishment) de débloquer le `await` de `_runPunishment` sans
  /// passer par `_failActive` (qui couperait tout le flow fail).
  Completer<void>? _punishmentCompleter;
  bool _punishmentAbandoned = false;

  // ─── État du défi intra-séance (Phase 1) ──────────────────────────────

  /// Phase courante du défi. `none` quand aucun défi n'est en cours
  /// (cas par défaut, hors carrière, ou avant/après la fenêtre défi).
  ChallengePhase _challengePhase = ChallengePhase.none;
  ChallengePhase get challengePhase => _challengePhase;

  /// Seconde absolue de début du step défi (matérialisée). Sert au calcul
  /// `elapsedInChallengeStep = elapsedSeconds - _challengeStepStartedAtSec`
  /// pour piloter les transitions de phase.
  int? _challengeStepStartedAtSec;

  /// Seconde absolue d'entrée en phase `atSeuil` — sert au timeout 8 s
  /// (succès net auto).
  int? _challengeAtSeuilStartedAtSec;
  static const int _challengeSeuilTimeoutSeconds = 8;

  /// Seconde absolue à laquelle une prolongation `JE TIENS ENCORE` expire
  /// (mode openExtension → re-prompt au seuil).
  int? _challengeOpenExtensionDeadlineSec;

  /// Compteur de `JE TIENS ENCORE` acquis. Au `_finish` : +1 humil/+1 obed
  /// par extension (cf. spec § 5.2 succès étendu).
  int _challengeExtensionsCount = 0;
  int get challengeExtensionsCount => _challengeExtensionsCount;

  /// Outcome du défi — posé par les triggers (skipped/fail/netSuccess/
  /// extendedSuccess) ou par `_finish` via timeout. Null tant qu'aucun défi
  /// n'a été terminé.
  ChallengeOutcome? _challengeOutcome;
  ChallengeOutcome? get challengeOutcome => _challengeOutcome;

  /// Phrase coach à afficher pendant la fenêtre défi (annonce / extension /
  /// outcome). Posée par les transitions de phase ; null si le coach n'a
  /// pas de phrase pour l'axe (l'UI retombe alors sur les libellés
  /// localisés via `AppLocalizations`).
  String? _challengeCurrentText;
  String? get challengeCurrentText => _challengeCurrentText;

  /// Snapshot du défi de la séance courante (clone de `session.challenge`).
  /// Posé au `start()` ou au `_checkSteps` quand on entre dans le breath.
  Challenge? _activeChallenge;
  Challenge? get activeChallenge => _activeChallenge;

  /// Seconde absolue à laquelle la phase `countdown` (3-2-1) démarre.
  /// `null` tant qu'on n'y est pas. Sert au calcul du chiffre courant
  /// (3 → 2 → 1) côté UI et au déclenchement TTS dans `_updateChallengePhase`.
  int? _challengeCountdownStartedAtSec;
  int? get challengeCountdownStartedAtSec => _challengeCountdownStartedAtSec;

  /// Dernier chiffre du countdown énoncé en TTS. Évite de dire 2× le
  /// même chiffre dans le même tick (le ticker tourne à 200 ms).
  int _challengeCountdownLastDigitSpoken = -1;

  /// Durée fixe du countdown 3-2-1 en secondes. Dit en TTS pendant les
  /// 3 dernières secondes du breath (auto-trigger) ou immédiatement
  /// après l'appui sur le bouton `GO`.
  static const int _challengeCountdownDurationSec = 3;

  /// `true` quand un step défi est en cours et qu'un appui sur le bouton
  /// FAIL ne doit PAS déclencher le flow fail standard mais être routé vers
  /// la machine d'états défi (cf. spec § 4.4 — bouton FAIL repurposé).
  bool get isChallengeActive =>
      _challengePhase != ChallengePhase.none &&
      _challengePhase != ChallengePhase.ended;

  // ─── Commentaires aléatoires ───────────────────────────────────────────

  Timer? _randomCommentTimer;

  /// Horodatage du dernier `_tts.speak()` déclenché par une étape scriptée
  /// (session ou punition). Sert de cooldown : si on est trop près, on
  /// reporte le commentaire aléatoire pour éviter le chevauchement.
  DateTime _lastScriptedSpeakAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True quand le controller a été détaché des services audio partagés
  /// (cf. [detachAudio]). Empêche `dispose()` de relancer un `tts.stop()`
  /// ou `beep.stop()` qui couperait le démarrage d'une nouvelle session
  /// en train de prendre la main (race observée sur le bouton « encore »).
  bool _released = false;

  /// `AppLocalizations` poussé depuis le screen via [setAppLocalizations]
  /// (appelé en `didChangeDependencies` côté `_SessionScreenState`). Permet
  /// au `_finish()` de résoudre une annonce TTS d'unlock par défaut quand
  /// la milestone n'a pas d'override texte. `null` pour les controllers
  /// instanciés hors widget tree (tests, sessions hors carrière sans l10n).
  AppLocalizations? _appLocalizations;
  void setAppLocalizations(AppLocalizations? l10n) {
    _appLocalizations = l10n;
  }

  /// Callback déclenché par `triggerFail` quand l'utilisatrice rate dans
  /// la fenêtre milestone et qu'un retry est encore disponible. Retourne
  /// `true` si le retry a été pris en charge (le contrôleur saute alors
  /// le flow fail standard). Set depuis `SessionScreen`.
  Future<bool> Function(SessionController controller)? onMilestoneRetry;

  /// Allocation de spécialisation courante. Consommée par la génération de
  /// punition carrière contextuelle (`_generateCareerPunishmentOrNull` →
  /// `CareerSessionGenerator.generatePunishment`). Null = pas de spé connue
  /// (sessions hors carrière).
  final SpecializationAllocation? _specialization;

  /// Service spécialisation — pour consommer la tête de la file showcase
  /// au `_finish` quand le défi de la séance a effectivement matché la
  /// branche fraîchement boostée (cf. spec § 5.1 cascade). Null hors
  /// carrière (le SessionController fonctionne sans consume).
  final SpecializationService? _specializationService;

  /// Probabilité par minute qu'une mini-punition inopinée se déclenche en
  /// cours de séance. Dérivée de la personnalité du coach (cf.
  /// `Coach.miniPunishmentRate`) ; 0 = jamais (sessions hors carrière /
  /// voix par défaut → le caller ne le passe pas).
  final double _miniPunishmentRate;

  /// Slug court du coach actif (`lina`, `victoria`, …) — extrait de l'`id`
  /// `coach_NN_<slug>` par le caller. Sert à orienter la sélection de fond
  /// vers les images taguées au nom de la coach (cf. `BackgroundContext`
  /// dans `BackgroundsService`). Null = pas de coach connue (voix par
  /// défaut, scénarios JSON, démos) → aucun fond `_<coach>` ne sera
  /// considéré comme matchant.
  final String? _coachTag;

  /// Compteur en secondes pour cadencer le tirage de mini-punition
  /// (1 tirage par minute).
  int _miniPunishmentTickAccumulator = 0;

  /// RNG dédié aux mini-punitions. Injectable en test via
  /// [debugSetMiniPunishmentRng] pour forcer le tirage.
  Random _miniPunishmentRng = Random();

  /// Compteur de mini-punitions effectivement déclenchées dans la session
  /// courante. Non persisté — observé par les tests.
  int _miniPunishmentsTriggered = 0;
  @visibleForTesting
  int get miniPunishmentsTriggered => _miniPunishmentsTriggered;

  @visibleForTesting
  void debugSetMiniPunishmentRng(Random rng) {
    _miniPunishmentRng = rng;
  }

  /// Décide si le tick courant doit déclencher une mini-punition cette
  /// minute. Pure : pas de side-effect, pas de lecture d'état controller.
  /// Exposée pour le test unitaire.
  @visibleForTesting
  static bool computeMiniPunishmentTrigger({
    required double rate,
    required double rngValue,
  }) {
    if (rate <= 0) return false;
    return rngValue < rate;
  }

  SessionController({
    required Session session,
    required TtsService tts,
    required BeepEngine beep,
    required AmbienceEngine ambience,
    required PunishmentBundle punishmentBundle,
    required RandomCommentsBundle randomComments,
    StatsService? stats,
    BadgeService? badges,
    CapabilityService? capabilities,
    bool trackCapabilities = false,
    PhraseBank? phraseBank,
    List<double>? staminaProfile,
    HoldVerifier? holdVerifier,
    SpecializationAllocation? specialization,
    SpecializationService? specializationService,
    double miniPunishmentRate = 0.0,
    double seedHumiliationSession = 0.0,
    int careerLevel = 0,
    CapabilityAxis? capabilityOverloadAxis,
    CapabilityProfile? capabilityProfile,
    Set<UnlockKey> unlockedKeys = const {},
    bool includeHand = true,
    bool isQuickie = false,
    String? coachTag,
  })  : _session = session,
        _tts = tts,
        _beep = beep,
        _ambience = ambience,
        _punishmentBundle = punishmentBundle,
        _randomComments = randomComments,
        _stats = stats ?? StatsService(),
        _badges = badges ?? BadgeService(),
        _capabilities = capabilities ?? CapabilityService(),
        _capabilityTracker = trackCapabilities ? CapabilityTracker() : null,
        _phraseBank = phraseBank,
        _staminaProfile = staminaProfile,
        _holdVerifier = holdVerifier,
        _specialization = specialization,
        _specializationService = specializationService,
        _miniPunishmentRate = miniPunishmentRate,
        _seedHumiliationSession = seedHumiliationSession,
        _careerLevel = careerLevel,
        _capabilityOverloadAxis = capabilityOverloadAxis,
        _capabilityProfile = capabilityProfile,
        _unlockedKeys = unlockedKeys,
        _includeHand = includeHand,
        _isQuickie = isQuickie,
        _coachTag = coachTag {
    _beep.onBeat = _handleBeat;
  }

  /// Valeur initiale du `sessionScore` d'humiliation au start. Vaut 0
  /// pour une session normale. Sur encore enchaîné, le caller transmet
  /// le `sessionScore` final de la session précédente pour conserver
  /// la chauffe accumulée (cf. modèle 2 thermomètres).
  final double _seedHumiliationSession;

  /// Tire une phrase TTS au franchissement d'un palier de progression
  /// (25/50/75/90 % de la durée totale de session). Ne joue pas si une
  /// phrase scriptée est en cours — on rate alors l'annonce, le palier
  /// reste marqué pour la session.
  void _handleProgressMarker(int threshold) {
    final bank = _phraseBank;
    if (bank == null) return;
    final phrase = bank.pickProgress(threshold, _random);
    if (phrase == null || phrase.isEmpty) return;
    if (_tts.isSpeaking) return;
    _tts.speak(phrase);
  }

  /// Vérifie si un nouveau palier `_progressMarkers` a été franchi entre
  /// le tick précédent et le courant. Tire une seule phrase par tick pour
  /// éviter d'enchaîner deux annonces.
  void _checkProgressMarkers() {
    final total = session.durationSeconds;
    if (total <= 0) return;
    // Step final entamé → on a déjà déclenché le chime (climax). Les paliers
    // pré-orgasme (« je vais décharger », « prépare ta gorge ») n'ont plus
    // de sens à ce moment-là : marquer le palier comme annoncé mais ne pas
    // parler. Cas typique : final hold long en custom, où le 90 % du temps
    // écoulé tombe en plein dans la tenue post-chime (issue #65).
    if (_finalChimePlayed) {
      final percent = (elapsedSeconds * 100 / total).floor();
      for (final marker in _progressMarkers) {
        if (percent >= marker) _announcedProgressMarkers.add(marker);
      }
      return;
    }
    final percent = (elapsedSeconds * 100 / total).floor();
    for (final marker in _progressMarkers) {
      if (percent >= marker && !_announcedProgressMarkers.contains(marker)) {
        _announcedProgressMarkers.add(marker);
        _handleProgressMarker(marker);
        return;
      }
    }
  }

  /// Détecte un changement de paramètre entre [previous] et [current] et
  /// déclenche une phrase de transition (« plus vite », « plus profond »,
  /// etc.). Ne joue que si :
  /// - même mode résolu (sinon le changement de mode parle pour lui-même)
  /// - delta significatif sur BPM (>10%) ou sur profondeur (`to` ou `from`)
  /// - le TTS n'est pas en train de parler
  /// - une phrase scriptée n'a pas démarré il y a moins de 2 secondes
  /// - la PhraseBank a une phrase pour ce TransitionKind
  void _maybeFireTransitionPhrase(SessionStep previous, SessionStep current) {
    final bank = _phraseBank;
    if (bank == null) return;
    final prevMode = previous.mode ?? session.defaultMode;
    final currMode = current.mode ?? session.defaultMode;
    if (prevMode != currMode) return;

    // Détection de la transition la plus saillante. Priorité depth > speed.
    final kind = _detectTransitionKind(previous, current);
    if (kind == null) return;

    if (_tts.isSpeaking) return;
    final since = DateTime.now().difference(_lastScriptedSpeakAt).inSeconds;
    if (since < 2) return;

    final phrase = bank.pickTransition(kind, _random);
    if (phrase == null || phrase.isEmpty) return;
    _tts.speak(phrase);
  }

  TransitionKind? _detectTransitionKind(
    SessionStep previous,
    SessionStep current,
  ) {
    // Profondeur : on regarde la position la plus profonde atteinte par le
    // step (to si présent, sinon from). Pour hold/beg, on a renommé en `to`,
    // donc current.to porte la cible.
    final prevDepth = previous.to ?? previous.from;
    final currDepth = current.to ?? current.from;
    if (prevDepth != null && currDepth != null) {
      if (currDepth.index > prevDepth.index) return TransitionKind.depthUp;
      if (currDepth.index < prevDepth.index) return TransitionKind.depthDown;
    }
    // Vitesse : delta BPM > 10% du précédent.
    final prevBpm = previous.bpm;
    final currBpm = current.bpm;
    if (prevBpm != null && currBpm != null && prevBpm > 0) {
      final delta = (currBpm - prevBpm) / prevBpm;
      if (delta >= 0.10) return TransitionKind.speedUp;
      if (delta <= -0.10) return TransitionKind.speedDown;
    }
    return null;
  }

  void _handleBeat(BeatEvent e) {
    if (!_session.noStats) {
      _stats.recordBeat(mode: e.mode, to: e.to);
      _stats.markModeUsed(e.mode);
    }
    _stamina.onBeat(e);
  }

  /// Vrai si l'utilisatrice a cliqué au moins une fois sur FAIL pendant
  /// cette session.
  bool _hadFailThisSession = false;

  /// Lecture publique : la SessionScreen carrière en a besoin pour décider
  /// d'un éventuel level-up à la complétion (level-up = niveau max +
  /// pas bâclé + sans fail).
  bool get hadFailThisSession => _hadFailThisSession;

  /// Badges débloqués pendant cette séance, ordonnés par catalogue. Vide
  /// tant que [_finish] n'a pas terminé sa réconciliation. Consommé par
  /// l'écran de fin pour afficher les nouveaux paliers.
  List<BadgeUnlock> _sessionBadgeUnlocks = const [];
  List<BadgeUnlock> get sessionBadgeUnlocks => _sessionBadgeUnlocks;

  /// Milestones acquittées **dans cette séance** (= viennent d'être
  /// `markCompleted` sans fail, n'étaient pas déjà acquittées avant).
  /// Vide tant que [_finish] n'a pas terminé son acquittement. Consommé
  /// par l'écran de fin pour lister les apprentissages validés à côté
  /// des badges.
  List<LevelMilestone> _sessionMilestoneUnlocks = const [];
  List<LevelMilestone> get sessionMilestoneUnlocks => _sessionMilestoneUnlocks;

  /// True si au moins une milestone vient d'être acquittée pendant cette
  /// séance (consulté après [_finish] par le caller pour décider du
  /// level-up via `CareerProgressService.canLevelUp`).
  bool get milestoneAcquittedThisSession => _sessionMilestoneUnlocks.isNotEmpty;

  /// True si la séance avait au moins une milestone candidate planifiée
  /// (body/body2/final) qui ne sera pas acquittée — utilisé par
  /// [triggerFail] pour doubler les malus humil/obed (« tu pouvais avancer,
  /// tu as raté »). Une milestone déjà complétée avant cette séance ne
  /// compte pas (cas défensif : le générateur ne devrait pas en insérer).
  bool _milestoneOpportunityMissed() {
    final ids = <String?>[
      _session.milestoneId,
      _session.secondMilestoneId,
      _session.finalMilestoneId,
    ];
    for (final id in ids) {
      if (id == null) continue;
      if (!milestoneService.isCompleted(id)) return true;
    }
    return false;
  }

  /// Compteur interne de la durée passée dans la position courante (s)
  /// quand on est en mode hold throat/full. Sert à crediter chaque
  /// seconde au StatsService et à mémoriser le hold full le plus long
  /// mené à terme (badge Iron Lungs).
  int _currentHoldFullDuration = 0;

  int _lastHoldTickAtSecond = -1;

  /// Met à jour le profil d'endurance (utilisé après requestUpgrade qui
  /// remplace la timeline restante par une nouvelle suite générée).
  void updateStaminaProfile(List<double>? profile) {
    _staminaProfile = profile;
  }

  /// True si on est dans les 60 dernières secondes de la session. Sert
  /// à amplifier les pénalités fail (« on ruine la session »).
  bool _isInLastMinute() {
    return remaining.inSeconds <= 60 && remaining.inSeconds >= 0;
  }

  /// True si la position courante est à l'intérieur de la fenêtre d'une
  /// des milestones body de la session. Utilisé pour offrir un retry
  /// plutôt que le flow fail standard quand l'utilisatrice rate pendant
  /// l'apprentissage. Couvre les deux body (sessions longues) + la final.
  bool _isInMilestoneWindow() => currentMilestoneIdInWindow != null;

  /// Id de la milestone dont la fenêtre temporelle contient `elapsedSeconds`,
  /// ou `null` si on est hors de toute fenêtre. Cherche dans l'ordre :
  /// body 1, body 2, final. Sert au callback `onMilestoneRetry` pour cibler
  /// la bonne milestone quand la séance en contient plusieurs.
  String? get currentMilestoneIdInWindow {
    final t = elapsedSeconds;
    bool within(int? start, int? dur) {
      if (start == null || dur == null) return false;
      return t >= start && t < start + dur;
    }

    if (within(
        _session.milestoneStartTime, _session.milestoneDurationSeconds)) {
      return _session.milestoneId;
    }
    if (within(_session.secondMilestoneStartTime,
        _session.secondMilestoneDurationSeconds)) {
      return _session.secondMilestoneId;
    }
    if (within(_session.finalMilestoneStartTime,
        _session.finalMilestoneDurationSeconds)) {
      return _session.finalMilestoneId;
    }
    return null;
  }

  /// Endurance projetée à la seconde courante, ou `null` si pas de
  /// profil disponible (sessions statiques).
  double? _staminaAtNow() {
    final profile = _staminaProfile;
    if (profile == null || profile.isEmpty) return null;
    final idx = elapsedSeconds.clamp(0, profile.length - 1);
    return profile[idx];
  }

  // ─── Getters d'état ────────────────────────────────────────────────────

  Session get session => _session;
  SessionState get state => _state;
  Duration get elapsed => _stopwatch.elapsed + _timelineOffset;
  int get elapsedSeconds => elapsed.inSeconds;
  Duration get remaining {
    final r = session.duration - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  SessionStep? get lastSpoken => _lastSpoken;

  /// Texte à afficher dans le panneau « instruction courante » : version
  /// résolue (`{name}` substitué) de la dernière phrase parlée, ou de la
  /// phrase de fail courante si on est en train d'en jouer une. Reste
  /// stable tant qu'aucune nouvelle phrase n'est lue.
  String? get currentDisplayText {
    if (_state == SessionState.failing && _currentFailPhrase != null) {
      return _currentFailPhrase;
    }
    return _lastSpokenResolvedText;
  }

  bool _configApplied = false;
  bool get hasConfig => _configApplied;

  SessionMode get currentMode => _beep.currentMode;
  Position get currentFrom => _beep.currentFrom;
  Position? get currentTo => _beep.currentTo;
  int get currentBpm => _beep.currentBpm;

  double get progress {
    if (session.durationSeconds == 0) return 0;
    final p = elapsed.inMilliseconds / (session.durationSeconds * 1000);
    return p.clamp(0.0, 1.0);
  }

  bool get isRunning => _state == SessionState.running;
  bool get isPaused => _state == SessionState.paused;
  bool get isFinished => _state == SessionState.finished;
  bool get isIdle => _state == SessionState.idle;
  bool get isFailing => _state == SessionState.failing;

  /// True quand le `finale_chime` retentit (après la phrase d'action du
  /// step final). Consommé par l'overlay de finale (halo blanc crémeux) :
  /// combiné à `isRunning`, ça ne s'allume que pour les sessions à step
  /// final dédié (carrière + custom), pile au moment du chime.
  bool get finaleChimeStarted => _finaleChimeStarted;

  FailPhase? get failPhase => _failPhase;
  String? get currentFailPhrase => _currentFailPhrase;
  Punishment? get currentPunishment => _currentPunishment;

  /// True si le bouton FAIL doit être actif. Actif aussi pendant la phase
  /// punishment d'un fail en cours pour permettre d'abandonner la punition.
  bool get canTriggerFail =>
      (_state == SessionState.running && _punishmentBundle.isEmpty == false) ||
      (_state == SessionState.failing && _failPhase == FailPhase.punishment);

  // ─── Ambiance ──────────────────────────────────────────────────────────

  double get ambienceVolume => _ambience.volume;

  Future<void> setAmbienceVolume(double v) async {
    await _ambience.setVolume(v);
    notifyListeners();
  }

  /// Aligne l'ambiance lue sur le mode courant du BeepEngine d'après le
  /// pack actif (porté par AmbienceEngine). Appelé après chaque step de config.
  Future<void> _syncAmbienceToCurrentMode() async {
    await _ambience.playForMode(_beep.currentMode);
  }

  // ─── Cycle principal ───────────────────────────────────────────────────

  bool _starting = false;

  Future<void> start() async {
    // Guard synchrone : un double-clic peut entrer ici deux fois avant
    // que le premier `await _tts.init()` rende la main et que `_state`
    // bascule à `running`. Le drapeau ferme cette fenêtre.
    if (_starting) return;
    if (_state == SessionState.running) return;
    _starting = true;
    try {
      if (_state == SessionState.idle || _state == SessionState.finished) {
        _stopwatch.reset();
        _timelineOffset = Duration.zero;
        _nextStepIndex = 0;
        _lastSpoken = null;
        _lastSpokenResolvedText = null;
        _lastConfigStep = null;
        _configApplied = false;
        _hadFailThisSession = false;
        _finalChimePlayed = false;
        _finaleChimeStarted = false;
        _sessionBadgeUnlocks = const [];
        _sessionMilestoneUnlocks = const [];
        _currentHoldFullDuration = 0;
        _lastHoldTickAtSecond = -1;
        _miniPunishmentTickAccumulator = 0;
        _miniPunishmentsTriggered = 0;
        _announcedProgressMarkers.clear();
        _capabilityTracker?.onSessionStart();
        // Seed neutre : remplacé par les valeurs persistées dès que la
        // lecture async (plus bas) revient. `seedHumiliationSession`
        // transporte la chauffe d'une session précédente lors d'un
        // encore enchaîné (sinon 0 = pas de chauffe initiale).
        _humiliation.seed(career: 0, session: _seedHumiliationSession);
        _obedience.seed(0);
        _saliva.reset();
        _swallowMode = SwallowMode.allowed;
        _salivaOverflowsThisSession = 0;
        // Application des compétences sloppy sur les multiplicateurs de
        // l'engine et le plafond de la barre. Cohérent avec le pattern
        // "compétence acquise = effet immédiat dès la séance suivante".
        // - sloppyDroolBasic : production lick ×1.5, plafond 100
        // - sloppyBiffleSlow : production biffle ×3
        if (milestoneService.hasUnlock(UnlockKey.sloppyDroolBasic)) {
          _saliva.setLickProductionMultiplier(1.5);
          _saliva.setMax(SalivaEngine.sloppyBaseMax);
        } else {
          _saliva.setMax(SalivaEngine.defaultMax);
        }
        if (milestoneService.hasUnlock(UnlockKey.sloppyBiffleSlow)) {
          _saliva.setBiffleProductionMultiplier(3.0);
        }
        _stamina.reset();
        // Lectures async tolérées : si pas finies au premier beat, on est
        // juste à valeur neutre (humiliation 0, obédiance 0). Pas critique —
        // les bumps en cours de session s'appliqueront aux valeurs neutres
        // puis seront remplacés à la première lecture async. La career
        // est seed sur la valeur persistée ; le session conserve sa
        // valeur de seed (encore enchaîné).
        _stats.getHumiliationLevel().then(
              (h) => _humiliation.seed(
                career: h,
                session: _seedHumiliationSession,
              ),
            );
        _stats.getObedienceLevel().then(_obedience.seed);
      }

      await _tts.init();
      await _beep.init();
      await WakelockPlus.enable();

      // Reset du fond média : on repart sur le placeholder animé tant que
      // le premier step de config n'a pas tiré une entrée. Évite qu'une
      // session précédente garde son dernier fond visible le temps du
      // premier tick.
      BackgroundsService.instance.clear();

      _stopwatch.start();
      _state = SessionState.running;
      _startTicker();
      _startRandomComments();
      notifyListeners();
      _checkSteps();
    } finally {
      _starting = false;
    }
  }

  Future<void> pause() async {
    if (_state != SessionState.running) return;
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    _disarmHoldVerifier();
    await _tts.stop();
    await _beep.pause();
    await _ambience.pause();
    _state = SessionState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_state != SessionState.paused) return;
    _stopwatch.start();
    _state = SessionState.running;
    _startTicker();
    _startRandomComments();
    await _beep.resume();
    await _ambience.resume();
    notifyListeners();
  }

  Future<void> stop() async {
    // Signale au flow fail (s'il est en cours) qu'il doit s'arrêter.
    _failActive = false;
    _punishmentTicker?.cancel();
    _punishmentTicker = null;
    _stopRandomComments();
    _disarmHoldVerifier();

    _stopwatch.stop();
    _stopwatch.reset();
    _timelineOffset = Duration.zero;
    _ticker?.cancel();
    _ticker = null;
    await _tts.stop();
    await _beep.stop();
    await _ambience.stop();
    await WakelockPlus.disable();

    _state = SessionState.idle;
    _nextStepIndex = 0;
    _lastSpoken = null;
    _lastSpokenResolvedText = null;
    _lastConfigStep = null;
    _configApplied = false;
    _failPhase = null;
    _currentFailPhrase = null;
    _currentPunishment = null;
    _hadFailThisSession = false;
    _currentHoldFullDuration = 0;
    _lastHoldTickAtSecond = -1;
    // Phase 1 défis — reset complet de la machine d'états.
    _challengePhase = ChallengePhase.none;
    _challengeStepStartedAtSec = null;
    _challengeAtSeuilStartedAtSec = null;
    _challengeOpenExtensionDeadlineSec = null;
    _challengeExtensionsCount = 0;
    _challengeOutcome = null;
    _challengeCurrentText = null;
    _activeChallenge = null;
    _challengeCountdownStartedAtSec = null;
    _challengeCountdownLastDigitSpoken = -1;
    _postChallengeBreathUntilSec = null;
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) => _onTick());
  }

  /// Debug : termine la séance immédiatement comme un succès complet, sans
  /// la jouer. Utile pour itérer sur le contenu (milestones, badges, level
  /// up) sans rejouer une session entière. Réservé au flag de debug
  /// `DebugSettingsService.getSkipSessionButton`.
  ///
  /// Avance la timeline jusqu'à la durée de la session pour que les compteurs
  /// (`_stats.addElapsedSeconds`, etc.) reflètent une session complète, puis
  /// délègue à `_finish` qui fait le travail standard de clôture.
  Future<void> debugFinishSuccess() async {
    if (_state != SessionState.running && _state != SessionState.paused) {
      return;
    }
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    await _tts.stop();
    await _beep.stop();
    // Cale l'horloge logique sur la durée totale (les badges qui regardent
    // `totalSeconds` créditent la session entière).
    final missing = Duration(seconds: session.durationSeconds) - elapsed;
    if (missing > Duration.zero) _timelineOffset += missing;
    _hadFailThisSession = false;
    await _finish();
  }

  void _onTick() {
    _checkSteps();
    _accrueHoldSecond();
    _checkProgressMarkers();
    _updateChallengePhase();
    if (elapsedSeconds >= session.durationSeconds) {
      _finish();
      return;
    }
    notifyListeners();
  }

  /// Crédite une seconde au compteur hold throat/full quand on est dans
  /// ce mode. Utilise [elapsedSeconds] pour ne créditer qu'une fois par
  /// seconde (le ticker tourne à 200 ms).
  void _accrueHoldSecond() {
    final now = elapsedSeconds;
    if (now == _lastHoldTickAtSecond) return;
    _lastHoldTickAtSecond = now;
    _capabilityTracker?.onTickSecond(swallowMode: _swallowMode);
    _obedience.onTickSecond();
    // L'humil tick est accéléré par l'obédiance courante : plus elle obéit
    // bien, plus on accepte qu'elle ait droit à plus d'humiliation par
    // unité de temps.
    _humiliation.onTickSecond(obedienceLevel: _obedience.score);
    _stamina.setCurrentMode(
      _beep.currentMode,
      from: _beep.currentFrom,
      bpm: _beep.currentBpm,
    );
    _stamina.onTickSecond();
    _saliva.onTickSecond(
      mode: _beep.currentMode,
      from: _beep.currentFrom,
      to: _beep.currentTo,
      swallowMode: _swallowMode,
      elapsedSecond: now,
    );
    final overflows = _saliva.popOverflowEvents();
    if (overflows > 0) {
      _capabilityTracker?.onSalivaOverflow();
      final remaining = _salivaOverflowsCap - _salivaOverflowsThisSession;
      final apply = overflows > remaining ? remaining : overflows;
      for (var i = 0; i < apply; i++) {
        _humiliation.onSalivaOverflow();
      }
      _salivaOverflowsThisSession += apply;
    }
    _accrueMiniPunishmentTick();
    if (_beep.currentMode != SessionMode.hold) return;
    final pos = _beep.currentFrom;
    if (pos == Position.throat || pos == Position.full) {
      if (!_session.noStats) {
        _stats.recordHoldSecond(pos);
      }
      if (pos == Position.full) {
        _currentHoldFullDuration++;
      }
    }
  }

  /// À appeler quand le mode change ou que la session se termine : si on
  /// vient de finir un hold full, on enregistre sa durée pour Iron Lungs.
  void _flushHoldFull() {
    if (_currentHoldFullDuration > 0) {
      if (!_session.noStats) {
        _stats.recordHoldFullCompleted(_currentHoldFullDuration);
      }
      _currentHoldFullDuration = 0;
    }
  }

  /// Arme la vérif caméra si le step est un hold sur une position connue.
  /// Pour les autres modes (rhythm/lick/biffle/breath/beg/freestyle/hand) on
  /// ne fait rien — la cible est mouvante, pas pertinent en V1.
  void _armHoldVerifierIfHoldStep(SessionStep step) {
    final verifier = _holdVerifier;
    if (verifier == null) return;
    final mode = step.mode ?? session.defaultMode;
    if (mode != SessionMode.hold) return;
    // Pour le mode hold, la position cible est portée par `step.to`
    // (sémantique « tenir jusqu'à »). Le `BeepEngine.applyStep` qui précède
    // a déjà reflété `to` dans son état interne `currentFrom`, donc on peut
    // s'y rabattre en cas d'absence d'override sur le step (text-only ne
    // ré-arme pas, donc rare).
    final expected = step.to ?? _beep.currentFrom;
    verifier.arm(expected);
  }

  /// Compose le contexte poussé à `BackgroundsService.pickForContext` au
  /// moment d'un step de config. Chaque champ alimente une catégorie de
  /// tags du `BackgroundTagVocabulary` (cf. `backgrounds_loader.dart`) :
  /// - `mode` : nom du mode résolu (`rhythm`, `hold`…).
  /// - `position` : `step.to` (cible courante : le rythme alterne avec `to`
  ///   comme point de tension), à défaut `step.from`. Null hors modes à
  ///   position (breath/biffle/freestyle/hand-sans-from).
  /// - `coach` : slug court de la coach active, transmis au constructeur.
  /// - `phase` : `final` au step `finalStepTime`, `post-final` au-delà.
  BackgroundContext _buildBackgroundContext(
    SessionStep step,
    SessionMode resolvedMode,
  ) {
    final pos = step.to ?? step.from;
    String? phase;
    final finalT = _session.finalStepTime;
    if (finalT != null) {
      if (step.time == finalT) {
        phase = 'final';
      } else if (step.time > finalT) {
        phase = 'post-final';
      }
    }
    return BackgroundContext(
      mode: resolvedMode.name,
      position: pos?.name,
      coach: _coachTag,
      phase: phase,
    );
  }

  /// Désarme la vérif et logue le rapport (V1 : juste un debugPrint).
  void _disarmHoldVerifier() {
    final verifier = _holdVerifier;
    if (verifier == null || !verifier.isArmed) return;
    final report = verifier.disarm();
    if (kDebugMode && report.armedWithDetection) {
      debugPrint(
        '[HoldVerifier] accuracy=${(report.accuracy * 100).toStringAsFixed(0)}%'
        ' total=${report.total.inMilliseconds}ms'
        ' maxDrift=${report.maxDrift.inMilliseconds}ms'
        ' nudges=${report.nudges}',
      );
    }
  }

  void _checkSteps() {
    // Phase 1 défis — quand la joueuse est en train de décider au seuil
    // (`atSeuil`) ou de prolonger (`openExtension`), on ne consomme pas
    // les steps suivants : la séance "se met en pause" sur le step défi
    // qui continue à jouer son loop. Sinon la session normale reprenait
    // par-dessus les boutons d'extension (bug observé en sessions de test).
    if (_challengePhase == ChallengePhase.atSeuil ||
        _challengePhase == ChallengePhase.openExtension) {
      return;
    }
    // Pareil pendant le breath de récup post-défi : le BeepEngine joue
    // un breath, le coach fait son rapport, la joueuse souffle. Le step
    // suivant attend.
    if (_inPostChallengeBreath) return;
    final s = elapsedSeconds;
    var modeChanged = false;
    while (_nextStepIndex < session.steps.length &&
        session.steps[_nextStepIndex].time <= s) {
      final step = session.steps[_nextStepIndex];

      // Anti-coupure des phrases random : si une phrase TTS est en cours
      // et que ce step a son propre texte, on diffère le step entier au
      // tick suivant en reculant l'horloge logique de l'épaisseur d'un
      // tick. Le step s'enclenchera dès que `_tts.isSpeaking` repasse à
      // false. Acceptable pour quelques centaines de ms (la phrase random
      // fait typiquement 2-4 s) ; au-delà la session se prolonge un peu,
      // ce que l'utilisatrice a explicitement validé.
      //
      // On défère pour TOUT step ayant du texte (incluant text-only) :
      // sinon le seul cas effectivement utile (un text-only random qui
      // arrive sur une phrase coach random) ne serait pas couvert.
      // Steps sans texte → on ne diffère jamais : la bascule de mode/bip
      // doit suivre le tempo logique, pas un commentaire vocal.
      if (step.text.isNotEmpty && _tts.isSpeaking) {
        _timelineOffset -= _tickInterval;
        break;
      }

      // Toggle déglutition (sticky). Appliqué AVANT l'éventuelle config de
      // bip pour que le mode soit déjà à jour quand le tick suivant
      // s'exécute. Le forçage à `forbidden` est ignoré tant que l'unlock
      // `sloppySwallowControl` n'est pas acquis (cf. Phase 5). Le retour
      // à `allowed` est toujours autorisé (pas besoin de compétence pour
      // libérer la salope).
      //
      // Transition `forbidden` → `allowed` : on considère que la coach a
      // dit « avale tout maintenant ». Reset salive + bump obéd (la
      // consigne a été suivie). La transition inverse (`allowed` →
      // `forbidden`) ne touche pas la barre courante : la salive déjà
      // accumulée reste, c'est juste l'auto-déglutition qui s'éteint.
      final stepSwallow = step.swallowMode;
      if (stepSwallow != null) {
        final previous = _swallowMode;
        if (stepSwallow == SwallowMode.allowed ||
            milestoneService.hasUnlock(UnlockKey.sloppySwallowControl)) {
          _swallowMode = stepSwallow;
          if (previous == SwallowMode.forbidden &&
              stepSwallow == SwallowMode.allowed) {
            _saliva.forceSwallow();
            _obedience.onPunishmentCompleted();
          }
        }
      }

      // Phase 1 défis — la machine d'états est désormais drivée par
      // `_updateChallengePhase` (appelée dans `_onTick`) sur la base
      // d'`elapsedSeconds` vs `session.challengeBreathStartTime` /
      // `challengeStepTime`. Plus de transition basée sur la consommation
      // de step (fragile au timing TTS / différé `_timelineOffset`).
      if (!step.isTextOnly) {
        // Avant de changer de mode : si on quittait un hold full, on crédite
        // sa durée pour le badge Iron Lungs (uniquement quand le hold est
        // mené à terme — un fail interrompt avant ce flush).
        _flushHoldFull();
        // Désarme la vérif caméra du hold précédent. On rearme juste après
        // si le nouveau step est lui-même un hold.
        _disarmHoldVerifier();
        // On garde le step précédent pour détecter les transitions
        // (changement de BPM ou de profondeur dans le même mode).
        final previousConfig = _lastConfigStep;
        _beep.applyStep(step, session.defaultMode);
        final resolvedMode = step.mode ?? session.defaultMode;
        if (!_session.noStats) {
          _stats.markModeUsed(resolvedMode);
        }
        _configApplied = true;
        _lastConfigStep = step;
        modeChanged = true;
        // Télémétrie capacités : on signale le changement de config avec les
        // valeurs du step (career sessions uniquement — `_capabilityTracker`
        // est null sinon).
        _capabilityTracker?.onStepApplied(
          mode: resolvedMode,
          from: step.from,
          to: step.to,
          bpm: step.bpm,
          duration: step.duration,
        );
        _armHoldVerifierIfHoldStep(step);
        // Sélection priorisée par tags du nom de fichier : on pousse au
        // service le contexte courant (mode, profondeur, coach, phase) et
        // il privilégie les fonds taggés en conséquence (cf.
        // `BackgroundsService.pickForContext`). Anti-doublon immédiat dans
        // le service. Un override `step.background` éventuel est appliqué
        // ci-dessous, après le bloc isTextOnly, parce qu'un step text-only
        // peut aussi vouloir poser un fond précis sans pour autant changer
        // de config bip.
        BackgroundsService.instance.pickForContext(
          _buildBackgroundContext(step, resolvedMode),
        );
        // Si la step n'a pas son propre texte scripté, on tente une phrase
        // de transition (« plus vite », « plus profond »…). Ça ne joue
        // que si on est resté dans le même mode et qu'un paramètre clé a
        // bougé suffisamment, et seulement si le TTS n'est pas occupé.
        if (step.text.isEmpty && previousConfig != null) {
          _maybeFireTransitionPhrase(previousConfig, step);
        }
      }

      // Override explicite de fond si le step le précise (milestones,
      // scénarios, génération carrière qui veut imposer un visuel sur un
      // beat précis). Posté après pickRandom pour gagner si les deux
      // s'appliquent au même tick.
      if (step.background != null) {
        BackgroundsService.instance.setById(step.background!);
      }

      if (step.text.isNotEmpty) {
        _lastSpoken = step;
        _speakScripted(step.text);
      }

      // Step final identifié via `Session.finalStepTime` : on déclenche le
      // `finale_chime` PENDANT le step (pas après, comme historiquement
      // dans `_finish`). La phrase d'action portée par `step.text` (« ouvre
      // ta bouche », « avale tout »…) vient d'être speakée juste au-dessus ;
      // on enchaîne le chime dès qu'elle est terminée. Fire-and-forget pour
      // ne pas bloquer le tick — `awaitSpeakCompletion(true)` côté TTS
      // garantit que le `await speak` du helper retourne après la fin de
      // la phrase, donc le chime ne chevauche pas la voix.
      final finalT = session.finalStepTime;
      if (finalT != null && step.time == finalT && !_finalChimePlayed) {
        _finalChimePlayed = true;
        unawaited(_playFinalChimeAfterAction(step.text));
      }

      _nextStepIndex++;
    }
    // Si un step de config a été appliqué, le mode courant a potentiellement
    // changé → on ré-aligne l'ambiance. Le AmbienceEngine no-op si l'asset
    // n'a pas changé, donc pas de coupure inutile entre 2 steps même mode.
    if (modeChanged) {
      _syncAmbienceToCurrentMode();
    }
  }

  /// Wrapper autour de `_tts.speak` qui marque le dernier instant scripté,
  /// pour permettre au scheduler de commentaires aléatoires de respecter
  /// son cooldown. Coupe explicitement un éventuel random en cours avant
  /// de parler, sinon flutter_tts peut conserver l'audio précédent et le
  /// scripted n'est jamais entendu (race observée sur Android).
  ///
  /// On résout `{name}` AVANT le speak et on stocke le résultat dans
  /// [_lastSpokenResolvedText] : ainsi l'UI peut afficher exactement ce
  /// qui a été prononcé (le resolver re-tirerait un surnom différent si
  /// on l'appelait depuis le widget).
  void _speakScripted(String text) {
    _lastScriptedSpeakAt = DateTime.now();
    final resolved = _tts.resolveText(text);
    _lastSpokenResolvedText = resolved;
    if (_tts.isSpeaking) {
      _tts.stop().then((_) => _tts.speak(resolved));
    } else {
      _tts.speak(resolved);
    }
  }

  /// Attend la fin du speak de la phrase d'action du step final puis joue
  /// le `finale_chime`. Lancé en fire-and-forget depuis `_checkSteps` quand
  /// le step final est appliqué — le chime retentit ainsi PENDANT le step
  /// (sur l'action en cours), pas après comme historiquement dans `_finish`.
  ///
  /// Le polling sur `_tts.isSpeaking` est nécessaire parce que `_speakScripted`
  /// est lui-même non-await : on ne peut pas chaîner directement après son
  /// retour. Petit warmup de 80 ms avant le poll pour laisser le start
  /// handler mettre `_speaking` à `true` (sinon on sort tout de suite).
  /// Deadline de sécurité à 8 s pour ne jamais bloquer si le TTS échoue.
  Future<void> _playFinalChimeAfterAction(String text) async {
    if (text.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 80));
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (
          _tts.isSpeaking && DateTime.now().isBefore(deadline) && !_released) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    if (_released) return;
    // Le chime sonne maintenant : on le signale (l'overlay de finale s'y
    // accroche pour démarrer le halo pile sur le son).
    _finaleChimeStarted = true;
    notifyListeners();
    await _beep.playFinaleChime(category: session.finalCategory);
  }

  // ─── Défi intra-séance (Phase 1) ───────────────────────────────────────
  //
  // Machine d'états pilotée par les transitions de phase suivantes :
  //   none → breath (entrée dans le step breath de countdown)
  //   breath → live (entrée dans le step défi)
  //   live → preExtend (à `seuil - 3 s`)
  //   live | preExtend → atSeuil (au seuil cible)
  //   atSeuil → openExtension (JE TIENS ENCORE)
  //   atSeuil → ended (JE M'ARRÊTE ou timeout 8 s)
  //   openExtension → atSeuil (prolongation expirée → re-prompt)
  //   * → ended (FAIL pendant le défi, selon phase)
  //
  // Au passage en `ended`, `_challengeOutcome` est figé et le `_finish` de
  // session applique les bumps capability/humil/obed correspondants.

  /// Seconde absolue (`elapsedSeconds`) jusqu'à laquelle le breath de
  /// récupération post-défi est actif. `null` = pas de breath en cours.
  /// Pendant cette fenêtre, `_checkSteps` ne consomme aucun step suivant —
  /// la séance "marque une pause" pour laisser le coach faire son rapport
  /// et la joueuse souffler.
  int? _postChallengeBreathUntilSec;
  bool get _inPostChallengeBreath {
    final until = _postChallengeBreathUntilSec;
    return until != null && elapsedSeconds < until;
  }

  /// Libellé de fallback localisé pour un tier donné, quand le coach
  /// n'a pas de `challengePhrases` rédigée pour cet axe. Évite que la
  /// joueuse se retrouve sans annonce / sans feedback visuel pendant
  /// les transitions de phase défi.
  String? _fallbackChallengeText(Challenge ch, String tier) {
    final l10n = _appLocalizations;
    if (l10n == null) return null;
    switch (tier) {
      case 'attempt':
        // Tutoriel hold throat = annonce dédiée plus pédagogique.
        if (ch.isTutorial && ch.axis == CapabilityAxis.holdThroatStreak) {
          return l10n.challengeAttemptTutorialHoldThroat;
        }
        return l10n.challengeAttemptDefault;
      case 'extension':
        return l10n.challengeExtensionDefault;
      case 'success':
        return l10n.challengeSuccessDefault;
      case 'stop':
        return l10n.challengeStopDefault;
      case 'fail':
        return l10n.challengeFailDefault;
      case 'timeout':
        return l10n.challengeTimeoutDefault;
      case 'skip':
        return l10n.challengeSkipDefault;
      default:
        return null;
    }
  }

  /// Libellé d'objectif du défi (ex. « Tiens gorge 10 secondes ») —
  /// affiché en sous-titre du banner UI pendant `live`/`preExtend` pour
  /// rappeler à la joueuse ce qu'elle doit faire. Pas dit en TTS (la
  /// coach a déjà fait l'annonce pendant le breath).
  String? challengeObjectiveText() {
    final ch = _activeChallenge;
    final l10n = _appLocalizations;
    if (ch == null || l10n == null) return null;
    switch (ch.kind) {
      case ChallengeAxisKind.duration:
        if (ch.axis == CapabilityAxis.holdThroatStreak ||
            ch.axis == CapabilityAxis.gorgeApneeStreak ||
            ch.axis == CapabilityAxis.gorgeEngagementStreak) {
          return l10n.challengeBannerHoldThroat(ch.targetThreshold);
        }
        if (ch.axis == CapabilityAxis.holdFullStreak) {
          return l10n.challengeBannerHoldFull(ch.targetThreshold);
        }
        if (ch.mode == SessionMode.hold) {
          return l10n.challengeBannerHoldGeneric(ch.targetThreshold);
        }
        return l10n.challengeBannerGeneric;
      case ChallengeAxisKind.bpm:
        if (ch.mode == SessionMode.biffle) {
          return l10n.challengeBannerBiffle(ch.targetThreshold);
        }
        return l10n.challengeBannerRhythm(ch.targetThreshold);
      case ChallengeAxisKind.depthCran:
        return l10n.challengeBannerGeneric;
    }
  }

  /// Tick de mise à jour de la machine d'états défi. Drivée par
  /// `elapsedSeconds` vs `session.challengeBreathStartTime` /
  /// `challengeStepTime` : ne dépend plus de la consommation des steps
  /// (qui peut être différée par le TTS ou interrompue par un fail), ce
  /// qui rendait la transition `breath → live` peu fiable. Appelée dans
  /// `_onTick` à chaque tick (200 ms).
  void _updateChallengePhase() {
    final ch = _session.challenge;
    if (ch == null) return;
    final phase = _challengePhase;
    if (phase == ChallengePhase.ended) return;
    final breathStart = _session.challengeBreathStartTime;
    final stepStart = _session.challengeStepTime;
    if (breathStart == null || stepStart == null) return;
    final t = elapsedSeconds;
    // Entrée en phase `breath` (annonce coach + boutons PASSE / GO visibles).
    if (phase == ChallengePhase.none && t >= breathStart && t < stepStart) {
      _activeChallenge = ch;
      _challengePhase = ChallengePhase.breath;
      _challengeCurrentText = _pickChallengePhrase(ch, 'attempt') ??
          _fallbackChallengeText(ch, 'attempt');
      _speakChallengePhraseIfAny();
      return;
    }
    // Auto-trigger du countdown 3-2-1 à `stepStart - 3 s` (= 3 dernières
    // secondes du breath) si la joueuse n'a pas pressé `GO`. Cf. spec § 4.3.
    if (phase == ChallengePhase.breath &&
        t >= stepStart - _challengeCountdownDurationSec) {
      _enterChallengeCountdown();
      // Pas de return : on enchaîne sur la logique countdown ci-dessous.
    }
    // Phase `countdown` : dire 3-2-1 en TTS et passer à `live` à 3 s.
    if (_challengePhase == ChallengePhase.countdown) {
      final countdownStart = _challengeCountdownStartedAtSec;
      if (countdownStart != null) {
        final elapsedInCountdown = t - countdownStart;
        _maybeSpeakCountdownDigit(elapsedInCountdown);
        if (elapsedInCountdown >= _challengeCountdownDurationSec) {
          _challengePhase = ChallengePhase.live;
          _challengeStepStartedAtSec = t;
          _challengeCurrentText = null;
        }
      }
      return;
    }
    // À partir d'ici, on est forcément après le step défi (phase live,
    // preExtend, atSeuil, ou openExtension). Calcul du temps écoulé
    // dans le step défi pour piloter les transitions vers le seuil.
    if (_challengeStepStartedAtSec == null) return;
    final elapsedInStep = t - _challengeStepStartedAtSec!;
    final target = ch.targetThreshold;
    // Phase `openExtension` : la prolongation expire → re-prompt au seuil.
    if (phase == ChallengePhase.openExtension) {
      final deadline = _challengeOpenExtensionDeadlineSec;
      if (deadline != null && t >= deadline) {
        _challengePhase = ChallengePhase.atSeuil;
        _challengeAtSeuilStartedAtSec = t;
        _challengeOpenExtensionDeadlineSec = null;
      }
      return;
    }
    // Phase `atSeuil` : surveille le timeout 8 s (succès net auto).
    if (phase == ChallengePhase.atSeuil) {
      final seuilAt = _challengeAtSeuilStartedAtSec;
      if (seuilAt != null && t - seuilAt >= _challengeSeuilTimeoutSeconds) {
        _completeChallenge(ChallengeOutcome.netSuccess, byTimeout: true);
      }
      return;
    }
    // Phases `live` / `preExtend` (calibrées sur axes durée).
    if (ch.kind == ChallengeAxisKind.duration) {
      // Phase 2 défi exploratoire : pas de phase `preExtend` (l'annonce
      // « tu peux rester là si tu veux » suppose un seuil cible, ce que
      // l'exploratoire n'a pas). On passe directement de `live` à
      // `atSeuil` au seuil initial estimé. Cf. spec § 3.2.
      if (!ch.isExploratory &&
          phase == ChallengePhase.live &&
          elapsedInStep >= target - 3 &&
          elapsedInStep < target) {
        _challengePhase = ChallengePhase.preExtend;
        _challengeCurrentText = _pickChallengePhrase(ch, 'extension') ??
            _fallbackChallengeText(ch, 'extension');
        _speakChallengePhraseIfAny();
      }
      if (elapsedInStep >= target) {
        _challengePhase = ChallengePhase.atSeuil;
        _challengeAtSeuilStartedAtSec = t;
      }
    } else {
      // Axes BPM / profondeur : pas de seuil temporel sur le step lui-même
      // (la difficulté est dans le paramètre, pas la durée). On considère
      // le seuil atteint dès la fin nominale du step.
      if (elapsedInStep >= ch.nominalDurationSeconds) {
        _challengePhase = ChallengePhase.atSeuil;
        _challengeAtSeuilStartedAtSec = t;
      }
    }
  }

  /// Bouton `PASSE` pendant le breath du défi — skip le défi entier.
  /// Outcome `skipped` (malus obed -3, aucun signal capability). Le skip
  /// du step défi est fait par `_completeChallenge` via
  /// `_startPostChallengeBreath` (qui appelle aussi `_skipPastChallengeStep`).
  void triggerChallengePass() {
    if (_challengePhase != ChallengePhase.breath) return;
    _completeChallenge(ChallengeOutcome.skipped);
  }

  /// Bouton `GO` pendant le breath du défi — démarre le countdown 3-2-1
  /// immédiatement, sans attendre la fin du breath. La joueuse contrôle
  /// son rythme : dès qu'elle est prête, elle tape `GO` et 3 s plus tard
  /// le step défi démarre.
  void triggerChallengeGo() {
    if (_challengePhase != ChallengePhase.breath) return;
    final stepStart = _session.challengeStepTime;
    if (stepStart == null) return;
    // Avance la timeline pour amener `elapsedSeconds` à `stepStart - 3 s`
    // (= début du countdown). Le step défi sera consommé naturellement
    // par `_checkSteps` 3 s plus tard.
    final targetT = stepStart - _challengeCountdownDurationSec;
    final advance = targetT - elapsedSeconds;
    if (advance > 0) {
      _timelineOffset += Duration(seconds: advance);
    }
    _enterChallengeCountdown();
    notifyListeners();
  }

  /// Bascule en phase `countdown` (3-2-1 TTS + UI). Le chiffre TTS est
  /// énoncé par `_updateChallengePhase` à chaque seconde via
  /// `_maybeSpeakCountdownDigit`.
  void _enterChallengeCountdown() {
    if (_challengePhase != ChallengePhase.breath) return;
    _challengePhase = ChallengePhase.countdown;
    _challengeCountdownStartedAtSec = elapsedSeconds;
    _challengeCountdownLastDigitSpoken = -1;
    _challengeCurrentText = null;
  }

  /// Chiffre courant du countdown (3, 2, 1) ou `null` si on n'est pas en
  /// phase countdown. Exposé pour le banner UI qui affiche le chiffre
  /// en grand.
  int? get challengeCountdownDigit {
    if (_challengePhase != ChallengePhase.countdown) return null;
    final start = _challengeCountdownStartedAtSec;
    if (start == null) return null;
    final elapsedInCountdown = elapsedSeconds - start;
    final digit = _challengeCountdownDurationSec - elapsedInCountdown;
    if (digit < 1 || digit > _challengeCountdownDurationSec) return null;
    return digit;
  }

  /// Énonce le chiffre courant du countdown en TTS si on ne l'a pas
  /// déjà fait pour cette seconde. Skip si le TTS est déjà occupé (le
  /// coach finit peut-être encore sa phrase d'annonce du défi).
  void _maybeSpeakCountdownDigit(int elapsedInCountdown) {
    final digit = _challengeCountdownDurationSec - elapsedInCountdown;
    if (digit < 1 || digit > _challengeCountdownDurationSec) return;
    if (_challengeCountdownLastDigitSpoken == digit) return;
    _challengeCountdownLastDigitSpoken = digit;
    if (_tts.isSpeaking) return;
    _speakScripted(digit.toString());
  }

  /// Bouton `JE TIENS ENCORE` — bascule en mode ouvert, +1 humil/+1 obed
  /// par extension, deadline `max(10, comfort × 0.30)` s.
  void triggerChallengeExtend() {
    if (_challengePhase != ChallengePhase.atSeuil) return;
    final ch = _activeChallenge;
    if (ch == null) return;
    _challengeExtensionsCount++;
    _challengePhase = ChallengePhase.openExtension;
    _challengeAtSeuilStartedAtSec = null;
    _challengeOpenExtensionDeadlineSec = elapsedSeconds + ch.extensionSeconds;
    notifyListeners();
  }

  /// Bouton `JE M'ARRÊTE` — succès net (ou étendu si extensions > 0).
  void triggerChallengeStop() {
    if (_challengePhase != ChallengePhase.atSeuil &&
        _challengePhase != ChallengePhase.openExtension) {
      return;
    }
    final outcome = _challengeExtensionsCount > 0
        ? ChallengeOutcome.extendedSuccess
        : ChallengeOutcome.netSuccess;
    _completeChallenge(outcome);
  }

  /// Termine le défi et fige l'outcome. Les bumps capability/humil/obed
  /// sont appliqués au `_finish` de session (cf. `_applyChallengeOutcome`).
  /// Enchaîne sur un breath de récup de 10 s : le step défi est skippé
  /// dans la timeline, le BeepEngine joue un breath, le coach fait son
  /// rapport (`stop`/`fail`/`timeout`/`success`/`skip`). Pendant ce
  /// breath, `_checkSteps` ne consomme pas le step suivant — la séance
  /// "marque une pause" et la joueuse souffle.
  void _completeChallenge(ChallengeOutcome outcome, {bool byTimeout = false}) {
    if (_challengePhase == ChallengePhase.ended) return;
    _challengeOutcome = outcome;
    _challengePhase = ChallengePhase.ended;
    final ch = _activeChallenge;
    if (ch != null) {
      final tier = switch (outcome) {
        ChallengeOutcome.fail => 'fail',
        ChallengeOutcome.netSuccess => byTimeout ? 'timeout' : 'stop',
        ChallengeOutcome.extendedSuccess => 'success',
        ChallengeOutcome.skipped => 'skip',
      };
      _challengeCurrentText =
          _pickChallengePhrase(ch, tier) ?? _fallbackChallengeText(ch, tier);
      _speakChallengePhraseIfAny();
    }
    _startPostChallengeBreath();
    notifyListeners();
  }

  /// Durée du breath de récup post-défi (toutes voies). Donne au coach
  /// le temps de faire son rapport et à la joueuse de souffler avant
  /// que la séance ne reprenne.
  static const int _postChallengeBreathSeconds = 10;

  /// Lance le breath de récup : skip le step défi dans la timeline,
  /// applique un step breath sur le BeepEngine, et pose le flag
  /// `_postChallengeBreathUntilSec` qui bloque `_checkSteps` pendant
  /// la durée. À l'expiration, le step suivant naturel reprend.
  void _startPostChallengeBreath() {
    _skipPastChallengeStep();
    _postChallengeBreathUntilSec = elapsedSeconds + _postChallengeBreathSeconds;
    // Applique le breath sur le BeepEngine — coupe le loop du défi
    // (hold/rhythm/biffle) en faveur du sample breath. Pas de
    // reconfiguration de mode "officielle" (`_lastConfigStep` reste
    // celui du step défi, restauré naturellement quand le step suivant
    // sera consommé après expiration du breath).
    if (!_released) {
      _beep.applyStep(
        const SessionStep(
          time: 0,
          mode: SessionMode.breath,
          duration: _postChallengeBreathSeconds,
        ),
        session.defaultMode,
      );
      _syncAmbienceToCurrentMode();
    }
  }

  /// Avance la timeline pour passer le step défi (cas `PASSE` pendant le
  /// breath). Cherche le prochain step non text-only après la fenêtre défi
  /// et y bascule via `_timelineOffset`. Si rien ne suit, on laisse la
  /// timeline naturelle aller à son terme.
  void _skipPastChallengeStep() {
    final stepStart = _session.challengeStepTime;
    final stepDur = _activeChallenge?.nominalDurationSeconds;
    if (stepStart == null || stepDur == null) return;
    final endOfChallenge = stepStart + stepDur;
    final advance = endOfChallenge - elapsedSeconds;
    if (advance > 0) {
      _timelineOffset += Duration(seconds: advance);
    }
  }

  String? _pickChallengePhrase(Challenge ch, String tier) {
    final bank = _phraseBank;
    if (bank == null) return null;
    return bank.pickChallengePhrase(ch.axisStorageKey, tier, _random);
  }

  void _speakChallengePhraseIfAny() {
    final text = _challengeCurrentText;
    if (text == null || text.isEmpty) return;
    if (_tts.isSpeaking) return;
    _speakScripted(text);
  }

  /// Applique les bumps liés à l'outcome du défi. Appelé depuis `_finish`
  /// après les bumps humil/obed standards mais avant `_capabilities.commit`.
  /// - `netSuccess` : humil/obed +2 (l'incrément capability passe par le
  ///   tracker qui voit le step défi comme un step normal).
  /// - `extendedSuccess` : netSuccess + N × (+1 humil, +1 obed).
  /// - `fail` : pas de malus humil/obed (cf. spec § 5.3). Le soft-cap
  ///   capability × 0.92 n'est pas distinct du standard pour Phase 1
  ///   (TODO : extension `CapabilityRegulator`) ; le tracker pose déjà un
  ///   ceiling via les FAILs séance, qui plafonnera l'axe naturellement.
  /// - `skipped` : malus obédiance -3, pas de signal capability.
  ///
  /// TODO Phase 1.5 : consume la tête de file showcase si la branche du
  /// défi matche (dépend de la branche `feat/specialization-showcase-queue`).
  /// Phase 3 défis — scanne le catalogue de milestones pour acquitter
  /// silencieusement celles dont `requiresCapability` matche l'axe du défi
  /// à un seuil ≤ valeur atteinte (cf. spec § 5.4).
  ///
  /// Calcul de la valeur atteinte :
  /// - axe durée : `targetThreshold + extensions × extensionSeconds` (borne
  ///   haute conservatrice — l'utilisatrice peut `JE M'ARRÊTE` avant la
  ///   fin d'une prolongation, mais on prend la valeur de référence du
  ///   défi pour rester simple).
  /// - axe BPM / profondeur : `targetThreshold` (tenu au paramètre demandé).
  ///
  /// No-op si :
  /// - outcome non succès (`fail` / `skipped` / `null`)
  /// - pas de profil de capacités (hors carrière)
  Future<void> _acquitMilestonesViaChallenge() async {
    final ch = _activeChallenge;
    final outcome = _challengeOutcome;
    if (ch == null || outcome == null) return;
    if (outcome != ChallengeOutcome.netSuccess &&
        outcome != ChallengeOutcome.extendedSuccess) {
      return;
    }
    final profile = _capabilityProfile;
    if (profile == null) return;
    final double reached;
    switch (ch.kind) {
      case ChallengeAxisKind.duration:
        reached = (ch.targetThreshold +
                _challengeExtensionsCount * ch.extensionSeconds)
            .toDouble();
        break;
      case ChallengeAxisKind.bpm:
      case ChallengeAxisKind.depthCran:
        reached = ch.targetThreshold.toDouble();
        break;
    }
    final acquittable = milestoneService.milestonesAcquittableByChallenge(
      axis: ch.axis,
      reached: reached,
      profile: profile,
      acquiredUnlocks: _unlockedKeys,
    );
    for (final m in acquittable) {
      await milestoneService.markCompletedViaChallenge(m.id);
    }
  }

  /// Phase finale défis — consume la tête de la file showcase si la
  /// branche du défi de la séance matche. No-op hors carrière (pas de
  /// service) ou si le défi n'a pas tourné (`_activeChallenge == null`
  /// ou `_challengeOutcome == null`).
  Future<void> _consumeShowcaseIfMatched() async {
    final svc = _specializationService;
    if (svc == null) return;
    final ch = _activeChallenge;
    if (ch == null || _challengeOutcome == null) return;
    final branch = ch.branch;
    if (branch == null) return;
    final head = await svc.peekShowcase();
    if (head != branch) return;
    await svc.consumeShowcase(branch);
  }

  void _applyChallengeOutcome() {
    final outcome = _challengeOutcome;
    if (outcome == null) return;
    final extensions = _challengeExtensionsCount;
    // Phase 2 défi exploratoire : pas de bump de base humil/obed +2
    // (pas de seuil cible atteint, donc pas de palier mesuré).
    // Cf. spec § 5.2 — seules les extensions comptent.
    final isExploratory = _activeChallenge?.isExploratory ?? false;
    switch (outcome) {
      case ChallengeOutcome.netSuccess:
        if (!isExploratory) {
          _humiliation.onChallengeNetSuccess();
          _obedience.onChallengeNetSuccess();
        }
        break;
      case ChallengeOutcome.extendedSuccess:
        if (!isExploratory) {
          _humiliation.onChallengeNetSuccess();
          _obedience.onChallengeNetSuccess();
        }
        for (var i = 0; i < extensions; i++) {
          _humiliation.onChallengeExtension();
          _obedience.onChallengeExtension();
        }
        break;
      case ChallengeOutcome.fail:
        // Pas de bumps humil/obed (cf. spec § 5.3).
        break;
      case ChallengeOutcome.skipped:
        _obedience.onChallengeSkip();
        break;
    }
  }

  Future<void> _finish() async {
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    await _beep.stop();
    await WakelockPlus.disable();
    _flushHoldFull();
    _disarmHoldVerifier();
    // Profil de capacités : on clôt les streaks dès maintenant (la session
    // s'est terminée proprement) — le rapport est réutilisé plus bas pour le
    // commit ET sert tout de suite à détecter un record battu sur l'axe poussé
    // cette séance (Phase 4 : bump + éventuelle phrase coach). `_capabilityTracker`
    // est null hors carrière → `capReport == null`. `finalizeReport` est
    // idempotent (re-flush de valeurs déjà figées = max d'elles-mêmes).
    final capTracker = _capabilityTracker;
    final SessionCapabilityReport? capReport =
        (capTracker != null && !_released) ? capTracker.finalizeReport() : null;
    final CapabilityAxis? recordAxis = _detectCapabilityRecord(capReport);
    if (!_session.noStats) {
      await _stats.addElapsedSeconds(elapsedSeconds);
      await _stats.recordSessionCompleted(hadFail: _hadFailThisSession);
      // Recalcul intégré du score career d'humiliation : delta = α × sessionScore
      // + β_encore × encoresAsked − β_fail × failsCount + γ × clean. Remplace
      // les anciens bumps évènementiels qui touchaient directement le score
      // persisté (cf. modèle 2 thermomètres). encoresAsked compté = 0 ici :
      // l'encore est déclenché depuis l'écran finished APRÈS ce _finish.
      _humiliation.applyEndOfSessionDelta(
        clean: !_hadFailThisSession,
        encoresAsked: 0,
        failsCount: _hadFailThisSession ? 1 : 0,
      );
      if (!_hadFailThisSession) {
        _obedience.onSessionCleanFinish();
        // Phase 4 : record battu sur l'axe poussé cette séance → petit bump
        // permanent humiliation + obéissance (« l'exploit *est* une soumission
        // acceptée », §9). Posé dès qu'un record est détecté — c'est seulement
        // l'annonce vocale (en fin de _finish) qui est rare (∝ niveau). AVANT
        // les persistances `setObedienceLevel` / `setHumiliationLevel`.
        if (recordAxis != null) {
          _humiliation.bumpCareer(HumiliationEngine.bumpProgressRecord);
          _obedience.onCapabilityRecord();
        }
        // Compteurs des badges de fin de séance (Bouche pleine / Repeinte /
        // Gobeuse / Nettoyeuse / Suppliante). On crédite uniquement sur
        // sessions sans fail : si elle s'est plantée en cours de route, le
        // final qu'elle « aurait » joué ne compte pas pour la collection.
        final finalStep = _findFinalStep();
        final finalMode = finalStep?.mode;
        if (finalMode != null) {
          await _stats.recordFinalMode(finalMode);
        }
        final postFinalStep = _findPostFinalStep();
        final postFinalMode = postFinalStep?.mode;
        if (postFinalMode != null) {
          await _stats.recordPostFinalMode(postFinalMode);
        }
      }
      // Persiste l'obédiance (thermomètre lifetime). L'humiliation career
      // est persistée en tout fin de _finish (après les bonus milestones
      // éventuels) — éviter une double écriture.
      await _stats.setObedienceLevel(_obedience.score);
    }

    // Acquittement milestone AVANT le bascule en `finished` : sans ça,
    // `_recordCareerCompletion` côté SessionScreen (déclenché par le
    // notifyListeners de l'isFinished) appelle `recordSessionCompleted`
    // sur un `canLevelUp` qui retourne false (la milestone du niveau
    // courant est encore pending) → le niveau ne s'incrémente jamais.
    // Le bonus humiliation +2 d'unlock est appliqué ici, mais l'annonce
    // TTS est déplacée APRÈS le bascule (sinon notifyListeners attend la
    // fin de l'announce).
    String? milestoneAnnouncement;
    // Body milestone (insertion en milieu de séance) et final milestone
    // (placement `finalApotheose`, en remplacement de la phase finish)
    // sont acquittées indépendamment. Une seule annonce TTS est jouée
    // pour ne pas tasser deux phrases d'unlock en fin de séance — on
    // privilégie celle de la final si présente (= compétence terminale,
    // plus marquante dramaturgiquement).
    final newlyUnlocked = <LevelMilestone>[];
    Future<void> markIfPresent(String? id, {required bool isFinal}) async {
      if (id == null) return;
      final wasAlreadyCompleted = milestoneService.isCompleted(id);
      await milestoneService.markCompleted(id, hadFail: _hadFailThisSession);
      if (!_hadFailThisSession && !wasAlreadyCompleted && !_released) {
        final m = milestoneService.findById(id);
        if (m != null) newlyUnlocked.add(m);
        final announce = milestoneService.getUnlockAnnouncement(
          id,
          l10n: _appLocalizations,
        );
        if (announce != null && (isFinal || milestoneAnnouncement == null)) {
          milestoneAnnouncement = announce;
        }
        // Bonus permanent sur la career : compétence acquise = chauffe
        // permanente (pas un bump session jeté à la fin de la séance).
        _humiliation.bumpCareer(HumiliationEngine.bumpMilestoneAcquired);
      }
    }

    await markIfPresent(session.milestoneId, isFinal: false);
    await markIfPresent(session.secondMilestoneId, isFinal: false);
    await markIfPresent(session.finalMilestoneId, isFinal: true);
    _sessionMilestoneUnlocks = List<LevelMilestone>.unmodifiable(newlyUnlocked);

    // Phase 1 défis — applique les bumps humil/obed liés à l'outcome
    // (cf. spec § 5.2 / 5.3). Posé après les bonus milestone pour
    // s'additionner au careerScore avant la persistance ci-dessous.
    _applyChallengeOutcome();

    // Phase 3 défis — acquittement silencieux des milestones dont
    // `requiresCapability` matche l'axe du défi avec un seuil ≤ valeur
    // atteinte (cf. spec § 5.4). Pas d'annonce TTS, pas de bump milestone
    // (déjà compté par l'outcome). Idempotent : une milestone déjà
    // acquittée est ignorée.
    await _acquitMilestonesViaChallenge();

    // Phase finale défis — consume la tête de la file showcase si la
    // branche du défi de la séance matche. Toutes les voies de fin
    // honorent la dette (cf. spec § 5.1) : fail, succès net, succès
    // étendu, skipped, timeout. La joueuse a essayé sur la branche
    // fraîchement boostée — la dette est honorée peu importe l'outcome.
    await _consumeShowcaseIfMatched();
    if (!_session.noStats) {
      // Repersiste l'obédiance si elle a bougé via l'outcome défi
      // (le `setObedienceLevel` ci-dessus a été appelé AVANT
      // `_applyChallengeOutcome`).
      if (_challengeOutcome != null) {
        await _stats.setObedienceLevel(_obedience.score);
      }
      // Persiste le score career une fois pour toutes : delta de fin +
      // d'éventuels bonus milestone sont déjà incorporés.
      await _stats.setHumiliationLevel(_humiliation.careerScore);

      // Réconciliation badges AVANT le bascule en `finished` : `_FinishedPanel`
      // initialise son `_badgesHidden` à partir de `hasPendingBadges` au
      // premier rendu. Si `_pendingBadgeUnlocks` est encore vide à ce
      // moment-là, le panel skippe l'étape MERCI et les badges ne sont
      // jamais révélés. On résout la liste avant le notifyListeners.
      final snap = await _stats.snapshot();
      final unlocks = await _badges.reconcileAndDetectUnlocks(snap);
      _pendingBadgeUnlocks = unlocks;

      // Profil de capacités : persiste le rapport clôturé plus haut.
      // `sessionIndex` = nombre de sessions complétées (déjà incrémenté par
      // `recordSessionCompleted`) → horloge de decay du `CapabilityRegulator`.
      // Renvoie l'axe imputé du tap-out — ignoré ici (le `tapout` a déjà été
      // attribué live pour la phrase coach ; l'attribution de `commit` ne sert
      // qu'au ratchet ↓).
      if (capReport != null && !capReport.isEmpty) {
        await _capabilities.commit(capReport,
            sessionIndex: snap.sessionsCompleted, quickie: _isQuickie);
      }
    }

    // Apothéose AVANT le bascule en `finished`. Deux cas :
    //
    // 1. **Step final dédié (carrière)** : `_finalChimePlayed` est déjà à
    //    true parce que `_checkSteps` a déclenché le chime PENDANT le step
    //    final (avec sa phrase d'action « ouvre ta bouche / avale tout »).
    //    On skippe ce bloc — le post-final qui a suivi a déjà refermé la
    //    séance avec son compliment doux.
    //
    // 2. **Sessions hors carrière** (ou carrière sans `finalStepTime`) :
    //    fallback historique — phrase `finale` (« voilà je jouis ») +
    //    chime joués ici, avant le bascule. Bloque le rendu du panel le
    //    temps de l'apothéose.
    if (!_hadFailThisSession && !_released && !_finalChimePlayed) {
      final finalStep = _findFinalStep();
      final mode = finalStep?.mode;
      final bank = _phraseBank;
      if (mode != null && bank != null) {
        final phrase = bank.pickFor(mode, 'finale', _random);
        if (phrase.isNotEmpty) {
          await _tts.speak(phrase);
        }
      }
      if (!_released) {
        await _beep.playFinaleChime(category: session.finalCategory);
        _finalChimePlayed = true;
      }
    }

    _state = SessionState.finished;
    notifyListeners();

    // Annonce TTS d'unlock milestone (post-bascule pour ne pas bloquer
    // le rendu du finished panel sur l'await). Joue après le chime :
    // phrase finale → son d'orgasme → panel de fin → annonce de la
    // compétence acquise.
    final announce = milestoneAnnouncement;
    if (announce != null && announce.isNotEmpty) {
      await _tts.speak(announce);
    } else if (recordAxis != null &&
        _phraseBank != null &&
        !_released &&
        _random.nextDouble() <
            CapabilityRegulator.progressPhraseChanceForLevel(_careerLevel)) {
      // Phase 4 — phrase `record` parcimonieuse : seulement s'il n'y a pas eu
      // d'annonce milestone cette séance (on n'empile pas deux annonces de fin)
      // et avec une chance ∝ niveau (« record » pas systématiquement annoncé,
      // §9). Même placement que l'annonce milestone : après le chime + le panel.
      final phrase = _phraseBank.pickProgressPhrase(
          recordAxis.storageKey, 'record', _random);
      if (phrase != null && phrase.isNotEmpty) {
        await _tts.speak(phrase);
      }
    }
  }

  /// Retourne le step final / apothéose. Identifié via
  /// `Session.finalStepTime` (= moment où le `finale_chime` retentit) si
  /// renseigné. Sinon (sessions hors carrière), fallback sur le dernier
  /// step de config — comportement historique.
  SessionStep? _findFinalStep() {
    final finalT = session.finalStepTime;
    if (finalT != null) {
      for (final s in session.steps) {
        if (!s.isTextOnly && s.time == finalT) return s;
      }
    }
    for (var i = session.steps.length - 1; i >= 0; i--) {
      final s = session.steps[i];
      if (!s.isTextOnly) return s;
    }
    return null;
  }

  /// Retourne le step de **post-final** = action douce qui suit l'orgasme.
  /// Recherché comme le premier step de config dont `time > finalStepTime`.
  /// Renvoie null si pas de step final défini ou si aucun step de config
  /// ne suit (sessions hors carrière, ou final milestone qui n'a pas de
  /// post-final dédié).
  SessionStep? _findPostFinalStep() {
    final finalT = session.finalStepTime;
    if (finalT == null) return null;
    for (final s in session.steps) {
      if (s.isTextOnly) continue;
      if (s.time > finalT) return s;
    }
    return null;
  }

  /// Phrase `tapout` du coach (Phase 4) si le « je peux pas » est imputable à
  /// un axe poussé au-delà de sa zone de confort (§6), avec une chance ∝ niveau.
  /// Suppose `CapabilityTracker.onFail()` déjà appelé (les `sessionCeilings`
  /// sont à jour). `null` = pas de phrase dédiée → l'appelant retombe sur le
  /// tirage de fail standard.
  String? _tapoutPhraseOrNull() {
    final tracker = _capabilityTracker;
    final profile = _capabilityProfile;
    final bank = _phraseBank;
    if (tracker == null || profile == null || bank == null) return null;
    final axis =
        CapabilityRegulator.attributeTapOut(tracker.sessionCeilings, profile);
    if (axis == null) return null;
    if (_random.nextDouble() >=
        CapabilityRegulator.progressPhraseChanceForLevel(_careerLevel)) {
      return null;
    }
    final phrase = bank.pickProgressPhrase(axis.storageKey, 'tapout', _random);
    return (phrase != null && phrase.isNotEmpty) ? phrase : null;
  }

  /// Détecte si la séance vient de battre le `best` de l'axe poussé cette
  /// séance (`_capabilityOverloadAxis`, axe pilotant `maximize`) en comparant
  /// `reached` au snapshot pré-séance. Renvoie l'axe en cas de record propre,
  /// `null` sinon — pas d'axe surchargé, pas d'amélioration, ou séance avec un
  /// « je peux pas » (on ne célèbre pas un record juste après un tap-out, §9 ;
  /// le `best` reste enregistré par `CapabilityService.commit` quoi qu'il arrive).
  CapabilityAxis? _detectCapabilityRecord(SessionCapabilityReport? report) {
    if (report == null || _hadFailThisSession) return null;
    final axis = _capabilityOverloadAxis;
    final profile = _capabilityProfile;
    if (axis == null || profile == null) return null;
    if (!axis.pilotant || axis.recordKind != CapabilityRecordKind.maximize) {
      return null;
    }
    final reached = report.reached[axis];
    if (reached == null) return null;
    final before = profile.bestOf(axis);
    return (before == null || reached > before) ? axis : null;
  }

  /// Liste des paliers nouvellement franchis, calculée par `_finish` mais
  /// gardée en attente jusqu'à `revealBadgeUnlocks()`. On préserve la
  /// même API publique (`sessionBadgeUnlocks`) une fois la révélation
  /// faite, pour que l'UI continue de pouvoir consommer la liste.
  List<BadgeUnlock> _pendingBadgeUnlocks = const [];

  /// True si des badges ont été détectés à la complétion mais pas encore
  /// révélés (l'utilisateur n'a pas tapé MERCI). Permet à l'UI d'afficher
  /// le bouton MERCI avant la grille de badges.
  bool get hasPendingBadges => _pendingBadgeUnlocks.isNotEmpty;

  /// Révèle les paliers de badges atteints pendant la séance : déplace la
  /// liste pending vers `sessionBadgeUnlocks`, lance les annonces TTS, et
  /// notifie l'UI. À appeler depuis le bouton MERCI de l'écran de fin.
  /// La phrase TTS est localisée via [_appLocalizations] (poussé depuis
  /// l'UI par [setAppLocalizations]) ; si la locale n'a pas encore été
  /// poussée (cas anormal — l'UI le fait au start de la séance), on
  /// révèle les badges côté UI mais on n'annonce pas TTS.
  Future<void> revealBadgeUnlocks() async {
    if (_pendingBadgeUnlocks.isEmpty) return;
    final unlocks = _pendingBadgeUnlocks;
    _pendingBadgeUnlocks = const [];
    _sessionBadgeUnlocks = unlocks;
    notifyListeners();
    final l10n = _appLocalizations;
    if (l10n == null) return;
    for (final u in unlocks) {
      if (_released) break;
      await _tts.speak(u.announcement(l10n));
    }
  }

  // ─── Action « Supplier » (mode Carrière) ───────────────────────────────

  /// Coupe la timeline restante et la remplace par : un beg insistant
  /// immédiat (à `elapsedSeconds`), suivi des [upcomingSteps] rebased
  /// pour démarrer juste après le beg. Utilisé par le bouton « SUPPLIER »
  /// du mode Carrière, qui régénère une suite à un niveau supérieur
  /// pendant que l'utilisateur supplie.
  ///
  /// Les `upcomingSteps` doivent avoir leur `time` exprimé relativement
  /// à zéro (le générateur produit toujours un `time` croissant à partir
  /// de 0) — la méthode rebase elle-même.
  Future<void> requestUpgrade({
    required SessionStep insistentBeg,
    required Session upcomingSession,
  }) async {
    if (_state != SessionState.running) return;

    final start = elapsedSeconds;
    final begDuration = insistentBeg.duration ?? 12;
    final offset = start + begDuration;

    final newSteps = <SessionStep>[
      SessionStep(
        time: start,
        text: insistentBeg.text,
        mode: insistentBeg.mode,
        from: insistentBeg.from,
        to: insistentBeg.to,
        bpm: insistentBeg.bpm,
        duration: begDuration,
      ),
      ...upcomingSession.steps.map(
        (s) => SessionStep(
          time: s.time + offset,
          text: s.text,
          mode: s.mode,
          from: s.from,
          to: s.to,
          bpm: s.bpm,
          duration: s.duration,
        ),
      ),
    ];

    // Décale les timestamps de fin (finalStep / silentFinish) du regen pour
    // qu'ils tombent sur les bons steps du nouveau `_session`. Sans ça, le
    // contrôleur ne reconnaît pas le step final → le `finale_chime` est
    // joué via le fallback de `_finish` ET la phrase finale est rejouée
    // (« voilà je jouis » + chime APRÈS la phrase d'action déjà speakée du
    // step final). Doublait l'apothéose à chaque Supplier.
    final upFinalStepTime = upcomingSession.finalStepTime;
    final upSilentFinish = upcomingSession.silentFinishStartTime;

    _session = Session(
      id: '${_session.id}:upgraded',
      name: _session.name,
      description: _session.description,
      durationSeconds: offset + upcomingSession.durationSeconds,
      defaultMode: _session.defaultMode,
      steps: newSteps,
      finalStepTime: upFinalStepTime != null ? upFinalStepTime + offset : null,
      silentFinishStartTime:
          upSilentFinish != null ? upSilentFinish + offset : null,
      finalCategory: upcomingSession.finalCategory,
      noStats: _session.noStats,
    );

    // Coupe le TTS en cours pour ne pas garder une phrase orpheline
    // de l'ancien step. Le beg insistant va parler tout de suite.
    await _tts.stop();

    _nextStepIndex = 0;
    _lastConfigStep = null;
    // Reset du flag chime : la régen apporte son propre step final +
    // apothéose. Si l'ancienne session avait déjà tiré son chime (cas
    // rare où Supplier est cliqué pile entre final et fin), on doit
    // pouvoir rejouer le chime de la nouvelle.
    _finalChimePlayed = false;
    _finaleChimeStarted = false;

    // Force le déclenchement immédiat du beg (time = start ≤ elapsedSeconds).
    _checkSteps();
    notifyListeners();
  }

  // ─── Flow FAIL ─────────────────────────────────────────────────────────

  /// Déclenche la séquence : pause → phrase fail → respiration → punition →
  /// reprise du loop session là où il était.
  ///
  /// Le bouton appelant doit vérifier [canTriggerFail] pour ne pas appeler
  /// cette méthode hors d'un état running.
  Future<void> triggerFail() async {
    if (!canTriggerFail) return;

    // Phase 1 défis — repurposage du bouton FAIL pendant la fenêtre défi
    // (cf. spec § 4.4) : pendant le breath de countdown = `PASSE` ; avant
    // le seuil = fail défi (pas de flow punition complet) ; après le seuil
    // = `JE M'ARRÊTE`. Aucun cas ne tombe dans le flow fail standard.
    if (isChallengeActive) {
      // Phase 2 défi exploratoire : pas de notion d'échec (spec § 4.4),
      // tap-out avant le seuil initial estimé = `JE M'ARRÊTE`. Le best
      // capturé est la durée tenue (= elapsed dans le step, < seuil).
      final isExploratory = _activeChallenge?.isExploratory ?? false;
      switch (_challengePhase) {
        case ChallengePhase.breath:
        case ChallengePhase.countdown:
          // Bouton FAIL pendant breath ou countdown = équivalent PASSE
          // (la joueuse n'a pas encore commencé le défi).
          _completeChallenge(ChallengeOutcome.skipped);
          return;
        case ChallengePhase.live:
        case ChallengePhase.preExtend:
          if (isExploratory) {
            _completeChallenge(ChallengeOutcome.netSuccess);
            return;
          }
          _capabilityTracker?.onFail();
          _completeChallenge(ChallengeOutcome.fail);
          return;
        case ChallengePhase.atSeuil:
        case ChallengePhase.openExtension:
          triggerChallengeStop();
          return;
        case ChallengePhase.none:
        case ChallengePhase.ended:
          break;
      }
    }

    // Retry milestone : si on rate dans la fenêtre pédagogique, on tente
    // d'abord de proposer une nouvelle tentative via le callback (qui
    // regénère + appelle requestUpgrade). Si le callback prend la main,
    // on saute entièrement le flow fail standard — pas de pénalités, pas
    // de phrase fail, pas de punition. La milestone est juste rejouée.
    //
    // Le profil de capacités, lui, voit ce fail : on fige les plafonds de
    // session AVANT le callback pour que la régénération du retry lise des
    // `capabilitySessionCeilings` à jour. `onFail` est idempotent (streaks
    // remis à 0), donc le ré-appel du flow standard plus bas (cas retry non
    // pris en charge) est sans effet.
    if (_isInMilestoneWindow() && onMilestoneRetry != null) {
      _capabilityTracker?.onFail();
      final handled = await onMilestoneRetry!(this);
      if (handled) return;
    }

    // Cas particulier : on est déjà dans le flow fail, en pleine punition
    // → on abandonne la punition (malus obéissance, pas de re-punition).
    if (_state == SessionState.failing && _failPhase == FailPhase.punishment) {
      _abandonPunishment();
      return;
    }

    _failActive = true;
    final myGen = ++_failGen;
    _hadFailThisSession = true;
    _stamina.onFail();
    _saliva.onFail();
    // Capacités : fige les plafonds de session sur la valeur live des
    // streaks, puis les vide — un streak interrompu par un fail ne devient
    // jamais un record propre (cf. §3/§6 de la spec).
    _capabilityTracker?.onFail();
    // Le mode forbidden est levé par le fail : la salope a craqué, on
    // repart sur des bases neutres. Si la session veut re-imposer le
    // forbidden après reprise, c'est au scénario de poser un step le
    // demandant explicitement.
    _swallowMode = SwallowMode.allowed;
    // Pénalités amplifiées si on craque dans la dernière minute (la
    // session est presque terminée — c'est ruiné). Cumulable avec ×2 si
    // une milestone candidate au niveau courant était présente et n'a pas
    // été acquittée : « tu pouvais avancer, tu as raté ». Au pire ×4.
    final lastMinuteMul = _isInLastMinute() ? 2.0 : 1.0;
    final missedMilestone = _milestoneOpportunityMissed();
    _obedience.onFail(
      multiplier: lastMinuteMul,
      milestoneOpportunityMissed: missedMilestone,
    );
    _humiliation.onFail(
      multiplier: lastMinuteMul,
      milestoneOpportunityMissed: missedMilestone,
    );
    _punishmentAbandoned = false;
    // Le hold full en cours est interrompu : pas de crédit Iron Lungs.
    _currentHoldFullDuration = 0;
    // Le hold éventuellement en cours est interrompu — disarm la caméra
    // pour ne pas spammer de rappels pendant la phrase de fail / breath.
    _disarmHoldVerifier();

    // 1) Mise en pause du timing principal et du loop courant.
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    await _tts.stop();
    await _beep.pause();

    _state = SessionState.failing;

    try {
      // 2) Phrase de fail.
      _failPhase = FailPhase.phrase;
      // On résout immédiatement : le contenu stocké dans `_currentFailPhrase`
      // est la version affichable (sans `{name}`). Le speak qui suit est
      // alors un pass-through pour le placeholder déjà absent.
      // Si la salope a avalé alors que c'était interdit, on tire dans le
      // pool dédié `failPhrasesSwallow` (transgression de consigne) plutôt
      // que dans le pool générique. Fallback transparent au pool standard
      // si le pool dédié est vide (sécurité contre un JSON incomplet).
      final swallowPool = _punishmentBundle.failPhrasesSwallow;
      final usingSwallowPool =
          _swallowMode == SwallowMode.forbidden && swallowPool.isNotEmpty;
      final pool =
          usingSwallowPool ? swallowPool : _punishmentBundle.failPhrases;
      // Phase 4 — coach audible : si le « je peux pas » est imputable à un axe
      // poussé au-delà de sa zone de confort (§6, attribution non ambiguë grâce
      // à la surcharge isolée) et que le dé ∝ niveau tombe juste, on remplace la
      // phrase de fail standard par une variante DOUCE « limite reconnue » (tier
      // `tapout`). Jamais sur le pool « avalement interdit transgressé »
      // (indiscipline ≠ limite légitime).
      final tapoutPhrase = usingSwallowPool ? null : _tapoutPhraseOrNull();
      final raw = tapoutPhrase ?? _pickRandom(pool);
      _currentFailPhrase = raw == null ? null : _tts.resolveText(raw);
      notifyListeners();
      if (_currentFailPhrase != null) {
        // awaitSpeakCompletion(true) → ce await retourne quand la phrase
        // est entièrement prononcée.
        _lastScriptedSpeakAt = DateTime.now();
        await _tts.speak(_currentFailPhrase!);
      }
      if (!_isFailFlowAlive(myGen)) return;

      // 3) Respiration : toujours présente comme phase de transition,
      //    mais raccourcie quand l'endurance projetée à l'instant t est
      //    confortable (pas besoin d'imposer une longue récup à
      //    quelqu'une qui n'en a pas besoin).
      _failPhase = FailPhase.breath;
      notifyListeners();
      final stamina = _staminaAtNow();
      final isFresh = stamina != null && stamina > _breathSkipStaminaThreshold;
      final breathSeconds =
          isFresh ? (3 + _random.nextInt(3)) : (8 + _random.nextInt(8));
      await _beep.applyStep(
        SessionStep(
          time: 0,
          mode: SessionMode.breath,
          duration: breathSeconds,
        ),
        session.defaultMode,
      );
      await _syncAmbienceToCurrentMode();
      await _waitInterruptible(Duration(seconds: breathSeconds), gen: myGen);
      if (!_isFailFlowAlive(myGen)) return;

      // 4) Punition. En carrière, on génère une composition contextuelle
      //    bornée par le profil de capacités (§7 — Phase 5). Hors carrière
      //    (Custom, scénarios JSON), on retombe sur le tirage statique dans
      //    `punishments.json` — comportement historique.
      _currentPunishment = _generateCareerPunishmentOrNull() ??
          _pickRandom(_punishmentBundle.punishments);
      _failPhase = FailPhase.punishment;
      notifyListeners();
      if (_currentPunishment != null) {
        await _runPunishment(_currentPunishment!);
        // Bonus seulement si la punition a été menée à terme (ni stop()
        // global, ni abandon volontaire via le bouton FAIL).
        if (_isFailFlowAlive(myGen) && !_punishmentAbandoned) {
          _humiliation.onPunishmentCompleted();
          _obedience.onPunishmentCompleted();
        }
      }
      if (!_isFailFlowAlive(myGen)) return;

      // 5) Saut à la section suivante : on cherche le prochain step de
      //    config et on avance la timeline jusqu'à son `time`. Tous les
      //    steps text-only intermédiaires sont consommés silencieusement.
      //    Si aucune section suivante n'existe, on restaure le loop d'avant
      //    le fail pour ne pas laisser la séance sans audio.
      final jumped = _skipToNextSection();
      if (!jumped) {
        await _restorePreviousLoop();
      }

      _stopwatch.start();
      _startTicker();
      _startRandomComments();
      _state = SessionState.running;
      // Coup de pouce immédiat : si on a sauté pile sur le `time` du
      // prochain step, on le déclenche tout de suite plutôt que d'attendre
      // le prochain tick (200 ms d'écart audible sinon).
      _checkSteps();
    } finally {
      // Ne nettoie le state global que si on est toujours owner du flow —
      // sinon on écraserait celui d'un nouveau triggerFail qui aurait pris
      // la main pendant l'un de nos awaits.
      if (_failGen == myGen) {
        _failPhase = null;
        _currentFailPhrase = null;
        _currentPunishment = null;
        _failActive = false;
        notifyListeners();
      }
    }
  }

  /// Joue toutes les étapes d'une punition selon leur `time` relatif,
  /// jusqu'à atteindre [Punishment.durationSeconds]. Interruptible via
  /// `_abandonPunishment()` (qui complète `_punishmentCompleter`).
  Future<void> _runPunishment(Punishment p) async {
    // Refuse les appels concurrents : si un précédent est encore actif,
    // c'est un état incohérent (les flows fail/mini-punition s'attendent
    // tous via await). On ne ré-entre pas ; le caller verra un retour
    // immédiat et la séquence en cours continuera son cycle.
    final previous = _punishmentCompleter;
    if (previous != null && !previous.isCompleted) {
      if (kDebugMode) {
        debugPrint(
            '[SessionController] _runPunishment ignoré : précédent encore actif');
      }
      return;
    }
    // Annule un ticker éventuellement orphelin pour ne pas le superposer.
    _punishmentTicker?.cancel();
    _punishmentTicker = null;

    final completer = Completer<void>();
    _punishmentCompleter = completer;
    final stopwatch = Stopwatch()..start();
    var nextIdx = 0;

    void tick() {
      // Si on n'est plus le completer en cours (un nouveau _runPunishment
      // a démarré), on stoppe ce tick fantôme sans toucher au state global.
      if (_punishmentCompleter != completer) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (!_failActive) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final s = stopwatch.elapsed.inSeconds;
      var modeChanged = false;
      while (nextIdx < p.steps.length && p.steps[nextIdx].time <= s) {
        final step = p.steps[nextIdx];
        if (!step.isTextOnly) {
          _beep.applyStep(step, session.defaultMode);
          modeChanged = true;
        }
        if (step.text.isNotEmpty) {
          // fire-and-forget — flutter_tts file les phrases consécutives
          _speakScripted(step.text);
        }
        nextIdx++;
      }
      if (modeChanged) {
        _syncAmbienceToCurrentMode();
      }

      if (s >= p.durationSeconds) {
        _punishmentTicker?.cancel();
        _punishmentTicker = null;
        stopwatch.stop();
        if (!completer.isCompleted) completer.complete();
      }
    }

    tick(); // déclenche le step à t=0 sans attendre
    _punishmentTicker = Timer.periodic(_tickInterval, (_) => tick());

    await completer.future;
    // Ne nille le champ que si on est toujours owner (sinon on écraserait
    // la référence d'un appelant suivant qui aurait pris la main).
    if (_punishmentCompleter == completer) {
      _punishmentCompleter = null;
    }
    await _beep.stop(); // coupe les bips de la punition avant de continuer
  }

  /// Interrompt la punition en cours (déclenché par un appui sur FAIL
  /// pendant la phase punishment). Pénalité d'obéissance, pas de
  /// re-punition pour éviter la spirale.
  void _abandonPunishment() {
    _punishmentAbandoned = true;
    final mul = _isInLastMinute() ? 2.0 : 1.0;
    _obedience.onPunishmentAbandoned(multiplier: mul);
    _humiliation.onPunishmentAbandoned(multiplier: mul);
    _punishmentTicker?.cancel();
    _punishmentTicker = null;
    final c = _punishmentCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  /// Tick mini-punition : 1 tirage par minute. Si le coach a un
  /// `miniPunishmentRate` > 0 et que l'état autorise une mini-punition (pas
  /// en milestone, pas dernière minute, pas en finish), tente de déclencher
  /// `_runMiniPunishmentFlow`. Pas de garde sur `_state == running` ici
  /// — `_accrueHoldSecond` ne s'appelle que sous le ticker, qui ne tourne
  /// que pendant `running`.
  void _accrueMiniPunishmentTick() {
    _miniPunishmentTickAccumulator++;
    if (_miniPunishmentTickAccumulator < 60) return;
    _miniPunishmentTickAccumulator = 0;
    if (_miniPunishmentRate <= 0) return;
    if (_isInMilestoneWindow()) return;
    if (_isInLastMinute()) return;
    final shouldFire = computeMiniPunishmentTrigger(
      rate: _miniPunishmentRate,
      rngValue: _miniPunishmentRng.nextDouble(),
    );
    if (!shouldFire) return;
    final shortPool = _punishmentBundle.punishments
        .where((p) => p.durationSeconds < 20)
        .toList();
    if (shortPool.isEmpty) return;
    final p = shortPool[_miniPunishmentRng.nextInt(shortPool.length)];
    _miniPunishmentsTriggered++;
    // Fire-and-forget : on ne bloque pas le ticker.
    unawaited(_runMiniPunishmentFlow(p));
  }

  /// Joue une mini-punition inopinée déclenchée par le tick coach.
  /// Variante allégée du flow fail : pas de phrase fail, pas de breath de
  /// récup, pas de saut de section. On enchaîne directement la punition
  /// puis on restaure le loop précédent.
  Future<void> _runMiniPunishmentFlow(Punishment p) async {
    if (_state != SessionState.running) return;

    _failActive = true;
    final myGen = ++_failGen;
    _disarmHoldVerifier();
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    await _tts.stop();
    await _beep.pause();

    _state = SessionState.failing;
    _failPhase = FailPhase.punishment;
    _currentPunishment = p;
    notifyListeners();

    try {
      await _runPunishment(p);
      if (_isFailFlowAlive(myGen) && !_punishmentAbandoned) {
        _humiliation.onPunishmentCompleted();
        _obedience.onPunishmentCompleted();
      }
      if (!_isFailFlowAlive(myGen)) return;
      await _restorePreviousLoop();
      _stopwatch.start();
      _startTicker();
      _startRandomComments();
      _state = SessionState.running;
      _checkSteps();
    } finally {
      if (_failGen == myGen) {
        _failPhase = null;
        _currentPunishment = null;
        _punishmentAbandoned = false;
        _failActive = false;
        notifyListeners();
      }
    }
  }

  /// Génère une punition carrière contextuelle (Phase 5, §7) via
  /// `CareerSessionGenerator.generatePunishment`. Renvoie `null` hors
  /// carrière (pas de profil de capacités ou pas de banque coach) — le
  /// caller retombe alors sur le tirage statique dans `punishments.json`.
  ///
  /// On reconstruit un générateur à la volée (pas d'état conservé entre
  /// fails) : la classe est suffisamment légère, le `Random()` interne
  /// suffit pour la variation et on évite de propager une référence partagée
  /// avec la chaîne de génération de session principale.
  Punishment? _generateCareerPunishmentOrNull() {
    final profile = _capabilityProfile;
    final bank = _phraseBank;
    if (profile == null || bank == null) return null;
    final generator = CareerSessionGenerator();
    return generator.generatePunishment(
      level: _careerLevel,
      bank: bank,
      unlockedKeys: _unlockedKeys,
      capability: CapabilityInputs(
        profile: profile,
        sessionCeilings: _capabilityTracker?.sessionCeilings ?? const {},
        overloadAxis: _capabilityOverloadAxis,
      ),
      specialization: _specialization,
      humiliationCareer: _humiliation.careerScore,
      humiliationSession: _humiliation.sessionScore,
      obedience: _obedience.score,
      includeHand: _includeHand,
    );
  }

  /// Restaure le loop de bips qui tournait avant le fail (ou no-op
  /// si aucune étape de config n'avait encore été appliquée).
  Future<void> _restorePreviousLoop() async {
    final last = _lastConfigStep;
    if (last == null) return;
    await _beep.applyStep(last, session.defaultMode);
    _capabilityTracker?.onStepApplied(
      mode: last.mode ?? session.defaultMode,
      from: last.from,
      to: last.to,
      bpm: last.bpm,
      duration: last.duration,
    );
    await _syncAmbienceToCurrentMode();
  }

  /// Cherche la prochaine étape avec configuration de bip (i.e. le début
  /// d'une nouvelle « section ») strictement après [elapsedSeconds]. Si
  /// trouvée, avance [_timelineOffset] pour faire correspondre l'horloge
  /// effective à son `time`, et place [_nextStepIndex] dessus. Les éventuels
  /// steps text-only entre la position courante et la nouvelle section
  /// sont sautés silencieusement.
  ///
  /// Retourne true si un saut a eu lieu, false si on est déjà dans la
  /// dernière section (pas de saut effectué).
  bool _skipToNextSection() {
    final currentSec = elapsedSeconds;
    for (var i = _nextStepIndex; i < session.steps.length; i++) {
      final step = session.steps[i];
      if (!step.isTextOnly && step.time > currentSec) {
        final delta = step.time - currentSec;
        _timelineOffset += Duration(seconds: delta);
        _nextStepIndex = i;
        return true;
      }
    }
    return false;
  }

  /// Délai annulable : si [_failActive] passe à false pendant l'attente
  /// — ou si la génération a changé (un nouveau flow fail nous a remplacés)
  /// — on retourne immédiatement.
  Future<void> _waitInterruptible(Duration total, {required int gen}) async {
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < total) {
      if (!_isFailFlowAlive(gen)) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  T? _pickRandom<T>(List<T> items) {
    if (items.isEmpty) return null;
    return items[_random.nextInt(items.length)];
  }

  // ─── Scheduler des commentaires aléatoires ─────────────────────────────

  /// Programme le prochain commentaire aléatoire dans [min, max] secondes.
  /// Idempotent : annule un éventuel timer existant avant d'en poser un nouveau.
  void _startRandomComments() {
    _randomCommentTimer?.cancel();
    if (_randomComments.isEmpty) return;
    _randomCommentTimer = Timer(_nextRandomDelay(), _fireRandomComment);
  }

  void _stopRandomComments() {
    _randomCommentTimer?.cancel();
    _randomCommentTimer = null;
  }

  Duration _nextRandomDelay() {
    final min = _randomComments.minIntervalSeconds;
    final max = _randomComments.maxIntervalSeconds;
    final spread = (max - min).clamp(0, 3600);
    final seconds = min + (spread > 0 ? _random.nextInt(spread + 1) : 0);
    return Duration(seconds: seconds);
  }

  /// Joue un commentaire aléatoire si l'état le permet, puis reprogramme
  /// le suivant. On reporte le commentaire si :
  /// - le TTS est déjà en train de parler (sinon le nouveau speak()
  ///   interrompt la phrase scriptée en cours via QUEUE_FLUSH) ;
  /// - une phrase scriptée vient juste d'être dite (cooldown de courtoisie).
  void _fireRandomComment() {
    if (_state != SessionState.running) return;
    if (_randomComments.isEmpty) return;

    // Pas de random pendant la fenêtre finish (boosts + final + chime) :
    // les phrases scriptées de cette phase (« continue je viens », phrase
    // finale, annonce milestone) ne doivent pas être chevauchées par un
    // commentaire random. La fenêtre est ouverte par le générateur via
    // `Session.silentFinishStartTime`. On stoppe carrément le scheduler
    // au lieu de re-Timer : plus rien ne joue jusqu'au _finish.
    final silentStart = session.silentFinishStartTime;
    if (silentStart != null && elapsedSeconds >= silentStart) {
      _stopRandomComments();
      return;
    }

    // Pas de random pendant la fenêtre milestone : la séquence pédagogique
    // enchaîne ses propres `text` scriptés et un random venant par-dessus
    // briserait la dramaturgie de l'apprentissage. On reporte de 3 s plutôt
    // que de stopper : la fenêtre se referme d'elle-même quand la milestone
    // se termine, le scheduler reprend naturellement.
    if (_isInMilestoneWindow()) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 3), _fireRandomComment);
      return;
    }

    // Pas de random pendant beg / breath : ces modes sont vocaux ou
    // respiratoires, l'utilisatrice doit pouvoir se concentrer sur la
    // consigne scriptée sans qu'un commentaire random vienne par-dessus.
    final mode = _beep.currentMode;
    if (mode == SessionMode.beg || mode == SessionMode.breath) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 3), _fireRandomComment);
      return;
    }

    if (_tts.isSpeaking) {
      // TTS occupé : on retentera dans 2s pour ne pas couper la phrase
      // en cours.
      _randomCommentTimer =
          Timer(const Duration(seconds: 2), _fireRandomComment);
      return;
    }

    final since = DateTime.now().difference(_lastScriptedSpeakAt).inSeconds;
    final cooldown = _randomComments.scriptedCooldownSeconds;
    if (since < cooldown) {
      _randomCommentTimer = Timer(
        Duration(seconds: cooldown - since + 1),
        _fireRandomComment,
      );
      return;
    }

    // Tirage contextualisé : on filtre sur le mode/BPM/profondeur courants.
    // Les phrases scopées par `requires_unlock` (ex. pool sloppy_drool_basic)
    // ne sortent que si la compétence est acquise — donne à la joueuse un
    // retour audible de ses milestones sans toucher au reste du gameplay.
    // Si aucune phrase ne match le contexte, fallback sur les phrases
    // applicables partout (toujours filtrées par requires_unlock).
    final unlockedKeys =
        milestoneService.acquiredUnlockKeys().map((k) => k.serialized).toSet();
    final phrase = _randomComments.pickFor(
      mode: _beep.currentMode,
      bpm: _beep.currentBpm,
      depth: _beep.currentTo ?? _beep.currentFrom,
      saliva: _saliva.ratio,
      rng: _random,
      unlockedKeys: unlockedKeys,
    );
    if (phrase != null) _tts.speak(phrase);

    _randomCommentTimer = Timer(_nextRandomDelay(), _fireRandomComment);
  }

  // ─── Disposal ──────────────────────────────────────────────────────────

  /// Détache le controller des services audio partagés (TTS, BeepEngine,
  /// AmbienceEngine). À appeler avant qu'une *autre* SessionScreen prenne
  /// la main (typiquement le bouton « J'en veux encore »).
  ///
  /// Sans ça, le `dispose()` de l'ancien controller — déclenché par le
  /// `pushReplacement` — fait un `_tts.stop()` / `_beep.stop()` en
  /// fire-and-forget qui résout APRÈS le `start()` du nouveau controller,
  /// et coupe la première phrase TTS + le loop de bips qui viennent juste
  /// d'être lancés (race condition observée sur le bouton encore).
  ///
  /// Cette méthode :
  ///  1. Coupe les timers locaux (ticker, fail, random comments).
  ///  2. Awaité le `_tts.stop()` pour interrompre proprement une éventuelle
  ///     annonce de badge en cours, AVANT que le nouveau controller parle.
  ///  3. Marque le controller comme « released » pour que `dispose()`
  ///     (qui partira ensuite, hors de notre contrôle) ne re-stoppe pas
  ///     les services partagés.
  Future<void> detachAudio() async {
    _released = true;
    _failActive = false;
    _punishmentTicker?.cancel();
    _randomCommentTimer?.cancel();
    _ticker?.cancel();
    _stopwatch.stop();
    await _tts.stop();
  }

  @override
  void dispose() {
    // Marquer released avant tout : les awaits encore en vol dans _finish,
    // triggerFail, _runPunishment, etc. testent ce flag avant de relancer
    // un speak/beep et court-circuitent proprement.
    final wasAlreadyReleased = _released;
    _released = true;
    _failActive = false;
    _punishmentTicker?.cancel();
    _randomCommentTimer?.cancel();
    _ticker?.cancel();
    _stopwatch.stop();
    if (!wasAlreadyReleased) {
      // Chaînage séquentiel : si l'écran est démonté juste avant qu'un
      // nouveau controller prenne la main (cas pushReplacement non capturé
      // par detachAudio), on laisse le _tts.stop() finir avant le beep et
      // l'ambience pour éviter une rafale de stops parallèles dont l'ordre
      // résolu peut couper le speak/beep du nouveau controller.
      unawaited(() async {
        try {
          await _tts.stop();
          await _beep.stop();
          await _ambience.stop();
        } catch (_) {}
      }());
      WakelockPlus.disable();
    }
    super.dispose();
  }
}
