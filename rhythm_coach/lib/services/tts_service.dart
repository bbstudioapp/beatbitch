import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'user_profile_service.dart';

class TtsService {
  static const double _defaultPitch = 1.13;
  static const double _defaultRate = 0.56;
  static const double _defaultVolume = 1.0;

  // Windows : Microsoft Julie (SAPI) est la seule voix FR locale fiable
  // sur la plupart des postes. On la force comme voix par defaut ET
  // pour tous les coachs (les voix Android `fr-fr-x-*-local` n'existent
  // pas sous SAPI). Rate/pitch ajustes pour Julie specifiquement.
  static const double _windowsDefaultPitch = 1.22;
  static const double _windowsDefaultRate = 0.68;
  // Match case-insensitive sur le nom de voix : couvre "Microsoft Julie
  // Desktop", "Julie - French (France)", etc. selon les variantes SAPI.
  static const String _windowsVoiceNeedle = 'julie';

  /// Voix préférées par locale, par ordre décroissant de qualité. **Voix
  /// locales uniquement** : on n'autorise jamais de voix réseau (cf.
  /// [_isLocalVoice]) — les voix `-network` envoient le texte aux serveurs
  /// Google, ce qui est inacceptable vu le contenu des phrases (intime,
  /// cru). Pour les autres locales : pas de préférence hardcodée — fallback
  /// gender=female puis première voix locale disponible.
  static const Map<String, List<String>> _preferredVoiceNamesByLanguage = {
    'fr': [
      'fr-fr-x-fra-local',
      'fr-fr-x-vlf-local',
      'fr-fr-x-frd-local',
      'fr-fr-x-frc-local',
    ],
    'en': [
      'en-gb-x-gba-local',
      'en-gb-x-fis-local',
      'en-us-x-tpf-local',
      'en-us-x-iol-local',
      'en-us-x-sfg-local',
    ],
  };

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  Locale _locale;

  /// Optionnel : si fourni, toutes les phrases passent par `resolve` avant
  /// d'être prononcées (substitution `{name}`).
  UserProfileService? _profile;

  /// Optionnel : override de résolution `{name}`. Quand non-null, il prime
  /// sur `_profile.resolve` — utile pour qu'un coach Carrière utilise son
  /// propre pool de surnoms le temps d'une session. À retirer en passant
  /// `null` à la fin de la session.
  String Function(String text)? _nameResolverOverride;

  // État courant exposé pour permettre aux écrans (ex: SONS) d'afficher
  // les bons défauts de slider et de sélecteur.
  double _rate = _platformDefaultRate;
  double _pitch = _platformDefaultPitch;
  String? _currentVoiceName;

  static bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  static double get _platformDefaultRate =>
      _isWindows ? _windowsDefaultRate : _defaultRate;
  static double get _platformDefaultPitch =>
      _isWindows ? _windowsDefaultPitch : _defaultPitch;

  TtsService({Locale locale = const Locale('fr')}) : _locale = locale;

  /// True tant que le moteur TTS est en train de prononcer une phrase.
  /// Permet aux scheduleurs (commentaires aléatoires) d'éviter de
  /// déclencher une nouvelle phrase qui interromprait l'actuelle (le mode
  /// par défaut de flutter_tts est QUEUE_FLUSH : un nouveau speak() coupe
  /// le précédent).
  bool get isSpeaking => _speaking;

  double get currentRate => _rate;
  double get currentPitch => _pitch;
  String? get currentVoiceName => _currentVoiceName;
  Locale get locale => _locale;

  /// Valeurs par défaut, exposées pour les UI qui veulent réinitialiser.
  /// Sur Windows, retourne les valeurs calibrees pour Microsoft Julie.
  static double get defaultRate => _platformDefaultRate;
  static double get defaultPitch => _platformDefaultPitch;

  void attachProfile(UserProfileService profile) {
    _profile = profile;
  }

  /// Pose ou retire un override de résolution `{name}`. Passe `null` pour
  /// rendre la main au resolver du `UserProfileService`.
  void setNameResolver(String Function(String text)? resolver) {
    _nameResolverOverride = resolver;
  }

  /// Résout les placeholders `{name}` d'un texte selon la même règle que
  /// `speak()` : override coach > resolver user > pass-through. Sert aux
  /// widgets qui doivent afficher le même texte que celui qui sera lu
  /// (panel d'intro, sous-titres éventuels) — sinon l'utilisateur voit
  /// `{name}` à l'écran alors qu'il entend le bon surnom.
  String resolveText(String text) {
    final override = _nameResolverOverride;
    if (override != null) return override(text);
    return _profile?.resolve(text) ?? text;
  }

  Future<void> init() async {
    if (_initialized) return;

    await _tts.setLanguage(_ttsLanguageTag(_locale));
    await _tts.setPitch(_platformDefaultPitch);
    await _tts.setSpeechRate(_platformDefaultRate);
    await _tts.setVolume(_defaultVolume);
    // `awaitSpeakCompletion(true)` est défaillant sur Windows : la
    // back-end SAPI n'émet pas toujours l'event de complétion attendu,
    // ce qui fait freeze/crash le `speak()` suivant. On le garde activé
    // sur les plateformes où il marche fiablement (Android/iOS).
    if (defaultTargetPlatform != TargetPlatform.windows) {
      await _tts.awaitSpeakCompletion(true);
    }
    await _selectVoice();

    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((msg) => _speaking = false);

    _initialized = true;
  }

  /// Change la locale courante du moteur TTS et resélectionne une voix.
  /// Reste idempotent si la locale est identique.
  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode &&
        _locale.countryCode == locale.countryCode) {
      return;
    }
    _locale = locale;
    if (_initialized) {
      await _tts.setLanguage(_ttsLanguageTag(_locale));
      await _selectVoice();
    }
  }

  /// Construit le tag BCP-47 attendu par flutter_tts (`fr-FR`, `en-US`…).
  /// Si pas de pays explicite, on utilise la convention système : la même
  /// chaîne en majuscules pour le pays (`fr` → `fr-FR`, `en` → `en-US`).
  String _ttsLanguageTag(Locale l) {
    final country = l.countryCode ?? _defaultCountryFor(l.languageCode);
    return '${l.languageCode}-$country';
  }

  String _defaultCountryFor(String lang) {
    switch (lang) {
      case 'fr':
        return 'FR';
      case 'en':
        return 'US';
      case 'de':
        return 'DE';
      case 'es':
        return 'ES';
      case 'it':
        return 'IT';
      case 'pt':
        return 'PT';
      default:
        return lang.toUpperCase();
    }
  }

  Future<void> _selectVoice() async {
    return _selectVoiceWithSeed(null);
  }

  /// Comme [_selectVoice], mais rotate la liste de voix préférées selon un
  /// hash du `seed`. Permet à plusieurs presets coach (qui partagent la même
  /// locale fallback) d'avoir chacun une voix distincte. Avec `seed == null`,
  /// se comporte comme avant (1ère voix de la liste).
  Future<void> _selectVoiceWithSeed(String? seed) async {
    try {
      final voices = await listVoicesForLocale(_locale);
      if (voices.isEmpty) return;

      Map<String, String>? pick;

      // Override Windows : on cherche d'abord Julie (case-insensitive),
      // peu importe le seed/coach. Sur SAPI il n'y a generalement qu'une
      // seule voix FR locale fiable, donc tous les coachs partagent
      // Julie ; leur identite reste portee par le texte/rate/pitch.
      if (_isWindows && _locale.languageCode == 'fr') {
        pick = voices.firstWhereOrNull(
          (v) => (v['name'] ?? '').toLowerCase().contains(_windowsVoiceNeedle),
        );
      }

      if (pick == null) {
        final basePreferred =
            _preferredVoiceNamesByLanguage[_locale.languageCode] ??
                const <String>[];
        final preferred = (seed != null && basePreferred.isNotEmpty)
            ? _rotateForSeed(basePreferred, seed)
            : basePreferred;

        for (final name in preferred) {
          pick = voices.firstWhereOrNull(
            (v) => (v['name'] ?? '') == name,
          );
          if (pick != null) break;
        }
        pick ??= _fallbackPick(voices);
      }
      if (pick == null) return;

      final name = pick['name'];
      final localeTag = pick['locale'];
      if (name != null && localeTag != null) {
        await _tts.setVoice({'name': name, 'locale': localeTag});
        _currentVoiceName = name;
        if (kDebugMode) {
          debugPrint('[TTS] voix sélectionnée : $name ($localeTag)');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[TTS] sélection voix échouée : $e');
    }
  }

  static List<String> _rotateForSeed(List<String> list, String seed) {
    if (list.isEmpty) return list;
    final idx = seed.hashCode.abs() % list.length;
    return [...list.sublist(idx), ...list.sublist(0, idx)];
  }

  Map<String, String>? _fallbackPick(List<Map<String, String>> voices) {
    return voices.firstWhereOrNull((v) {
          final gender = (v['gender'] ?? '').toLowerCase();
          return gender == 'female';
        }) ??
        voices.firstWhereOrNull((v) {
          final name = (v['name'] ?? '').toLowerCase();
          return name.contains('female') || name.contains('femme');
        }) ??
        voices.first;
  }

  Future<void> speak(String text) async {
    if (!_initialized) await init();
    if (text.trim().isEmpty) return;
    try {
      await _tts.speak(resolveText(text));
    } catch (e) {
      _speaking = false;
      if (kDebugMode) debugPrint('[TTS] speak KO : $e');
    }
  }

  Future<void> stop() async {
    _speaking = false;
    try {
      await _tts.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('[TTS] stop KO : $e');
    }
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.1, 1.0);
    await _tts.setSpeechRate(_rate);
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    await _tts.setPitch(_pitch);
  }

  Future<void> setVolume(double volume) =>
      _tts.setVolume(volume.clamp(0.0, 1.0));

  /// Liste les voix disponibles pour la locale donnée (filtrage sur
  /// `locale.startsWith(languageCode)`). Si `locale` est null, retourne
  /// toutes les voix du moteur (utile pour exposer un sélecteur sans
  /// restriction de langue).
  ///
  /// **Filtre voix locales uniquement** par défaut : les voix `-network`
  /// (Google Cloud) sont exclues — elles transmettent chaque phrase aux
  /// serveurs Google. `includeNetwork: true` pour outrepasser (debug).
  Future<List<Map<String, String>>> listVoicesForLocale(
      [Locale? locale, bool includeNetwork = false]) async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    var all = raw
        .whereType<Map>()
        .map((v) => v.map((k, val) => MapEntry(k.toString(), val.toString())))
        .toList();
    if (!includeNetwork) {
      all = all.where(_isLocalVoice).toList();
    }
    if (locale == null) return all;
    final code = locale.languageCode.toLowerCase();
    return all
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith(code))
        .toList();
  }

  /// Variante : toutes les voix locales du moteur, sans filtre de locale.
  Future<List<Map<String, String>>> listAllVoices() =>
      listVoicesForLocale(null);

  /// Heuristique « voix hors-ligne ». La convention Google Android TTS
  /// suffixe les voix online par `-network` (ex: `fr-fr-x-fra-network`)
  /// et les voix offline par `-local`. Côté features, certaines builds de
  /// `flutter_tts` exposent `networkConnectionRequired` dans la liste de
  /// features (stringifiée à ce stade). On exclut sur l'un ou l'autre
  /// indice — toute ambiguïté penche vers « probablement local » pour ne
  /// pas masquer une voix légitime à l'utilisateur.
  static bool _isLocalVoice(Map<String, String> v) {
    final name = (v['name'] ?? '').toLowerCase();
    if (name.contains('-network') || name.contains('network')) return false;
    final features = (v['features'] ?? '').toLowerCase();
    if (features.contains('networkconnectionrequired') ||
        features.contains('networkrequired')) {
      return false;
    }
    return true;
  }

  Future<List<Map<String, String>>> listEngines() async {
    final raw = await _tts.getEngines;
    if (raw is! List) return const [];
    return raw.map((e) => {'name': e.toString()}).toList();
  }

  Future<void> setVoiceByName(String name, String locale) async {
    try {
      await _tts.setVoice({'name': name, 'locale': locale});
      _currentVoiceName = name;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TTS] setVoiceByName KO ($name/$locale) : $e');
      }
    }
  }

  /// Applique un preset vocal coach : voix nommée + rate + pitch. Toute
  /// valeur null laisse le réglage courant intact. Utilisé au start d'une
  /// session carrière pour donner sa « couleur vocale » à chaque coach
  /// (cf. `assets/career/coaches/<id>.json` → `tts.voice/rate/pitch`).
  ///
  /// Si la voix demandée n'existe pas sur l'appareil, on tombe sur
  /// `_selectVoice()` (auto-sélection préférée locale) plutôt que
  /// d'échouer silencieusement avec une voix exotique.
  Future<void> applyCoachVoicePreset({
    String? voiceName,
    String? voiceLocale,
    double? rate,
    double? pitch,
  }) async {
    if (!_initialized) await init();
    // Override Windows : tous les coachs utilisent Julie + rate/pitch
    // Windows par defaut. Les voix Android-specifiques (`fr-fr-x-*-local`)
    // n'existent pas sous SAPI, et on n'a typiquement qu'une voix FR
    // locale correcte (Julie) — donc pas de variation de voix possible.
    // Les coachs gardent leur identite via leurs phrases.
    if (_isWindows) {
      await _selectVoice();
      await setRate(_windowsDefaultRate);
      await setPitch(_windowsDefaultPitch);
      return;
    }
    // Le preset coach est défini en dur dans le JSON meta (lang-indépendant)
    // mais référence une voix d'une langue précise (ex: `fr-fr-x-fra-local`).
    // Si la locale active diffère, on ignore la voix nommée et on laisse
    // `_selectVoice()` choisir une voix de la locale courante via
    // `_preferredVoiceNamesByLanguage`. Le rate/pitch du coach (sa couleur
    // vocale) est en revanche conservé — c'est ce qui distingue les coachs
    // entre eux indépendamment de la langue.
    final localeMatchesVoice = voiceName == null ||
        voiceLocale == null ||
        voiceLocale
            .toLowerCase()
            .startsWith(_locale.languageCode.toLowerCase());
    if (voiceName != null && localeMatchesVoice) {
      try {
        final voices = await listVoicesForLocale();
        final match = voices.firstWhereOrNull(
          (v) => (v['name'] ?? '') == voiceName,
        );
        if (match != null) {
          await setVoiceByName(
            voiceName,
            voiceLocale ?? match['locale'] ?? _ttsLanguageTag(_locale),
          );
        } else {
          if (kDebugMode) {
            debugPrint('[TTS] preset coach : voix « $voiceName » introuvable, '
                'fallback auto');
          }
          await _selectVoice();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[TTS] applyCoachVoicePreset KO : $e');
      }
    } else if (voiceName != null) {
      // La voix demandée n'est pas dans la langue active : pioche une voix
      // dans la liste préférée de la locale courante en utilisant un hash
      // du voiceName comme seed. Chaque coach a donc une voix distincte
      // (déterministe), au lieu que les 6 coaches partagent la 1ère voix
      // de la liste — ça préserve une partie de leur identité vocale.
      if (kDebugMode) {
        debugPrint('[TTS] preset coach : voix « $voiceName » '
            '(locale=$voiceLocale) ne matche pas la locale active '
            '${_locale.languageCode} — fallback rotated');
      }
      await _selectVoiceWithSeed(voiceName);
    }
    if (rate != null) await setRate(rate);
    if (pitch != null) await setPitch(pitch);
  }

  /// Réinitialise voix/rate/pitch aux valeurs par défaut. Appelé en sortie
  /// de session carrière pour ne pas qu'un preset coach contamine les
  /// autres écrans (SONS, autre coach, scénario hors carrière).
  Future<void> restoreDefaultVoicePreset() async {
    if (!_initialized) await init();
    await setRate(_platformDefaultRate);
    await setPitch(_platformDefaultPitch);
    await _selectVoice();
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
