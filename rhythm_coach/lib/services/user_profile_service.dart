import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/anatomy_profile.dart';
import 'locale_service.dart';

/// Profil utilisateur : prénom optionnel + liste de surnoms personnalisés.
///
/// Le placeholder `{name}` dans toute phrase TTS est remplacé par un tirage
/// aléatoire dans le pool (prenom si défini ∪ surnoms par défaut + custom).
/// Le tirage se fait à chaque appel de `pickName()` — donc deux occurrences
/// de `{name}` dans la même phrase peuvent renvoyer des surnoms différents
/// (volontaire : variété).
class UserProfileService extends ChangeNotifier {
  static const String _prenomKey = 'user_profile_prenom';
  static const String _customNicknamesKey = 'user_profile_custom_nicknames';
  static const String _disabledDefaultsKey =
      'user_profile_disabled_default_nicknames';
  static const String _nicknamesAssetPathDefault = 'assets/nicknames.json';
  static const String _anatomyHasBallsKey = 'profile.anatomy.has_balls';

  String _nicknamesAssetPathFor(String lang) =>
      lang == 'fr' ? _nicknamesAssetPathDefault : 'assets/nicknames_$lang.json';

  /// Fallback ultime si l'utilisateur a tout vidé. Évite que `{name}`
  /// disparaisse complètement et laisse une phrase tronquée.
  static const String _emptyFallback = 'salope';

  final Random _rng;

  String? _prenom;
  List<String> _defaultNicknames = const [];
  List<String> _customNicknames = const [];
  Set<String> _disabledDefaults = const {};
  bool _anatomyHasBalls = true;
  bool _loaded = false;
  String? _defaultsLoadedFor;
  late final VoidCallback _localeListener = _onLocaleChanged;

  UserProfileService({Random? rng}) : _rng = rng ?? Random() {
    LocaleService.instance.addListener(_localeListener);
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_localeListener);
    super.dispose();
  }

  String? get prenom => _prenom;
  List<String> get defaultNicknames => List.unmodifiable(_defaultNicknames);
  List<String> get customNicknames => List.unmodifiable(_customNicknames);
  Set<String> get disabledDefaults => Set.unmodifiable(_disabledDefaults);

  /// Profil anatomique courant. Reconstruit à chaque appel (objet value
  /// immuable, peu coûteux). Les listeners du service sont notifiés au
  /// changement → `AnimatedBuilder` côté UI suffit pour réagir.
  AnatomyProfile get anatomy => AnatomyProfile(hasBalls: _anatomyHasBalls);

  /// Pool effectif utilisé pour le tirage aléatoire.
  List<String> get activePool {
    final pool = <String>[];
    if (_prenom != null && _prenom!.isNotEmpty) pool.add(_prenom!);
    for (final n in _defaultNicknames) {
      if (!_disabledDefaults.contains(n)) pool.add(n);
    }
    pool.addAll(_customNicknames);
    return pool;
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    _prenom = prefs.getString(_prenomKey);
    _customNicknames = prefs.getStringList(_customNicknamesKey) ?? const [];
    _disabledDefaults =
        (prefs.getStringList(_disabledDefaultsKey) ?? const []).toSet();
    _anatomyHasBalls = prefs.getBool(_anatomyHasBallsKey) ?? true;

    await _loadDefaultsForCurrentLocale();

    _loaded = true;
    notifyListeners();
  }

  Future<void> _loadDefaultsForCurrentLocale() async {
    final lang = LocaleService.instance.languageCode;
    try {
      final path = _nicknamesAssetPathFor(lang);
      String raw;
      try {
        raw = await rootBundle.loadString(path);
      } catch (_) {
        raw = await rootBundle.loadString(_nicknamesAssetPathDefault);
      }
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final list = (decoded['default_nicknames'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [];
      _defaultNicknames = list;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserProfile] chargement surnoms défaut KO : $e');
      }
      _defaultNicknames = const [];
    }
    _defaultsLoadedFor = lang;
  }

  void _onLocaleChanged() {
    final lang = LocaleService.instance.languageCode;
    if (_defaultsLoadedFor == lang) return;
    unawaited(() async {
      await _loadDefaultsForCurrentLocale();
      notifyListeners();
    }());
  }

  Future<void> setPrenom(String? value) async {
    final cleaned = value?.trim();
    _prenom = (cleaned == null || cleaned.isEmpty) ? null : cleaned;
    final prefs = await SharedPreferences.getInstance();
    if (_prenom == null) {
      await prefs.remove(_prenomKey);
    } else {
      await prefs.setString(_prenomKey, _prenom!);
    }
    notifyListeners();
  }

  Future<void> addCustomNickname(String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    if (_customNicknames.contains(cleaned)) return;
    _customNicknames = [..._customNicknames, cleaned];
    await _persistCustom();
    notifyListeners();
  }

  Future<void> removeCustomNickname(String value) async {
    if (!_customNicknames.contains(value)) return;
    _customNicknames =
        _customNicknames.where((n) => n != value).toList(growable: false);
    await _persistCustom();
    notifyListeners();
  }

  Future<void> setDefaultEnabled(String nickname, bool enabled) async {
    final next = Set<String>.from(_disabledDefaults);
    if (enabled) {
      next.remove(nickname);
    } else {
      next.add(nickname);
    }
    if (next.length == _disabledDefaults.length &&
        next.containsAll(_disabledDefaults)) {
      return;
    }
    _disabledDefaults = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_disabledDefaultsKey, _disabledDefaults.toList());
    notifyListeners();
  }

  Future<void> _persistCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customNicknamesKey, _customNicknames);
  }

  Future<void> setAnatomyHasBalls(bool value) async {
    if (_anatomyHasBalls == value) return;
    _anatomyHasBalls = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_anatomyHasBallsKey, value);
    notifyListeners();
  }

  /// Renvoie un nom à utiliser pour substituer `{name}`. Un tirage par appel.
  String pickName() {
    final pool = activePool;
    if (pool.isEmpty) return _emptyFallback;
    return pool[_rng.nextInt(pool.length)];
  }

  /// Substitue les occurrences de `{name}` par un tirage du pool actif.
  /// Capture l'espace qui précède pour le retirer aussi quand on supprime
  /// la balise — sinon on laisse un double espace.
  ///
  /// **Une fois sur deux**, `{name}` est purement effacé : trop d'appels
  /// à la suite donnaient l'impression que la coach martelait toujours
  /// le surnom, ce qui devient mécanique. Le tirage 1/2 garde de la
  /// variété sans casser les phrases construites autour du placeholder.
  ///
  /// `{coach}` sans override coach → effacé proprement (espace avalé).
  /// L'override coach (cf. `Coach.buildTextResolver`) prend la main.
  String resolve(String text) {
    if (!text.contains('{')) return text;
    return text.replaceAllMapped(
      RegExp(r'\s?\{\s*name\s*\}', caseSensitive: false),
      (m) {
        // Si on tire « strip », on jette aussi l'espace capturé.
        if (_rng.nextBool()) return '';
        // Préserve l'espace original si présent dans la capture.
        final hadSpace = m.group(0)?.startsWith(' ') ?? false;
        return hadSpace ? ' ${pickName()}' : pickName();
      },
    ).replaceAll(RegExp(r'\s?\{\s*coach\s*\}', caseSensitive: false), '');
  }
}
