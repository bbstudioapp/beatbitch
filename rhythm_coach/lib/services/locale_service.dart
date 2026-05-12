import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locales supportées par l'app. Ajouter une entrée + un fichier ARB
/// + un set de phrases JSON pour étendre.
const List<Locale> kSupportedLocales = [
  Locale('fr'),
  Locale('en'),
  Locale('de'),
];

/// Locale de repli si aucune préférence persistée et que la locale système
/// n'est pas dans `kSupportedLocales`. Anglais : c'est la langue la plus
/// large pour un public qui ne parle ni français ni une autre langue
/// éventuellement ajoutée plus tard. N'est utilisée que comme valeur
/// provisoire le temps que l'utilisatrice choisisse via le sélecteur de
/// premier lancement (cf. [needsLanguageSelection]).
const Locale kFallbackLocale = Locale('en');

/// Clé du choix de langue *explicite* (sélecteur de premier lancement ou
/// dropdown des réglages). Une locale auto-déduite de l'OS n'est jamais
/// persistée ici — elle est re-dérivée à chaque lancement, donc l'app suit
/// la langue du téléphone tant que celle-ci est supportée.
const String _prefsKey = 'app.locale';

/// Clé de l'ensemble des codes langue supportés *au moment du dernier choix
/// explicite*. Sert à détecter qu'une langue ajoutée dans une version
/// ultérieure correspond maintenant à la locale système — auquel cas on
/// propose (une fois) de basculer, cf. [pendingNewLocaleOffer].
const String _knownLocalesKey = 'app.locale.knownLocales';

/// Singleton léger qui expose la locale active. Notifie les listeners quand
/// elle change. À instancier au démarrage (`await LocaleService.instance.init()`)
/// avant `runApp`.
class LocaleService extends ChangeNotifier {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  Locale _current = kFallbackLocale;
  bool _initialized = false;
  bool _needsLanguageSelection = false;

  Locale get current => _current;

  /// Code langue ISO-639 (ex: "fr", "en"). Pratique pour filtrer les JSON.
  String get languageCode => _current.languageCode;

  /// `true` quand aucun choix explicite n'est persisté ET que la langue du
  /// système n'est pas supportée : on ne devine pas, l'écran d'accueil doit
  /// présenter un sélecteur (la locale active est provisoirement
  /// [kFallbackLocale] le temps de ce choix).
  bool get needsLanguageSelection => _needsLanguageSelection;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && _isSupportedLanguage(stored)) {
      _current = Locale(stored);
      return;
    }

    final system = PlatformDispatcher.instance.locale;
    if (_isSupportedLanguage(system.languageCode)) {
      // Pas persisté : on re-suit l'OS à chaque lancement.
      _current = Locale(system.languageCode);
    } else {
      // Provisoire — l'écran d'accueil demandera de choisir.
      _current = kFallbackLocale;
      _needsLanguageSelection = true;
    }
  }

  /// Enregistre un choix de langue *explicite* (sélecteur de premier
  /// lancement, dropdown des réglages, ou bascule proposée après l'ajout
  /// d'une langue). Persiste toujours — même si la locale choisie est déjà
  /// la locale active — pour que le choix « colle » face à la langue de
  /// l'OS. Mémorise aussi les locales supportées à cet instant.
  Future<void> setLocale(Locale locale) async {
    if (!_isSupportedLanguage(locale.languageCode)) return;
    _needsLanguageSelection = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
    await prefs.setStringList(_knownLocalesKey, _supportedCodes());
    if (_current.languageCode != locale.languageCode) {
      _current = Locale(locale.languageCode);
      notifyListeners();
    }
  }

  /// Si une langue ajoutée dans une version ultérieure correspond maintenant
  /// à la locale système, qu'elle diffère de la locale active et qu'elle
  /// n'était pas disponible au moment du dernier choix explicite, renvoie
  /// cette locale pour que l'écran d'accueil propose (une seule fois) de
  /// basculer. Sinon `null`.
  ///
  /// Conservateur volontairement : on ne propose pas quand l'utilisatrice a
  /// déjà choisi une langue *en présence* de celle de son OS (choix assumé) —
  /// uniquement quand la nouvelle langue n'existait pas encore. Le dropdown
  /// des réglages reste l'échappatoire pour tous les autres cas.
  Future<Locale?> pendingNewLocaleOffer() async {
    if (_needsLanguageSelection) return null;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored == null) return null; // suit déjà l'OS, rien à proposer

    final knownAtChoice =
        (prefs.getStringList(_knownLocalesKey) ?? _supportedCodes()).toSet();
    final system = PlatformDispatcher.instance.locale.languageCode;

    if (_isSupportedLanguage(system) &&
        !knownAtChoice.contains(system) &&
        system != _current.languageCode) {
      return Locale(system);
    }
    // Lecture pure : l'ensemble « connu » n'est mis à jour qu'à un choix
    // explicite ([setLocale]) ou un refus ([keepCurrentLocale]).
    return null;
  }

  /// L'utilisatrice a refusé la bascule proposée par [pendingNewLocaleOffer]
  /// (ou ignoré la boîte de dialogue) : on fige le choix courant comme
  /// explicite et on prend acte des locales actuelles → plus jamais reproposé.
  Future<void> keepCurrentLocale() => setLocale(_current);

  List<String> _supportedCodes() =>
      kSupportedLocales.map((l) => l.languageCode).toList();

  bool _isSupportedLanguage(String code) {
    for (final l in kSupportedLocales) {
      if (l.languageCode == code) return true;
    }
    return false;
  }
}
