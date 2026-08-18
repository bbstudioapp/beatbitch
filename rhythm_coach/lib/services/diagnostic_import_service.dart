import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../career/models/coach_catalog.dart';
import '../career/models/specialization.dart';
import '../models/badge.dart';
import 'capability_axis.dart';
import 'locale_service.dart';
import 'profile_reconciliation.dart';
import 'tts_service.dart';

/// Inverse de [DiagnosticExportService] : réécrit l'état persisté
/// (`SharedPreferences`) à partir d'un payload au **format d'export**.
///
/// Usage : **debug uniquement** (chargement de profils pré-fabriqués depuis
/// `assets/debug/profiles/`, cf. `DebugProfilesSection`). Ne vérifie PAS le
/// champ `integrity` — les presets sont des assets de confiance, et
/// l'intégrité anti-corruption n'a de sens que pour un fichier transmis.
///
/// **Déterministe** : on efface d'abord toutes les clés gérées (`_clearManaged`)
/// puis on réécrit celles présentes dans le payload. Charger un preset produit
/// donc toujours le même état, sans résidu d'un chargement précédent.
///
/// **Restart requis** : les services (MilestoneService, CapabilityService,
/// StatsService…) sont des singletons qui lisent les prefs au démarrage. Les
/// écritures ne prennent effet qu'au prochain lancement de l'app.
class DiagnosticImportService {
  final SharedPreferences _prefs;
  final List<Future<void>> _ops = <Future<void>>[];

  DiagnosticImportService(this._prefs);

  static Future<DiagnosticImportService> create() async =>
      DiagnosticImportService(await SharedPreferences.getInstance());

  /// Applique le [payload] (Map désérialisée d'un JSON au format export).
  /// Attend la persistance de toutes les écritures avant de rendre la main.
  Future<void> apply(Map<String, dynamic> payload) async {
    await _clearManaged();

    _career(_map(payload['career']));
    _specialization(_map(payload['specialization']));
    _stats(_map(payload['stats']));
    _double(
        'stats.humiliation_level', _map(payload['humiliation'])['careerScore']);
    _double('stats.obedience_level', _map(payload['obedience'])['level']);
    _capabilities(_map(payload['capabilities']));
    _milestones(_map(payload['milestones']));
    _badges(_map(payload['badges']));
    _coach(_map(payload['coach']));
    _bool('profile.anatomy.has_balls', _map(payload['anatomy'])['hasBalls']);
    if (payload['nicknames'] != null) {
      _nicknames(_map(payload['nicknames']));
    }
    final voice = payload['voice'];
    if (_carriesVoiceSettings(voice)) {
      await _clearVoiceKeys();
      _voice(_map(voice));
    }
    _surprise(_map(payload['surprise']));
    _settings(_map(payload['settings']));
    _consent(_map(payload['consent']));

    await Future.wait(_ops);
  }

  // ── sections ─────────────────────────────────────────────────────────

  void _career(Map<String, dynamic> j) {
    _int('career.max_level', j['maxLevel']);
    _int('career.last_level', j['lastLevel']);
    _int('career.completed_sessions', j['completedSessions']);
    _bool('career.include_hand', j['includeHand']);
  }

  void _specialization(Map<String, dynamic> j) {
    final points = _map(j['points']);
    for (final b in SpecializationBranch.values) {
      _int('specialization.points.${b.name}', points[b.name]);
    }
    _int('specialization.last_respec_ms', j['lastRespecMs']);
    _int('specialization.respec_count', j['respecCount']);
  }

  void _stats(Map<String, dynamic> j) {
    _int('stats.total_seconds', j['totalSeconds']);
    _int('stats.throatfucks', j['throatfucks']);
    _int('stats.biffles', j['biffles']);
    _int('stats.hold_throat_seconds', j['holdThroatSeconds']);
    _int('stats.hold_full_seconds', j['holdFullSeconds']);
    _int('stats.sessions_completed', j['sessionsCompleted']);
    _int('stats.sessions_no_fail_streak', j['sessionsNoFailStreak']);
    _int('stats.modes_used_mask', j['modesUsedMask']);
    _int('stats.max_hold_full_atomic', j['maxHoldFullAtomic']);
    _int('stats.last_session_day', j['lastSessionDay']);
    _int('stats.daily_streak', j['dailyStreak']);
    _int('stats.encores_asked', j['encoresAsked']);
    _int('stats.quickies_completed', j['quickiesCompleted']);
    _int('stats.finals_bouche_pleine', j['finalsBouchePleine']);
    _int('stats.finals_repeinte', j['finalsRepeinte']);
    _int('stats.finals_gobeuse', j['finalsGobeuse']);
    _int('stats.post_finals_nettoyeuse', j['postFinalsNettoyeuse']);
    _int('stats.post_finals_suppliante', j['postFinalsSuppliante']);
  }

  void _capabilities(Map<String, dynamic> j) {
    final axes = _map(j['axes']);
    for (final entry in axes.entries) {
      final base = 'cap.${entry.key}';
      final a = _map(entry.value);
      _double('$base.best', a['best']);
      _double('$base.comfort', a['comfort']);
      _double('$base.sr', a['successRate']);
      _int('$base.seen', a['lastSeenSession']);
    }
    _bool('cap.legacy_migrated', j['legacyMigrated']);
  }

  void _milestones(Map<String, dynamic> j) {
    final completed = (j['completed'] as List?)?.cast<dynamic>() ?? const [];
    _string('career.milestones_completed', jsonEncode(completed));
    _string('career.milestone_retries', jsonEncode(_map(j['retries'])));
    _string('career.milestone_candidacy_seen',
        jsonEncode(_map(j['candidacySeen'])));
  }

  void _badges(Map<String, dynamic> j) {
    for (final family in BadgeFamily.values) {
      final tierName = j[family.name];
      if (tierName is! String) continue;
      final idx = BadgeTier.values.indexWhere((t) => t.name == tierName);
      if (idx >= 0) _int('badge.tier.${family.name}', idx);
    }
  }

  void _coach(Map<String, dynamic> j) {
    _int('coach.current_tier', j['currentTier']);
    _string('coach.selected_id', j['selectedId']);
    _stringList('coach.unlocked_ids', j['unlockedIds']);
  }

  void _nicknames(Map<String, dynamic> j) {
    _string('user_profile_prenom', j['prenom']);
    _stringList('user_profile_custom_nicknames', j['custom']);
    _stringList(
        'user_profile_disabled_default_nicknames', j['disabledDefaults']);
  }

  /// Repose les réglages de voix **tels quels** : une voix absente du nouvel
  /// appareil retombe sur le repli silencieux de la séance, et la préférence
  /// reste en base pour reprendre effet si la voix réapparaît. Rien à valider
  /// ici, donc.
  ///
  /// `source` n'est jamais lu : il n'existe que pour le lecteur humain. Ni
  /// `platform`, qui dit de quel moteur vient l'identifiant mais ne change
  /// rien à ce qu'on écrit : reposer sur un autre moteur une voix qui n'y
  /// existe pas tombe sur le même repli silencieux qu'une voix désinstallée,
  /// et filtrer ferait disparaître les réglages d'un export chargé pour
  /// diagnostic depuis une autre machine. Une entrée « automatique » porte
  /// `voice: null`, que [_string] ignore — et une clé absente *est* le mode
  /// automatique.
  ///
  /// Les clés sont composées via [TtsService] à partir du `coachId` et de la
  /// langue portés par l'entrée : un id inconnu du catalogue (export d'une
  /// version plus récente) se repose donc sans traitement particulier.
  void _voice(Map<String, dynamic> j) {
    _double(TtsService.userRateKey, j['rate']);
    _double(TtsService.userPitchKey, j['pitch']);
    for (final e in _entries(j['default'])) {
      final lang = e['language'];
      if (lang is String) _string(TtsService.userVoiceKey(lang), e['voice']);
    }
    for (final e in _entries(j['coaches'])) {
      final id = e['coachId'];
      final lang = e['language'];
      if (id is String && lang is String) {
        _string(TtsService.coachVoiceKey(id, lang), e['voice']);
      }
    }
  }

  void _surprise(Map<String, dynamic> j) {
    _bool('surprise.enabled', j['enabled']);
    _int('surprise.window_seconds', j['windowSeconds']);
    _int('surprise.alert_count', j['alertCount']);
    _int('surprise.duration_min_s', j['durationMinSeconds']);
    _int('surprise.duration_max_s', j['durationMaxSeconds']);
  }

  void _settings(Map<String, dynamic> j) {
    _bool('debug.show_stamina_bar', j['showStaminaBar']);
    _bool('debug.show_timer', j['showTimer']);
    _bool('debug.show_humiliation_bar', j['showHumiliationBar']);
    _bool('debug.show_obedience_bar', j['showObedienceBar']);
    _bool('debug.show_saliva_bar', j['showSalivaBar']);
    _bool('debug.show_session_controls', j['showSessionControls']);
    _bool('debug.show_mode_badge', j['showModeBadge']);
    _bool('debug.camera_hold_check', j['cameraHoldCheck']);
    _bool('debug.skip_session_button', j['skipSessionButton']);
    _bool('pref.show_background_media', j['showBackgroundMedia']);
    _bool('pref.show_session_remaining_time', j['showSessionRemainingTime']);
    // Champ hors-export : les presets debug peuvent piloter le réglage
    // « Postures imposées et pauses » directement (`pref.scripted_breaks`).
    _bool('pref.scripted_breaks', j['scriptedBreaks']);
  }

  void _consent(Map<String, dynamic> j) {
    _bool('app.adult_consent_accepted', j['adultConsentAccepted']);
    _bool('onboarding.shown', j['onboardingShown']);
  }

  // ── effacement des clés gérées (pour un chargement déterministe) ───────

  Future<void> _clearManaged() async {
    final keys = <String>{
      'career.max_level',
      'career.last_level',
      'career.completed_sessions',
      'career.include_hand',
      for (final b in SpecializationBranch.values)
        'specialization.points.${b.name}',
      'specialization.last_respec_ms',
      'specialization.respec_count',
      'stats.total_seconds',
      'stats.throatfucks',
      'stats.biffles',
      'stats.hold_throat_seconds',
      'stats.hold_full_seconds',
      'stats.sessions_completed',
      'stats.sessions_no_fail_streak',
      'stats.modes_used_mask',
      'stats.max_hold_full_atomic',
      'stats.last_session_day',
      'stats.daily_streak',
      'stats.encores_asked',
      'stats.quickies_completed',
      'stats.finals_bouche_pleine',
      'stats.finals_repeinte',
      'stats.finals_gobeuse',
      'stats.post_finals_nettoyeuse',
      'stats.post_finals_suppliante',
      'stats.humiliation_level',
      'stats.obedience_level',
      'cap.legacy_migrated',
      for (final axis in CapabilityAxis.values) ...[
        'cap.${axis.storageKey}.best',
        'cap.${axis.storageKey}.comfort',
        'cap.${axis.storageKey}.sr',
        'cap.${axis.storageKey}.seen',
      ],
      'career.milestones_completed',
      'career.milestone_retries',
      'career.milestone_candidacy_seen',
      for (final family in BadgeFamily.values) 'badge.tier.${family.name}',
      'coach.current_tier',
      'coach.selected_id',
      'coach.unlocked_ids',
      'profile.anatomy.has_balls',
      'user_profile_prenom',
      'user_profile_custom_nicknames',
      'user_profile_disabled_default_nicknames',
      'surprise.enabled',
      'surprise.window_seconds',
      'surprise.alert_count',
      'surprise.duration_min_s',
      'surprise.duration_max_s',
      'debug.show_stamina_bar',
      'debug.show_timer',
      'debug.show_humiliation_bar',
      'debug.show_obedience_bar',
      'debug.show_saliva_bar',
      'debug.show_session_controls',
      'debug.show_mode_badge',
      'debug.camera_hold_check',
      'debug.skip_session_button',
      'pref.scripted_breaks',
      'pref.show_background_media',
      'pref.show_session_remaining_time',
      'app.adult_consent_accepted',
      'onboarding.shown',
      // Le profil importé remplace l'existant : il doit être réconcilié
      // comme n'importe quel profil chargé, donc au redémarrage qui suit
      // l'import. Garder le drapeau posé ferait entrer un profil dérivé
      // sans jamais le rattraper.
      ProfileReconciliation.flagKey,
      ProfileReconciliation.reportKey,
      ProfileReconciliation.ranAtKey,
    };
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }

  /// Une section `voice` **exploitable** : une Map portant au moins une des
  /// deux listes d'entrées. C'est ce qui conditionne l'effacement préalable
  /// (cf. [_clearVoiceKeys]) — effacer sans rien pouvoir reposer derrière
  /// viderait les réglages en silence, alors que le payload n'a rien dit sur
  /// la voix. Écarte donc `{}`, une chaîne, un nombre, une liste, `null`.
  static bool _carriesVoiceSettings(dynamic v) =>
      v is Map && (v['default'] is List || v['coaches'] is List);

  /// Efface les réglages de voix, **seulement** quand le payload en porte
  /// (cf. [apply]) — à la différence des autres sections, effacées sans
  /// condition.
  ///
  /// Pourquoi cette exception : tout export produit depuis la Phase 3 porte
  /// une section `voice`, donc charger l'export d'une utilisatrice repose
  /// bien son état vocal exact — sans quoi on diagnostiquerait un problème
  /// de voix en entendant ses propres réglages. Un payload qui n'en parle
  /// pas (preset debug d'`assets/debug/profiles/`, export d'avant la Phase 3)
  /// ne gère pas les voix : les effacer changerait silencieusement la voix
  /// de la machine, et le repli est justement muet en séance.
  ///
  /// Énumération par **composition** (catalogue × langues supportées), jamais
  /// par filtrage-parsing des clés : un `coachId` peut contenir un point.
  Future<void> _clearVoiceKeys() async {
    await _prefs.remove(TtsService.userRateKey);
    await _prefs.remove(TtsService.userPitchKey);
    for (final locale in kSupportedLocales) {
      final lang = locale.languageCode;
      await _prefs.remove(TtsService.userVoiceKey(lang));
      for (final coach in CoachCatalog.defaults) {
        await _prefs.remove(TtsService.coachVoiceKey(coach.id, lang));
      }
    }
  }

  // ── writers typés (ignorent silencieusement les valeurs absentes/nulles) ─

  void _int(String key, dynamic v) {
    if (v is num) _ops.add(_prefs.setInt(key, v.toInt()));
  }

  void _double(String key, dynamic v) {
    if (v is num) _ops.add(_prefs.setDouble(key, v.toDouble()));
  }

  void _bool(String key, dynamic v) {
    if (v is bool) _ops.add(_prefs.setBool(key, v));
  }

  void _string(String key, dynamic v) {
    if (v is String) _ops.add(_prefs.setString(key, v));
  }

  void _stringList(String key, dynamic v) {
    if (v is List) _ops.add(_prefs.setStringList(key, v.cast<String>()));
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  static List<Map<String, dynamic>> _entries(dynamic v) => v is List
      ? <Map<String, dynamic>>[
          for (final e in v)
            if (e is Map) Map<String, dynamic>.from(e),
        ]
      : const <Map<String, dynamic>>[];
}
