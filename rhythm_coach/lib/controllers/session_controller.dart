import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../career/models/career_generation_inputs.dart';
import '../career/models/challenge.dart';
import '../career/models/level_milestone.dart';
import '../career/models/phrase_bank.dart';
import '../career/services/challenges/challenge_segment_builder.dart';
import '../career/services/generation/career_session_generator.dart';
import '../career/services/specialization_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show milestoneService;
import '../models/punishment.dart';
import '../models/posture.dart';
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

part 'session_controller_challenge.dart';
part 'session_controller_fail_flow.dart';
part 'session_controller_career_hooks.dart';
part 'session_controller_break.dart';

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
  ///
  /// Mutable (non `final`) : se met à jour quand un défi acquitte
  /// silencieusement des milestones intra-séance (cf.
  /// `_finalizeChallengeAcquittals`). Les filtres runtime
  /// (`random_comments.pickFor`, punition carrière) voient le nouvel
  /// unlock immédiatement après le défi. La régénération des steps à
  /// venir, elle, est portée par le caller via `onPostChallengeRegen`
  /// (déclenché seulement quand le set s'élargit réellement).
  Set<UnlockKey> _unlockedKeys;

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

  /// Intervalle aléatoire borné (s) entre deux ordres énoncés pendant un break
  /// scénarisé (issue #77). Tiré dans [min, max] après chaque ordre (et à
  /// l'entrée) plutôt que fixe — une cadence régulière sonne mécanique, un peu
  /// d'irrégularité est plus naturel (cf. variété des cycles de séance). ~1
  /// ordre toutes les ~25 s en moyenne sur une pause de 60-120 s.
  static const int _breakOrderMinIntervalSeconds = 18;
  static const int _breakOrderMaxIntervalSeconds = 32;

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

  /// Seconde absolue (wallclock `_realSec`) d'entrée en phase `atSeuil`.
  /// Sert à dériver le compteur d'extensions : tant que la joueuse maintient
  /// le doigt au-delà du seuil, chaque tranche `ch.extensionSeconds` au-dessus
  /// de ce point vaut +1 extension (bumps +1 humil/+1 obed au `_finish`).
  int? _challengeAtSeuilStartedAtSec;

  /// True tant qu'un doigt (touch) ou la touche espace (desktop) est présent
  /// pendant un défi. Pilote les transitions :
  /// - `breath` : la pression initiale sur GO démarre le countdown
  /// - `countdown`/`live` : la perte du doigt arme la tolérance
  /// - `atSeuil` : le release ferme le défi avec netSuccess/extendedSuccess
  bool _challengeHoldActive = false;
  bool get challengeHoldActive => _challengeHoldActive;

  /// Seconde absolue (wallclock `_realSec`) à laquelle le doigt a décroché
  /// pendant un défi actif. `null` quand le doigt est présent OU quand on
  /// est en phase qui ne dépend pas du hold (`breath`, `ended`, `none`).
  /// Sert au calcul de la tolérance 1 s avant fail.
  int? _challengeReleaseAtRealSec;

  /// Compteur de releases pendant le countdown 3-2-1 pour le défi courant.
  /// Le 1er release ramène en `breath` avec une annonce pédagogique
  /// (« tu dois maintenir le doigt »). Le 2e release au même défi vaut
  /// `skipped` (PASSE silencieux). Reset à chaque entrée en `none`.
  int _challengeCountdownReleaseCount = 0;

  /// Compteur de `JE TIENS ENCORE` acquis. Au `_finish` : +1 humil/+1 obed
  /// par extension (cf. spec § 5.2 succès étendu). Posé par
  /// `_completeChallenge` à partir de la durée tenue au-delà du seuil
  /// (`tranches = (releaseAt - atSeuilEnteredAt) ÷ ch.extensionSeconds`).
  int _challengeExtensionsCount = 0;

  /// Compteur de franchissements gorge atteints depuis le début de la
  /// phase `live` du défi courant. Incrémenté dans `_handleBeat` quand le
  /// beat émis matche la position cible du défi (`Challenge.to`). Sert à
  /// déclencher la bascule en `atSeuil` quand `Challenge.targetCrossings`
  /// est posé — alternative à la durée nominale pour les défis dont la
  /// rampe BPM rend la durée trompeuse.
  int _challengeCrossingsCount = 0;
  int get challengeCrossingsCount => _challengeCrossingsCount;

  /// Outcome du défi courant (= dernier défi armé) — posé par les triggers
  /// (skipped/fail/netSuccess/extendedSuccess) ou par `_finish` via
  /// timeout. Null entre 2 défis ou quand aucun défi n'a encore été armé.
  /// Pour la multi-défi (Phase 19.5.b), l'historique complet est dans
  /// [_completedChallenges] — `_challengeOutcome` reflète seulement le
  /// défi en cours / qui vient de se terminer.
  ChallengeOutcome? _challengeOutcome;

  /// Index du défi actif dans `_session.challenges` (-1 = aucun défi en
  /// cours). Sert à savoir lequel des N défis est armé et à le marquer
  /// comme « traité » à la fin du breath post-défi pour que le suivant
  /// puisse être armé à son trigger time.
  int _activeChallengeIndex = -1;

  /// Set d'index de défis déjà acquittés (`_completeChallenge` appelé pour
  /// eux). Sert à éviter de re-armer un défi qui a déjà été traité, dans
  /// le cas où la session reboucle sur le même `breathStartTime` après un
  /// rebase de timeline. Persiste sur toute la session.
  final Set<int> _completedChallengeIndices = <int>{};

  /// Historique des défis complétés (outcome + extensions) pour appliquer
  /// les bumps humil/obed multi-défi au `_finish`. Push à chaque
  /// `_completeChallenge`. Une entrée par défi armé qui a abouti
  /// (succès/fail/skip/timeout).
  final List<_CompletedChallengeRecord> _completedChallenges =
      <_CompletedChallengeRecord>[];

  /// Phrase coach à afficher pendant la fenêtre défi (annonce / extension /
  /// outcome). Posée par les transitions de phase ; null si le coach n'a
  /// pas de phrase pour l'axe (l'UI retombe alors sur les libellés
  /// localisés via `AppLocalizations`).
  String? _challengeCurrentText;

  /// Miroir de la dernière `_challengeCurrentText` qui a effectivement été
  /// envoyée au TTS via `_speakChallengePhraseIfAny`. Permet de re-tenter
  /// la prononciation au tick suivant si le TTS était occupé (random
  /// comment en cours, phrase scriptée précédente non terminée) au moment
  /// de la transition de phase défi — sans risquer de prononcer deux fois
  /// la même phrase.
  String? _challengeSpokenText;

  /// Snapshot du défi de la séance courante (clone de `session.challenge`).
  /// Posé au `start()` ou au `_checkSteps` quand on entre dans le breath.
  Challenge? _activeChallenge;

  /// Builder de segments du défi en cours (Phase B — streaming). Instancié
  /// à l'entrée en phase `live` via `_startChallengeStreaming`, vidé au
  /// reset post-`ended`. `null` hors fenêtre défi live/atSeuil.
  ChallengeSegmentBuilder? _segmentBuilder;

  /// Segment de défi actuellement joué par le BeepEngine. Posé par chaque
  /// `_advanceChallengeSegment` ; sa `duration` sert à détecter la fin du
  /// segment et à demander le suivant au builder. `null` hors fenêtre défi
  /// live/atSeuil.
  SessionStep? _currentChallengeSegment;

  /// Snapshot du `_swallowMode` avant l'entrée en phase live d'un défi
  /// `noswallowStreak`. Le contrôleur force `forbidden` pendant le défi
  /// (le critère intrinsèque, cf. spec § 6) et restaure le mode initial à
  /// la sortie. `null` hors fenêtre noswallow défi.
  SwallowMode? _challengeSavedSwallowMode;

  /// Seconde absolue à laquelle la phase `countdown` (3-2-1) démarre.
  /// `null` tant qu'on n'y est pas. Sert au calcul du chiffre courant
  /// (3 → 2 → 1) côté UI et au déclenchement TTS dans `_updateChallengePhase`.
  int? _challengeCountdownStartedAtSec;

  /// Dernier chiffre du countdown énoncé en TTS. Évite de dire 2× le
  /// même chiffre dans le même tick (le ticker tourne à 200 ms).
  int _challengeCountdownLastDigitSpoken = -1;

  /// Temps réel écoulé depuis le start de la session, en secondes (fraction
  /// préservée). Lit `_stopwatch.elapsed` brut sans `_timelineOffset` — ne
  /// suit donc PAS le freeze imposé pendant les défis. Sert exclusivement à
  /// piloter la machine d'états défi (durée du countdown, du step, du
  /// timeout atSeuil) indépendamment du gel du timer session.
  double get _realSec => _stopwatch.elapsedMilliseconds / 1000.0;

  // ─── État du break scénarisé (issue #77) ──────────────────────────────
  // Pause active de récup sur les sessions longues (cf. spec
  // `specs/scripted_breaks.md`). Contrairement au flow fail, l'horloge
  // `elapsed` continue (le générateur a laissé un trou d'effort dans
  // l'enveloppe) : la machine est pilotée par tick (`_updateBreakPhase`),
  // pas par un flow async. Les méthodes vivent dans
  // `session_controller_break.dart` (part of).

  /// True tant qu'on est dans la fenêtre `[break.time, break.endTime)` d'un
  /// break. Gèle l'accrual d'effort et suspend les commentaires aléatoires.
  bool _breakActive = false;
  bool get breakActive => _breakActive;

  /// Break en cours, ou `null` hors fenêtre de break. Exposé pour l'UI
  /// (overlay PAUSE + décompte — PR5).
  ScriptedBreak? _activeBreak;
  ScriptedBreak? get activeBreak => _activeBreak;

  /// Index du prochain break à déclencher dans `session.breaks` (ordonnés
  /// par `time`). Avancé à chaque entrée de break.
  int _nextBreakIndex = 0;

  /// `elapsedSeconds` du dernier ordre de break énoncé. Sert à espacer les
  /// ordres.
  int _breakOrderLastAtSec = 0;

  /// Intervalle courant (s) avant le prochain ordre de break, re-tiré dans
  /// [`_breakOrderMinIntervalSeconds`, `_breakOrderMaxIntervalSeconds`] à
  /// l'entrée du break et après chaque ordre (cadence irrégulière).
  int _breakOrderInterval = _breakOrderMinIntervalSeconds;

  /// Posture courante imposée (issue #77). Initialisée à
  /// `session.initialPose` au `start()`, mise à jour à la reprise de chaque
  /// break qui change de pose. Exposée pour l'indicateur de posture (PR5).
  Posture _currentPose = Posture.free;
  Posture get currentPose => _currentPose;

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

  /// Wrapper privé sur `notifyListeners()` accessible depuis les extensions
  /// `ChallengeOrchestrator` (`session_controller_challenge.dart`),
  /// `FailFlowOrchestrator` (`session_controller_fail_flow.dart`) et
  /// `CareerHooksOrchestrator` (`session_controller_career_hooks.dart`).
  /// L'annotation `@protected` de `ChangeNotifier.notifyListeners` ne
  /// permet l'appel que depuis l'intérieur d'une sous-classe, pas depuis
  /// une extension — d'où ce passe-plat.
  void _notify() => notifyListeners();

  /// Callback déclenché par `triggerFail` quand l'utilisatrice rate dans
  /// la fenêtre milestone et qu'un retry est encore disponible. Retourne
  /// `true` si le retry a été pris en charge (le contrôleur saute alors
  /// le flow fail standard). Set depuis `SessionScreen`.
  Future<bool> Function(SessionController controller)? onMilestoneRetry;

  /// Callback déclenché par `_finalizeChallengeAcquittals` lorsqu'un défi
  /// vient d'élargir le set d'unlocks acquittés (au moins une milestone
  /// acquittée silencieusement via `markCompletedViaChallenge`). Le caller
  /// est attendu pour régénérer le reste de la séance avec les nouveaux
  /// unlocks et appeler `requestPostChallengeRegen` — sinon la timeline
  /// continue avec le contenu généré au start (qui ne sait rien des
  /// nouveaux unlocks). No-op si non set (sessions hors carrière, tests).
  Future<void> Function(SessionController controller)? onPostChallengeRegen;

  /// Callback déclenché à la fin de tout défi (peu importe l'outcome :
  /// fail / netSuccess / extendedSuccess / skipped / timeout). Le caller
  /// l'utilise pour persister un compteur d'essais par axe — fait monter
  /// la cible « franchissements » du défi suivant sur le même axe (cf.
  /// `ChallengeService.attemptsCount` / `crossingsTargetForAttempts`).
  /// No-op si non set.
  void Function(Challenge challenge, ChallengeOutcome outcome)?
      onChallengeOutcome;

  /// Callback haptic du défi. Émis par le contrôleur sur les transitions
  /// clés du gameplay hold-to-keep : `light` à l'entrée seuil et à chaque
  /// extension franchie, `heavy` au fail par tolérance épuisée. Câblé par
  /// la UI à `HapticFeedback.{light,heavy}Impact()`. No-op si non set
  /// (tests, sessions hors widget tree).
  void Function(ChallengeHapticKind kind)? onChallengeHaptic;

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
        _unlockedKeys = Set<UnlockKey>.from(unlockedKeys),
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
    // Pendant un défi : ne pas accumuler les stats lifetime (throatfucks,
    // biffles, mode utilisé). Le défi est une événement exceptionnel
    // (surcharge calibrée × 1.50), pas une pratique standard — un défi
    // rhythm head→throat à 120 BPM sur 45 s consomme 90 beats et gonfle
    // artificiellement le compteur throatfucks. L'imputation capability
    // se fait séparément par le `CapabilityTracker` qui voit le step
    // défi comme tout autre step.
    if (!_session.noStats && !isChallengeActive) {
      _stats.recordBeat(mode: e.mode, to: e.to);
      _stats.markModeUsed(e.mode);
    } else {
      _onChallengeBeatIfCrossingsTracked(e);
    }
    _stamina.onBeat(e);
  }

  /// Incrémente [_challengeCrossingsCount] quand le défi est en `live` et
  /// que le beat émis atteint la position cible du défi.
  /// No-op hors phase de comptage ou si le défi ne pilote pas un compteur
  /// (`targetCrossings == null`).
  void _onChallengeBeatIfCrossingsTracked(BeatEvent e) {
    final ch = _activeChallenge;
    if (ch == null || ch.targetCrossings == null) return;
    if (_challengePhase != ChallengePhase.live) {
      return;
    }
    final target = ch.to;
    if (target == null) return;
    if (e.to == target) _challengeCrossingsCount++;
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

  /// Liste des paliers nouvellement franchis, calculée par `_finish` mais
  /// gardée en attente jusqu'à `revealBadgeUnlocks()` (cf. extension
  /// `CareerHooksOrchestrator`). On préserve la même API publique
  /// (`sessionBadgeUnlocks`) une fois la révélation faite, pour que l'UI
  /// continue de pouvoir consommer la liste.
  List<BadgeUnlock> _pendingBadgeUnlocks = const [];

  /// Milestones acquittées **dans cette séance** (= viennent d'être
  /// `markCompleted` sans fail, n'étaient pas déjà acquittées avant).
  /// Vide tant que [_finish] n'a pas terminé son acquittement. Consommé
  /// par l'écran de fin pour lister les apprentissages validés à côté
  /// des badges.
  List<LevelMilestone> _sessionMilestoneUnlocks = const [];
  List<LevelMilestone> get sessionMilestoneUnlocks => _sessionMilestoneUnlocks;

  /// True si au moins une milestone vient d'être acquittée pendant cette
  /// séance. Consulté pour la cosmétique post-séance (badges, annonces)
  /// — Phase 19.12 a retiré l'utilisation pour le level-up qui n'existe
  /// plus.
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
        // Break scénarisé (issue #77) : repart de la posture initiale tirée
        // par le générateur (`free` hors carrière / flag off).
        _breakActive = false;
        _activeBreak = null;
        _nextBreakIndex = 0;
        _breakOrderLastAtSec = 0;
        _currentPose = _session.initialPose;
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

      // Inits best-effort : aucun de ces appels n'est un prérequis du passage
      // en `running`. Un échec (typiquement iOS Safari/PWA — voir ci-dessous)
      // ne doit JAMAIS avorter `start()` : sinon `_state` reste `idle` et,
      // en prod, l'écran de jeu n'a aucun bouton play (gated derrière le
      // toggle debug `showSessionControls`) → soft-lock total (cf. retour
      // iOS « pas de bouton pour commencer », v0.4.0).
      try {
        await _tts.init();
      } catch (e) {
        debugPrint('start(): _tts.init() a échoué (non bloquant) : $e');
      }
      try {
        await _beep.init();
      } catch (e) {
        debugPrint('start(): _beep.init() a échoué (non bloquant) : $e');
      }
      try {
        // Wakelock = garder l'écran allumé (confort, non essentiel). Sur iOS
        // Safari/PWA la Wake Lock API exige un contexte de geste utilisateur ;
        // appelée depuis le Timer de prep (7 s après « JE SUIS PRÊTE »), elle
        // peut lever `NotAllowedError`.
        await WakelockPlus.enable();
      } catch (e) {
        debugPrint(
            'start(): WakelockPlus.enable() a échoué (non bloquant) : $e');
      }

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
    _challengeHoldActive = false;
    _challengeReleaseAtRealSec = null;
    _challengeCountdownReleaseCount = 0;
    _challengeExtensionsCount = 0;
    _challengeOutcome = null;
    _challengeCurrentText = null;
    _challengeSpokenText = null;
    _activeChallenge = null;
    _challengeCountdownStartedAtSec = null;
    _challengeCountdownLastDigitSpoken = -1;
    _postChallengeBreathRealEndSec = null;
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
    // `_updateChallengePhase` AVANT `_checkSteps` : si on franchit la fin
    // nominale du step défi à ce tick, la phase doit basculer en `atSeuil`
    // avant que `_checkSteps` ne consomme le step suivant naturel — sinon
    // on enchaîne sur autre chose (rythme → hold head…) alors que l'UI
    // attend toujours la décision joueuse au seuil.
    _updateChallengePhase();
    // Break scénarisé (issue #77) : entrée/sortie + ordres espacés, AVANT
    // `_checkSteps`. À l'entrée d'un break la machine pause le beep ; à la
    // sortie elle relâche `_breakActive` → `_checkSteps` (ci-dessous) applique
    // alors le step d'effort posé par le générateur juste après le trou.
    _updateBreakPhase();
    _checkSteps();
    // Gel de l'effort pendant un break : pas de crédit hold/saliva/stamina/
    // mini-punition ni de marqueurs de progression (la pause est de la récup
    // mise en scène, pas de l'effort). L'horloge `elapsed`, elle, continue.
    if (!_breakActive) {
      _accrueHoldSecond();
      _checkProgressMarkers();
    }
    // Freeze la timeline session pendant TOUTE la durée du défi (breath
    // d'attente joueuse + countdown + step défi + atSeuil + extensions +
    // breath post-défi). Le défi est intégralement hors du décompte de
    // session — c'est un bonus skippable qui ne consomme jamais de temps
    // de séance, peu importe combien la joueuse attend / prolonge.
    //
    // Les transitions internes (live → atSeuil, tolérance de release, fin
    // du breath post-défi) sont mesurées sur `_realSec` (= `_stopwatch.elapsed`
    // brut, jamais freezé) pour rester indépendantes de ce gel — sans
    // cela, `_inPostChallengeBreath` ne se terminerait jamais (son seuil
    // ne serait jamais franchi par un `elapsedSeconds` gelé).
    if (isChallengeActive || _inPostChallengeBreath) {
      _timelineOffset -= _tickInterval;
    }
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
    // Phase 1 défis — quand la joueuse est au-delà du seuil (`atSeuil`)
    // et continue de tenir, on ne consomme pas les steps suivants : la
    // séance reste freezée sur le step défi qui continue à jouer son
    // loop tant que le doigt est présent.
    if (_challengePhase == ChallengePhase.atSeuil) {
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
      // d'`elapsedSeconds` vs `session.challengeTriggerTimes`. Plus de
      // transition basée sur la consommation de step (fragile au timing
      // TTS / différé `_timelineOffset`).
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
  ///
  /// [trackForDisplay] : `false` pour les énoncés courts/techniques qui
  /// ne doivent pas rester affichés dans le panneau d'instruction (ex.
  /// chiffres du countdown défi « 3 », « 2 », « 1 » — sinon « 1 » reste
  /// scotché à l'écran pendant tout le step défi).
  void _speakScripted(String text, {bool trackForDisplay = true}) {
    _lastScriptedSpeakAt = DateTime.now();
    final resolved = _tts.resolveText(text);
    if (trackForDisplay) {
      _lastSpokenResolvedText = resolved;
    }
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

  /// Instant **wallclock** (`_realSec.toInt()`-style) à partir duquel le
  /// breath de récup post-défi expire. `null` = pas de breath en cours.
  /// Pendant cette fenêtre, `_checkSteps` ne consomme aucun step suivant
  /// ET la timeline session est freezée (cf. `_onTick`) — le défi entier
  /// (breath d'annonce + step + post-défi breath) est gratuit du point de
  /// vue du timer de séance. La sémantique wallclock est nécessaire pour
  /// que le freeze fonctionne : si on indexait sur `elapsedSeconds`,
  /// celui-ci ne dépasserait jamais le seuil tant qu'on freeze et le
  /// breath ne se terminerait pas. Les getters dérivés et la machine
  /// d'états vivent dans le `part` `session_controller_challenge.dart`.
  int? _postChallengeBreathRealEndSec;

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

    // Acquittement milestone AVANT le bascule en `finished` : pose les
    // bonus immédiatement et alimente `_pendingBadgeUnlocks` avant que
    // `_FinishedPanel` ne capture son état initial. Le bonus humiliation
    // +2 d'unlock est appliqué ici, mais l'annonce TTS est déplacée
    // APRÈS le bascule (sinon notifyListeners attend la fin de
    // l'announce).
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

    // L'acquittement silencieux des milestones via défi (`§ 5.4`) et le
    // consume showcase (`§ 5.1`) sont désormais faits **dès la fin du défi**
    // dans `_completeChallenge → _finalizeChallengeAcquittals`, pour que
    // les unlocks débloqués pendant la séance soient visibles avant la
    // fin de session (et pour la séance suivante). Idempotent : la
    // séance peut se terminer avant que le défi ne s'achève (cas rare —
    // session courte + défi sur fin de fenêtre), auquel cas
    // `_finalizeChallengeAcquittals` n'a pas eu lieu et on rattrape ici.
    if (_challengePhase != ChallengePhase.ended && _challengeOutcome != null) {
      await _acquitMilestonesViaChallenge();
      await _consumeShowcaseIfMatched();
    }
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

  /// Helper pur : assemble la nouvelle [Session] qui remplace la suite
  /// après un Supplier (bouton « SUPPLIER » du mode Carrière) ou un retry
  /// milestone. Préfixe un beg insistant à [start], rebase les steps de
  /// [upcoming] sur `start + insistentBeg.duration`, et fusionne les
  /// milestones :
  ///
  /// - **Body milestones de [previous]** : conservées UNIQUEMENT si leur
  ///   fenêtre `[start, start+dur]` se termine avant [start] (Supplier
  ///   ne les a pas coupées → seront acquittées à `_finish`). Sinon
  ///   abandonnées — sinon le `markIfPresent` de `_finish` acquitterait
  ///   une milestone que l'utilisatrice n'a pas jouée.
  /// - **Body milestones de [upcoming]** : ajoutées avec décalage `offset`
  ///   (cas typique du retry milestone qui replante la milestone ratée).
  /// - **Final milestone** : prise de [upcoming] uniquement (Supplier
  ///   remplace le final, comme `finalStepTime` / `silentFinishStartTime`).
  ///
  /// Si la fusion produit plus de 2 body milestones (cas extrême : 2
  /// anciennes passées + 2 nouvelles), on conserve les 2 premières
  /// chronologiquement.
  @visibleForTesting
  static Session buildUpgradedSession({
    required Session previous,
    required Session upcoming,
    required SessionStep insistentBeg,
    required int start,
  }) {
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
      for (final s in upcoming.steps)
        SessionStep(
          time: s.time + offset,
          text: s.text,
          mode: s.mode,
          from: s.from,
          to: s.to,
          bpm: s.bpm,
          bpmEnd: s.bpmEnd,
          duration: s.duration,
          chainAction: s.chainAction,
          swallowMode: s.swallowMode,
          background: s.background,
        ),
    ];

    final bodies = <({String id, int start, int? duration})>[];
    void addPrevIfWindowEnded(int? mStart, int? mDur, String? id) {
      if (id == null || mStart == null || mDur == null) return;
      if ((mStart + mDur) <= start) {
        bodies.add((id: id, start: mStart, duration: mDur));
      }
    }

    addPrevIfWindowEnded(previous.milestoneStartTime,
        previous.milestoneDurationSeconds, previous.milestoneId);
    addPrevIfWindowEnded(previous.secondMilestoneStartTime,
        previous.secondMilestoneDurationSeconds, previous.secondMilestoneId);

    void addUpcoming(int? mStart, int? mDur, String? id) {
      if (id == null || mStart == null) return;
      bodies.add((id: id, start: mStart + offset, duration: mDur));
    }

    addUpcoming(upcoming.milestoneStartTime, upcoming.milestoneDurationSeconds,
        upcoming.milestoneId);
    addUpcoming(upcoming.secondMilestoneStartTime,
        upcoming.secondMilestoneDurationSeconds, upcoming.secondMilestoneId);

    bodies.sort((a, b) => a.start.compareTo(b.start));
    final mid1 = bodies.isNotEmpty ? bodies[0] : null;
    final mid2 = bodies.length >= 2 ? bodies[1] : null;

    final upFinalStepTime = upcoming.finalStepTime;
    final upSilentFinish = upcoming.silentFinishStartTime;
    final upFinalMsStart = upcoming.finalMilestoneStartTime;

    return Session(
      id: '${previous.id}:upgraded',
      name: previous.name,
      description: previous.description,
      durationSeconds: offset + upcoming.durationSeconds,
      defaultMode: previous.defaultMode,
      steps: newSteps,
      milestoneId: mid1?.id,
      milestoneStartTime: mid1?.start,
      milestoneDurationSeconds: mid1?.duration,
      secondMilestoneId: mid2?.id,
      secondMilestoneStartTime: mid2?.start,
      secondMilestoneDurationSeconds: mid2?.duration,
      finalMilestoneId: upcoming.finalMilestoneId,
      finalMilestoneStartTime:
          upFinalMsStart != null ? upFinalMsStart + offset : null,
      finalMilestoneDurationSeconds: upcoming.finalMilestoneDurationSeconds,
      finalStepTime: upFinalStepTime != null ? upFinalStepTime + offset : null,
      silentFinishStartTime:
          upSilentFinish != null ? upSilentFinish + offset : null,
      finalCategory: upcoming.finalCategory,
      noStats: previous.noStats,
    );
  }

  /// Helper pur : assemble la nouvelle [Session] qui remplace la suite après
  /// un défi qui a élargi les unlocks. Rebase les steps de [upcoming] sur
  /// [breathEnd] et propage les métadonnées de fin (finalStepTime,
  /// silentFinishStartTime, finalCategory) en les décalant aussi.
  ///
  /// Conserve [previous.challenge] (et ses timestamps) pour rester cohérent
  /// avec `_updateChallengePhase` qui se met en `phase == ended` à ce stade
  /// — le challenge ne sera pas re-déclenché.
  @visibleForTesting
  static Session buildPostChallengeRegenSession({
    required Session previous,
    required Session upcoming,
    required int breathEnd,
  }) {
    final newSteps = <SessionStep>[
      for (final s in upcoming.steps)
        SessionStep(
          time: s.time + breathEnd,
          text: s.text,
          mode: s.mode,
          from: s.from,
          to: s.to,
          bpm: s.bpm,
          bpmEnd: s.bpmEnd,
          duration: s.duration,
          chainAction: s.chainAction,
          swallowMode: s.swallowMode,
          background: s.background,
        ),
    ];
    final upFinalStepTime = upcoming.finalStepTime;
    final upSilentFinish = upcoming.silentFinishStartTime;
    return Session(
      id: '${previous.id}:postchallenge',
      name: previous.name,
      description: previous.description,
      durationSeconds: breathEnd + upcoming.durationSeconds,
      defaultMode: previous.defaultMode,
      steps: newSteps,
      finalStepTime:
          upFinalStepTime != null ? upFinalStepTime + breathEnd : null,
      silentFinishStartTime:
          upSilentFinish != null ? upSilentFinish + breathEnd : null,
      finalCategory: upcoming.finalCategory,
      noStats: previous.noStats,
      challenges: previous.challenges,
      challengeTriggerTimes: previous.challengeTriggerTimes,
    );
  }

  /// Décide si la machine d'états défi doit transitionner vers `atSeuil`
  /// au tick courant. Vrai uniquement quand on est encore en phase `live`
  /// et qu'on vient d'atteindre la fin nominale du step défi.
  ///
  /// Garde indispensable : après `_completeChallenge`, `phase` passe à
  /// `ended` mais `_challengeStepStartedAtSec` reste posé jusqu'à
  /// l'expiration du breath post-défi (~10 s plus tard). Sans cette garde,
  /// `elapsedInStep` continue de grandir en wallclock, dépasse `stepEnd`
  /// au tick suivant, et la transition vers `atSeuil` écrase `phase=ended`.
  @visibleForTesting
  static bool shouldEnterAtSeuilPhase({
    required ChallengePhase phase,
    required int elapsedInStep,
    required int stepEnd,
  }) {
    if (phase != ChallengePhase.live) {
      return false;
    }
    return elapsedInStep >= stepEnd;
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

    // Pas de random pendant un break scénarisé (issue #77) : la dramaturgie
    // est pilotée par le séquenceur du break (phrase d'entrée + ordres
    // espacés + reprise). On reporte de 3 s ; la fenêtre se referme d'elle-
    // même à la fin du break.
    if (_breakActive) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 3), _fireRandomComment);
      return;
    }

    // Pas de random pendant tout un défi (breath d'annonce + countdown +
    // step défi + atSeuil + extensions + breath post-défi). Pendant cette
    // fenêtre, la dramaturgie est entièrement pilotée par les phrases
    // `challengePhrases` du coach (annonce, extension, outcome) — un random
    // viendrait écraser l'annonce d'explication (mode QUEUE_FLUSH du TTS),
    // bug reporté avec « Caresse le tendrement » prononcé à la place du
    // texte d'explication du défi. Le filtre `mode == breath` plus bas ne
    // suffit pas : entre la transition de phase défi et l'application du
    // step breath sur le BeepEngine, le mode courant peut encore être le
    // mode précédent (rhythm/lick/hold).
    if (isChallengeActive || _inPostChallengeBreath) {
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
