import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../career/models/specialization.dart';
import '../models/badge.dart';
import 'capability_axis.dart';
import 'diagnostic_export_integrity.dart';
import 'locale_service.dart';

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
class DiagnosticExportService {
  /// Version du schéma d'export. À bumper si la forme du JSON change de
  /// façon incompatible.
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
      if (options.includeNicknames) 'nicknames': _nicknames(),
      'surprise': _surprise(),
      'settings': _settings(),
      'savedSessions': _savedSessions(),
      'customConfigs': _customConfigs(),
      'consent': _consent(),
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
