import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../career/models/coach_catalog.dart';
import '../career/models/specialization.dart';
import '../models/badge.dart';
import 'capability_axis.dart';
import 'diagnostic_export_integrity.dart';
import 'locale_service.dart';
import 'profile_reconciliation.dart';
import 'tts_service.dart';

/// Options de l'export diagnostic. Seul levier exposé à la joueuse pour
/// l'instant : inclure ou non les surnoms personnalisés (off par défaut —
/// peuvent contenir un prénom réel).
class DiagnosticExportOptions {
  final bool includeNicknames;

  const DiagnosticExportOptions({this.includeNicknames = false});
}

/// Compose un snapshot JSON lisible de l'état persisté (SharedPreferences) de
/// l'app, à des fins de diagnostic — la joueuse peut le partager pour
/// permettre à la mainteneuse de reproduire un état précis (ex. un blocage
/// de progression de carrière).
///
/// L'export n'est jamais déclenché automatiquement : il faut une action UI
/// explicite. Aucun upload réseau : le service produit la chaîne et le caller
/// décide comment la livrer (share_plus, file_saver, etc.).
///
/// Volontairement excluus par défaut :
/// - les surnoms personnalisés (`includeNicknames` les rétablit) — peuvent
///   contenir un prénom réel ;
/// - la calibration caméra (axes, min/max) — donnée personnelle qui n'apporte
///   rien au diagnostic d'un bug de carrière.
///
/// Les réglages de voix (section `voice`), eux, sortent **sans option** : un
/// identifiant de voix est choisi dans une liste imposée par le moteur, pas
/// saisi, et ne désigne personne — contrairement à un surnom. Les mettre
/// derrière un toggle éteint par défaut reviendrait à ne jamais les recevoir,
/// c'est-à-dire à manquer la seule donnée qui permette de calibrer les voix
/// par défaut des langues non maîtrisées.
class DiagnosticExportService {
  /// Version du schéma d'export. À bumper si la forme du JSON change de
  /// façon incompatible.
  ///
  /// **Ajouter une section n'est pas incompatible** et ne la bumpe donc pas :
  /// l'import ignore ce qu'il ne connaît pas, et le checksum se recalcule sur
  /// le fichier tel qu'il est — un export produit avant l'ajout reste
  /// vérifiable. `appVersion` suffit à dater un fichier reçu.
  static const int schemaVersion = 1;

  final SharedPreferences _prefs;
  final PackageInfo _packageInfo;
  final String _platform;
  final String _locale;
  final DateTime _exportedAt;

  DiagnosticExportService({
    required SharedPreferences prefs,
    required PackageInfo packageInfo,
    required String platform,
    required String locale,
    DateTime? exportedAt,
  })  : _prefs = prefs,
        _packageInfo = packageInfo,
        _platform = platform,
        _locale = locale,
        _exportedAt = (exportedAt ?? DateTime.now()).toUtc();

  /// Construit un service en lisant SharedPreferences, package_info_plus et
  /// la locale active. Utiliser ce point d'entrée depuis l'UI ; les tests
  /// passent par le constructeur direct.
  static Future<DiagnosticExportService> create({DateTime? exportedAt}) async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    return DiagnosticExportService(
      prefs: prefs,
      packageInfo: info,
      platform: _detectPlatform(),
      locale: LocaleService.instance.languageCode,
      exportedAt: exportedAt,
    );
  }

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  /// Nom de fichier proposé par défaut, horodaté UTC à la seconde près.
  String defaultFilename() {
    final d = _exportedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${d.year.toString().padLeft(4, '0')}'
        '${two(d.month)}${two(d.day)}-'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
    return 'beatbitch-export-$stamp.json';
  }

  /// Construit le payload (Map sérialisable) selon les [options]. Inclut un
  /// champ `integrity` (SHA-256 sur la sérialisation canonique des autres
  /// champs) — checksum **anti-corruption**, pas signature cryptographique :
  /// l'app étant offline il n'existe aucun secret partagé fiable, donc rien
  /// ne prouve qu'un export modifié et re-haché ne sort pas de l'app. À
  /// utiliser pour détecter qu'un fichier transmis a été tronqué / édité
  /// par mégarde, pas pour authentifier la source.
  Map<String, dynamic> buildPayload(DiagnosticExportOptions options) {
    final payload = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'exportedAt': _exportedAt.toIso8601String(),
      'appVersion': '${_packageInfo.version}+${_packageInfo.buildNumber}',
      'platform': _platform,
      'locale': _locale,
      'career': _career(),
      'specialization': _specialization(),
      'stats': _stats(),
      'humiliation': _humiliation(),
      'obedience': _obedience(),
      'capabilities': _capabilities(),
      'milestones': _milestones(),
      'badges': _badges(),
      'coach': _coach(),
      'anatomy': _anatomy(),
      'voice': _voice(),
      if (options.includeNicknames) 'nicknames': _nicknames(),
      'surprise': _surprise(),
      'settings': _settings(),
      'savedSessions': _savedSessions(),
      'customConfigs': _customConfigs(),
      'consent': _consent(),
      'reconciliation': _reconciliation(),
    };
    payload['integrity'] = <String, dynamic>{
      'algorithm': DiagnosticExportIntegrity.algorithm,
      'value': DiagnosticExportIntegrity.compute(payload),
      'scope': 'sha256 of the canonical JSON of every other top-level field '
          '(keys sorted alphabetically at every depth, no whitespace).',
    };
    return payload;
  }

  /// Construit le JSON indenté (UTF-8) prêt à partager.
  String buildJson(DiagnosticExportOptions options) {
    return const JsonEncoder.withIndent('  ').convert(buildPayload(options));
  }

  // ── Partage des seuls réglages de voix ─────────────────────────────────

  /// Nature du fichier, en tête pour que quiconque l'ouvre sache ce qu'il
  /// tient à la première ligne — et qu'un script d'agrégation le distingue
  /// d'un export complet autrement que par l'absence de sections.
  static const String voiceShareKind = 'beatbitch-voice-settings';

  /// Payload d'un export **dédié aux réglages de voix**, sans rien du reste
  /// du profil.
  ///
  /// **Pourquoi il existe.** L'export diagnostic complet porte le temps de
  /// jeu, les scores d'humiliation et d'obéissance, les capacités mesurées
  /// axe par axe, les paliers, l'anatomie, les surnoms, le consentement.
  /// Le demander pour connaître une voix est disproportionné : la plupart
  /// refuseront, et à juste titre — c'est-à-dire que la donnée qui doit
  /// servir à calibrer les voix par défaut des langues non maîtrisées
  /// n'arriverait jamais. Un fichier qui ne contient que les voix est
  /// anodin, et suffit exactement au besoin.
  ///
  /// **Ce qu'on met autour des voix, et pourquoi si peu :**
  /// - [voiceShareKind] : ce que le fichier est, en clair.
  /// - `appVersion` : date le fichier — savoir de quelle version vient un
  ///   réglage suffit à l'interpréter, sans horodater personne.
  /// - `platform` : indispensable ici et **irrécupérable autrement**. Les
  ///   entrées ne portent le moteur que là où elles portent une voix ; un
  ///   fichier entièrement automatique ne dirait donc plus d'où il vient,
  ///   alors que « personne ne règle rien sur telle plateforme » est
  ///   précisément une conclusion qu'on veut pouvoir tirer.
  ///
  /// Volontairement **absents** : l'horodatage précis et tout identifiant,
  /// même anonyme — ils n'apportent rien à l'analyse et permettraient de
  /// recouper deux envois d'une même personne. Le pays aussi : la langue
  /// active est ce qui compte, et elle est déjà dans la section.
  ///
  /// Pas de champ `integrity` non plus : ce fichier n'est pas réimporté par
  /// l'app, il est lu par un humain. Un checksum y serait un bloc opaque au
  /// milieu d'un fichier dont tout l'argument est qu'on peut le lire en
  /// entier — et il n'authentifie rien (cf. [buildPayload]).
  ///
  /// La section est **la même** que celle de l'export complet, produite par
  /// le même code : un lot mêlant les deux formats s'agrège d'un seul
  /// chemin (`.voice.coaches[]`).
  Map<String, dynamic> buildVoiceSharePayload() => <String, dynamic>{
        'kind': voiceShareKind,
        'appVersion': '${_packageInfo.version}+${_packageInfo.buildNumber}',
        'platform': _platform,
        'voice': _voice(),
      };

  /// Construit le JSON indenté (UTF-8) des seuls réglages de voix. Court
  /// par construction : il est fait pour être affiché en entier avant
  /// d'être partagé.
  String buildVoiceShareJson() {
    return const JsonEncoder.withIndent('  ').convert(buildVoiceSharePayload());
  }

  /// Nom de fichier proposé pour le partage des voix. Il dit ce qu'il est —
  /// aucune confusion possible avec `beatbitch-export-<horodatage>.json`,
  /// qui, lui, contient tout le profil.
  ///
  /// La langue y figure parce que c'est l'axe de tri à la réception ; elle
  /// n'ajoute rien qui ne soit déjà dans le fichier. Pas d'horodatage : le
  /// nom est le même vecteur de recoupement que le contenu.
  String voiceShareFilename() => 'beatbitch-voices-$_locale.json';

  /// Recalcule le checksum sur un payload importé et le compare au champ
  /// `integrity.value`. Renvoie `true` si tout colle. Permet à un outil
  /// standalone (`tools/verify_export.dart`) de valider un export reçu.
  /// Délègue à [DiagnosticExportIntegrity.verify] — ce wrapper existe pour
  /// que l'UI / les tests n'aient qu'un seul symbole à importer.
  static bool verifyIntegrity(Map<String, dynamic> payload) =>
      DiagnosticExportIntegrity.verify(payload);

  // ── Sections ───────────────────────────────────────────────────────────

  Map<String, dynamic> _career() => <String, dynamic>{
        'maxLevel': _prefs.getInt('career.max_level') ?? 1,
        'lastLevel': _prefs.getInt('career.last_level'),
        'completedSessions': _prefs.getInt('career.completed_sessions') ?? 0,
        'includeHand': _prefs.getBool('career.include_hand') ?? true,
      };

  Map<String, dynamic> _specialization() => <String, dynamic>{
        'points': <String, int>{
          for (final b in SpecializationBranch.values)
            b.name: _prefs.getInt('specialization.points.${b.name}') ?? 0,
        },
        'lastRespecMs': _prefs.getInt('specialization.last_respec_ms'),
        'respecCount': _prefs.getInt('specialization.respec_count') ?? 0,
      };

  Map<String, dynamic> _stats() => <String, dynamic>{
        'totalSeconds': _prefs.getInt('stats.total_seconds') ?? 0,
        'throatfucks': _prefs.getInt('stats.throatfucks') ?? 0,
        'biffles': _prefs.getInt('stats.biffles') ?? 0,
        'holdThroatSeconds': _prefs.getInt('stats.hold_throat_seconds') ?? 0,
        'holdFullSeconds': _prefs.getInt('stats.hold_full_seconds') ?? 0,
        'sessionsCompleted': _prefs.getInt('stats.sessions_completed') ?? 0,
        'sessionsNoFailStreak':
            _prefs.getInt('stats.sessions_no_fail_streak') ?? 0,
        'modesUsedMask': _prefs.getInt('stats.modes_used_mask') ?? 0,
        'maxHoldFullAtomic': _prefs.getInt('stats.max_hold_full_atomic') ?? 0,
        'lastSessionDay': _prefs.getInt('stats.last_session_day'),
        'dailyStreak': _prefs.getInt('stats.daily_streak') ?? 0,
        'encoresAsked': _prefs.getInt('stats.encores_asked') ?? 0,
        'quickiesCompleted': _prefs.getInt('stats.quickies_completed') ?? 0,
        'finalsBouchePleine': _prefs.getInt('stats.finals_bouche_pleine') ?? 0,
        'finalsRepeinte': _prefs.getInt('stats.finals_repeinte') ?? 0,
        'finalsGobeuse': _prefs.getInt('stats.finals_gobeuse') ?? 0,
        'postFinalsNettoyeuse':
            _prefs.getInt('stats.post_finals_nettoyeuse') ?? 0,
        'postFinalsSuppliante':
            _prefs.getInt('stats.post_finals_suppliante') ?? 0,
      };

  Map<String, dynamic> _humiliation() => <String, dynamic>{
        'careerScore': _prefs.getDouble('stats.humiliation_level') ?? 0.0,
      };

  Map<String, dynamic> _obedience() => <String, dynamic>{
        'level': _prefs.getDouble('stats.obedience_level') ?? 0.0,
      };

  Map<String, dynamic> _capabilities() {
    final axes = <String, dynamic>{};
    for (final axis in CapabilityAxis.values) {
      final base = 'cap.${axis.storageKey}';
      final best = _prefs.getDouble('$base.best');
      final comfort = _prefs.getDouble('$base.comfort');
      final sr = _prefs.getDouble('$base.sr');
      final seen = _prefs.getInt('$base.seen');
      if (best == null && comfort == null && sr == null && seen == null) {
        continue;
      }
      axes[axis.storageKey] = <String, dynamic>{
        'best': best,
        'comfort': comfort,
        'successRate': sr,
        'lastSeenSession': seen,
      };
    }
    return <String, dynamic>{
      'axes': axes,
      'legacyMigrated': _prefs.getBool('cap.legacy_migrated') ?? false,
    };
  }

  Map<String, dynamic> _milestones() => <String, dynamic>{
        'completed':
            _decodeJsonList(_prefs.getString('career.milestones_completed')),
        'retries': _decodeJsonMap(_prefs.getString('career.milestone_retries')),
        'candidacySeen':
            _decodeJsonMap(_prefs.getString('career.milestone_candidacy_seen')),
      };

  Map<String, dynamic> _badges() {
    final out = <String, dynamic>{};
    for (final family in BadgeFamily.values) {
      final stored = _prefs.getInt('badge.tier.${family.name}');
      if (stored == null) continue;
      final tier = (stored >= 0 && stored < BadgeTier.values.length)
          ? BadgeTier.values[stored].name
          : 'unknown';
      out[family.name] = tier;
    }
    return out;
  }

  Map<String, dynamic> _coach() => <String, dynamic>{
        'currentTier': _prefs.getInt('coach.current_tier'),
        'selectedId': _prefs.getString('coach.selected_id'),
        'unlockedIds':
            _prefs.getStringList('coach.unlocked_ids') ?? const <String>[],
      };

  Map<String, dynamic> _anatomy() => <String, dynamic>{
        'hasBalls': _prefs.getBool('profile.anatomy.has_balls') ?? true,
      };

  /// Réglages de voix : la voix par défaut hors carrière (`tts.voice.<lang>`)
  /// et celle choisie pour chaque coach (`tts.voice.coach.<coachId>.<lang>`).
  ///
  /// Section conçue pour être lue par un **humain** autant que réimportée :
  /// six coachs sur sept déclarent une voix française en dur, donc hors
  /// français personne ne sait quelle voix mettre par défaut. Ces exports
  /// sont le seul moyen de le déduire des choix réels des utilisateurs —
  /// d'où le nom du coach à côté de son id opaque, la langue sur chaque
  /// entrée, et un `source` explicite plutôt qu'une clé absente muette.
  ///
  /// **Ce qui est listé** : la langue active l'est en entier (tout le
  /// catalogue de coachs, réglés ou non — « laissé en automatique » est une
  /// donnée) ; les autres langues n'apparaissent que là où un choix a été
  /// fait, pour qu'un réglage devenu inactif ne soit pas perdu sans que
  /// quatre langues vides encombrent l'export.
  ///
  /// Les clés sont **composées** via [TtsService], jamais parsées ni
  /// recopiées en littéral : un `coachId` peut contenir un point, et une
  /// divergence de préfixe exporterait un réglage que la séance ne lit pas.
  Map<String, dynamic> _voice() {
    // Langue active en tête : c'est la ligne qui porte l'information quand
    // un humain lit l'export, les autres ne sont que des vestiges. L'ordre
    // reste déterministe — le checksum ne trie pas les listes.
    final languages = <String>[
      _locale,
      for (final l in kSupportedLocales)
        if (l.languageCode != _locale) l.languageCode,
    ];
    final defaults = <Map<String, dynamic>>[];
    for (final lang in languages) {
      final stored = _prefs.getString(TtsService.userVoiceKey(lang));
      if (stored == null && lang != _locale) continue;
      defaults.add(_voiceEntry(lang, stored));
    }
    final coaches = <Map<String, dynamic>>[];
    for (final coach in CoachCatalog.defaults) {
      for (final lang in languages) {
        final stored =
            _prefs.getString(TtsService.coachVoiceKey(coach.id, lang));
        if (stored == null && lang != _locale) continue;
        coaches.add(<String, dynamic>{
          'coachId': coach.id,
          'coachName': coach.name,
          ..._voiceEntry(lang, stored),
        });
      }
    }
    return <String, dynamic>{
      'activeLanguage': _locale,
      // Linux n'expose aucune API « choisir une voix » (cf.
      // `TtsService.supportsVoiceSelection`) : sans ce drapeau, un export
      // Linux entièrement `automatic` se lirait comme un désintérêt alors
      // que le réglage n'a simplement aucune prise.
      'selectionSupported': _platform != 'linux',
      'default': defaults,
      'coaches': coaches,
    };
  }

  /// Entrée de voix lisible seule : `voice` porte l'identifiant technique
  /// (`null` quand rien n'est réglé), `source` dit en clair si l'appareil
  /// choisit ou si l'utilisateur a tranché, et `platform` **le moteur qui a
  /// produit cet identifiant**.
  ///
  /// Le moteur est porté par l'entrée et non par la section parce que
  /// l'unité qu'on agrège est l'entrée : concaténer les `coaches` de
  /// plusieurs exports perd tout ce qui vivait au-dessus, et
  /// `en-gb-x-gbd-local` (voix Android) se retrouverait dans la même liste
  /// plate que `Microsoft David Desktop` (voix SAPI) — deux espaces de noms
  /// disjoints, aucun moyen de savoir lequel est réutilisable où. Même
  /// raison que la [language] répétée sur chaque entrée.
  ///
  /// Il vaut la valeur du champ `platform` de tête, volontairement : c'est
  /// tout ce qu'on sait du moteur (`flutter_tts` délègue à l'OS, sans
  /// exposer quel moteur Android est installé), et réutiliser le nom évite
  /// d'inventer un vocabulaire qui promettrait plus de précision.
  ///
  /// **Absent quand `voice` est `null`** : il n'y a alors aucune valeur à
  /// interpréter, et une colonne constante sur tout le catalogue coûterait
  /// en lisibilité sans rien apprendre. `selectionSupported` couvre déjà le
  /// seul cas où une absence de réglage demande à être interprétée (Linux
  /// n'a pas prise, ce n'est pas un désintérêt).
  Map<String, dynamic> _voiceEntry(String language, String? voice) =>
      <String, dynamic>{
        'language': language,
        'voice': voice,
        'source': voice == null ? 'automatic' : 'chosen',
        if (voice != null) 'platform': _platform,
      };

  Map<String, dynamic> _nicknames() => <String, dynamic>{
        'prenom': _prefs.getString('user_profile_prenom'),
        'custom': _prefs.getStringList('user_profile_custom_nicknames') ??
            const <String>[],
        'disabledDefaults':
            _prefs.getStringList('user_profile_disabled_default_nicknames') ??
                const <String>[],
      };

  Map<String, dynamic> _surprise() => <String, dynamic>{
        'enabled': _prefs.getBool('surprise.enabled') ?? false,
        'windowSeconds': _prefs.getInt('surprise.window_seconds'),
        'alertCount': _prefs.getInt('surprise.alert_count'),
        'durationMinSeconds': _prefs.getInt('surprise.duration_min_s'),
        'durationMaxSeconds': _prefs.getInt('surprise.duration_max_s'),
      };

  Map<String, dynamic> _settings() => <String, dynamic>{
        'showStaminaBar': _prefs.getBool('debug.show_stamina_bar') ?? false,
        'showTimer': _prefs.getBool('debug.show_timer') ?? false,
        'showHumiliationBar':
            _prefs.getBool('debug.show_humiliation_bar') ?? false,
        'showObedienceBar': _prefs.getBool('debug.show_obedience_bar') ?? false,
        'showSalivaBar': _prefs.getBool('debug.show_saliva_bar') ?? false,
        'showSessionControls':
            _prefs.getBool('debug.show_session_controls') ?? false,
        'showModeBadge': _prefs.getBool('debug.show_mode_badge') ?? false,
        'cameraHoldCheck': _prefs.getBool('debug.camera_hold_check') ?? false,
        'skipSessionButton':
            _prefs.getBool('debug.skip_session_button') ?? false,
        'showBackgroundMedia':
            _prefs.getBool('pref.show_background_media') ?? true,
        'showSessionRemainingTime':
            _prefs.getBool('pref.show_session_remaining_time') ?? false,
      };

  /// `saved_sessions/` vit en `path_provider` côté natif : on n'a accès qu'à
  /// l'index web persisté en shared_preferences. Suffisant pour un signalement
  /// de bug — la mainteneuse a déjà la liste des scénarios intégrés.
  Map<String, dynamic> _savedSessions() {
    final webIdx =
        _prefs.getStringList('saved_sessions.index') ?? const <String>[];
    return <String, dynamic>{
      'webIndexCount': webIdx.length,
    };
  }

  /// Idem `_savedSessions` : les configs Custom vivent sur disque côté natif.
  /// On ne dévoile pas leur contenu ici — il peut contenir un nom personnel —
  /// juste le compte de l'index web et l'id de la dernière config lancée.
  Map<String, dynamic> _customConfigs() {
    final webIdx =
        _prefs.getStringList('custom_configs.index') ?? const <String>[];
    return <String, dynamic>{
      'lastConfigId': _prefs.getString('custom.last_config_id'),
      'webIndexCount': webIdx.length,
    };
  }

  Map<String, dynamic> _consent() => <String, dynamic>{
        'adultConsentAccepted':
            _prefs.getBool('app.adult_consent_accepted') ?? false,
        'onboardingShown': _prefs.getBool('onboarding.shown') ?? false,
      };

  /// Passes de réconciliation appliquées au profil. Sans ça, un profil
  /// corrigé au démarrage serait indiscernable d'un profil qui n'a jamais
  /// dérivé — donc indiagnosticable après coup. `changes` est absent quand
  /// la passe a tourné sans rien modifier (le cas d'un profil sain).
  Map<String, dynamic> _reconciliation() {
    final report = ProfileReconciliation.storedReport(_prefs);
    return <String, dynamic>{
      'bpmRunawayV1': <String, dynamic>{
        'ran': _prefs.getBool(ProfileReconciliation.flagKey) ?? false,
        'ranAt': _prefs.getString(ProfileReconciliation.ranAtKey),
        if (report != null) 'changes': report.toJson(),
      },
    };
  }

  // ── helpers ────────────────────────────────────────────────────────────

  static List<dynamic> _decodeJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return const <dynamic>[];
    try {
      final v = json.decode(raw);
      if (v is List) return v;
    } catch (_) {
      // raw corrompu — on retourne une liste vide plutôt que de faire échouer
      // tout l'export pour un seul champ.
    }
    return const <dynamic>[];
  }

  static Map<String, dynamic> _decodeJsonMap(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, dynamic>{};
    try {
      final v = json.decode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {
      // idem.
    }
    return const <String, dynamic>{};
  }
}
