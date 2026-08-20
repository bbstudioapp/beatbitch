import 'dart:async' show Timer, unawaited;
import 'dart:convert' show json, utf8;
import 'dart:io'
    show Directory, File, Platform, Process, ProcessException, ProcessResult;
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile_service.dart';

class TtsService {
  /// Préfixe de la clé qui mémorise le choix de voix **explicite** de
  /// l'utilisateur, une entrée par langue (`tts.voice.en`, `tts.voice.de`…).
  /// Cf. [setUserVoice] pour le pourquoi du découpage par langue.
  static const String _userVoicePrefsPrefix = 'tts.voice.';

  /// Préfixe de la clé qui mémorise la voix choisie **pour un coach donné**,
  /// une entrée par coach et par langue
  /// (`tts.voice.coach.coach_07_marc.en`). Miroir strict de
  /// [_userVoicePrefsPrefix] : même découpage par langue, mêmes règles de
  /// repli. Cf. [setCoachVoice].
  ///
  /// Le `coachId` est une chaîne **opaque** : la clé se compose, elle ne se
  /// parse jamais (un id pourrait contenir un point). Pour énumérer, itérer
  /// sur le catalogue de coachs et recomposer.
  static const String _coachVoicePrefsPrefix = 'tts.voice.coach.';

  /// Clés du débit et de la hauteur choisis par l'utilisateur pour la voix
  /// par défaut.
  ///
  /// **Pas de découpage par langue**, contrairement à
  /// [_userVoicePrefsPrefix] : une voix est un objet de sa langue — celle
  /// d'un moteur anglais n'existe pas en allemand — alors qu'un débit est un
  /// confort d'écoute, et le même nombre y a le même sens partout.
  static const String _userRatePrefsKey = 'tts.rate';
  static const String _userPitchPrefsKey = 'tts.pitch';

  /// Préfixes des clés qui mémorisent le débit et la hauteur réglés **pour
  /// un coach donné** (`tts.rate.coach.coach_07_marc`).
  ///
  /// Une entrée par coach, **pas** par langue — à la différence de
  /// [_coachVoicePrefsPrefix], et pour la même raison qu'au-dessus : le
  /// preset d'origine que ce réglage remplace est lui-même déclaré une seule
  /// fois dans le JSON du coach, sans distinction de langue.
  ///
  /// `coachId` opaque, clé composée et jamais parsée (cf.
  /// [_coachVoicePrefsPrefix]).
  static const String _coachRatePrefsPrefix = 'tts.rate.coach.';
  static const String _coachPitchPrefsPrefix = 'tts.pitch.coach.';

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

  /// Linux : le plugin `flutter_tts` n'a pas d'implémentation Linux (cf.
  /// son `pubspec.yaml` qui ne déclare que android/ios/macos/windows/web).
  /// On bypass donc le plugin et on choisit l'un de deux backends détectés
  /// au runtime :
  ///
  /// 1. **piper** (TTS neuronal, voix naturelle) — si `piper` est dans le
  ///    PATH et au moins un fichier `.onnx` est posé dans un dossier
  ///    conventionnel (cf. [_PiperResolver._candidateDirs]). C'est le
  ///    backend préféré : qualité bien supérieure à espeak-ng.
  /// 2. **spd-say** (CLI de speech-dispatcher) — fallback. Toujours
  ///    disponible (déclaré comme dépendance Linux du paquet), mais utilise
  ///    par défaut espeak-ng → voix très robotique.
  ///
  /// La sélection est faite au 1er `speak()` et mémoïsée. Cf.
  /// `docs/LINUX_TTS.md` pour l'installation de piper côté utilisateur.
  static const String _linuxVoiceLabel = 'spd-say (système)';
  static const String _linuxPiperVoiceLabel = 'piper (neuronal)';

  /// Voix préférées par locale, par ordre décroissant de qualité. **Voix
  /// locales uniquement** : on n'autorise jamais de voix réseau (cf.
  /// [_isLocalVoice]) — les voix `-network` envoient le texte aux serveurs
  /// Google, ce qui est inacceptable vu le contenu des phrases (intime,
  /// cru). Pour les autres locales : pas de préférence hardcodée — on retombe
  /// sur [_fallbackPick] (voix déclarée féminine quand le moteur le dit,
  /// sinon la première voix locale disponible).
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
    'de': [
      'de-de-x-deg-local',
      'de-de-x-de2-local',
      'de-de-x-nfh-local',
      'de-de-x-deb-local',
    ],
    'es': [
      'es-es-x-eef-local',
      'es-es-x-ana-local',
      'es-es-x-esc-local',
      'es-us-x-sfb-local',
    ],
  };

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  Locale _locale;

  /// Durée au-delà de laquelle un énoncé est considéré comme terminé même
  /// sans callback du moteur. Le contenu le plus long de l'app (le briefing
  /// du tutoriel, ~380 caractères) tient en une trentaine de secondes au débit
  /// configuré : la marge ×2 garantit qu'aucune phrase réelle n'est écourtée.
  static const Duration _maxUtteranceDuration = Duration(seconds: 60);

  /// Filet de sécurité de [_speaking]. Le drapeau ne redescend normalement que
  /// sur un callback du moteur (`onDone` / `onCancel` / `onError`) ; quand le
  /// moteur signale le début d'un énoncé et ne signale jamais rien d'autre
  /// (service TTS Android déconnecté, `onend` avalé par Safari/PWA), il
  /// resterait à `true` pour le reste de la vie du service — plus aucun
  /// commentaire aléatoire ne serait prononcé de la séance.
  Timer? _speakingWatchdog;

  /// Processus aplay en cours (backend piper) ou null. Tenu pour pouvoir
  /// l'interrompre depuis [stop] — `Process.run('spd-say', ['-S'])` ne
  /// peut pas couper un pipeline piper→aplay externe.
  Process? _linuxAplayProcess;
  Process? _linuxPiperProcess;

  /// Posé à true par [stop] le temps d'absorber l'interruption d'un speak
  /// en cours. Empêche `_speakLinux` de retomber sur le fallback spd-say
  /// après un kill volontaire de piper — sinon l'utilisateur entend la
  /// phrase intégralement relancée juste après avoir cliqué "stop" / "Je
  /// suis prête" (cf. issue #85 : "Boutons session custom non réactifs").
  bool _linuxStopRequested = false;

  /// Mémoization de la résolution piper. Calculée lazy au 1er speak,
  /// réévaluée jamais (le user doit relancer l'app après avoir installé
  /// piper / posé une nouvelle voix). `null` après résolution = piper
  /// indisponible, fallback spd-say.
  _PiperConfig? _piperConfig;
  bool _piperResolved = false;
  Future<void>? _piperResolving;

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
  static bool get _isLinux => defaultTargetPlatform == TargetPlatform.linux;
  static double get _platformDefaultRate =>
      _isWindows ? _windowsDefaultRate : _defaultRate;
  static double get _platformDefaultPitch =>
      _isWindows ? _windowsDefaultPitch : _defaultPitch;

  // Web Speech API : rate ∈ [0.1, 10] avec 1.0 = vitesse normale.
  // flutter_tts (Android/iOS) : rate ∈ [0, 1] avec ~0.5 = vitesse normale.
  // On stocke le rate logique (calibré Android) et on remappe ×2 sur web
  // pour que la même valeur produise la même vitesse perçue partout —
  // évite que les `tts.rate` baked des coachs (~0.55) sonnent en demi-vitesse.
  static double _effectiveRate(double logical) =>
      kIsWeb ? (logical * 2.0).clamp(0.1, 10.0) : logical;

  TtsService({Locale locale = const Locale('fr')}) : _locale = locale;

  /// True tant que le moteur TTS est en train de prononcer une phrase.
  /// Permet aux scheduleurs (commentaires aléatoires) d'éviter de
  /// déclencher une nouvelle phrase qui interromprait l'actuelle (le mode
  /// par défaut de flutter_tts est QUEUE_FLUSH : un nouveau speak() coupe
  /// le précédent).
  bool get isSpeaking => _speaking;

  /// Marque le début d'un énoncé et (ré)arme le watchdog de [_speakingWatchdog].
  void _markSpeaking() {
    _speaking = true;
    _speakingWatchdog?.cancel();
    _speakingWatchdog = Timer(_maxUtteranceDuration, () => _speaking = false);
  }

  /// Marque la fin d'un énoncé et désarme le watchdog.
  void _markNotSpeaking() {
    _speakingWatchdog?.cancel();
    _speakingWatchdog = null;
    _speaking = false;
  }

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

    // Linux : le plugin flutter_tts ne déclare aucun pluginClass pour
    // Linux → tout appel sur le method channel jette
    // MissingPluginException. On ne touche pas au plugin et on délègue à
    // `piper` (préféré, voix neuronale) ou `spd-say` (fallback) selon ce
    // qui est installé. Cf. _speakLinux / docs/LINUX_TTS.md.
    if (_isLinux) {
      await _ensurePiperResolved();
      _currentVoiceName =
          _piperConfig != null ? _linuxPiperVoiceLabel : _linuxVoiceLabel;
      // Avant le retour : le backend `spd-say` lit `_rate` et `_pitch` à
      // chaque énoncé (cf. [_speakViaSpd]), le réglage y a donc prise même
      // là où choisir une voix n'en a aucune.
      await _applyStoredUserRateAndPitch();
      _initialized = true;
      return;
    }

    await _tts.setLanguage(_ttsLanguageTag(_locale));
    await _applyStoredUserRateAndPitch();
    await _tts.setVolume(_defaultVolume);
    // `awaitSpeakCompletion(true)` est défaillant sur Windows (SAPI) :
    // SAPI n'émet pas toujours l'event de complétion attendu, ce qui
    // fait freeze/crash le `speak()` suivant. On le garde activé sur les
    // plateformes où il marche fiablement (Android/iOS). Linux passe par
    // spd-say -w qui fait son propre wait (cf. _speakLinux).
    if (!_isWindows) {
      await _tts.awaitSpeakCompletion(true);
    }
    await _selectVoice();

    _tts.setStartHandler(_markSpeaking);
    _tts.setCompletionHandler(_markNotSpeaking);
    _tts.setCancelHandler(_markNotSpeaking);
    _tts.setErrorHandler((msg) => _markNotSpeaking());

    _initialized = true;
  }

  /// Promesse de la dernière transition de locale en cours, ou `null` si
  /// aucune. Partagée pour que les appels concurrents (listener
  /// `LocaleService` + UI qui veut resync) attendent tous la même
  /// `_selectVoice()` au lieu de retourner immédiatement parce que
  /// `_locale` a déjà été muté synchroniquement par le premier appelant.
  Future<void>? _setLocalePending;

  /// Change la locale courante du moteur TTS et resélectionne une voix.
  /// Idempotent si la locale est identique (retourne la transition en cours
  /// le cas échéant).
  Future<void> setLocale(Locale locale) {
    if (_locale.languageCode == locale.languageCode &&
        _locale.countryCode == locale.countryCode) {
      return _setLocalePending ?? Future.value();
    }
    final pending = _doSetLocale(locale);
    _setLocalePending = pending;
    pending.whenComplete(() {
      if (identical(_setLocalePending, pending)) _setLocalePending = null;
    });
    return pending;
  }

  Future<void> _doSetLocale(Locale locale) async {
    _locale = locale;
    if (!_initialized || _isLinux) return;
    await _tts.setLanguage(_ttsLanguageTag(_locale));
    await _selectVoice();
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

  /// Sélection de la voix « par défaut » (hors coach) : celle qui vaut au
  /// démarrage, après un changement de langue, et en sortie de session
  /// carrière.
  ///
  /// **Un choix explicite de l'utilisateur prime sur l'auto-sélection.** La
  /// liste [_preferredVoiceNamesByLanguage] n'est qu'un défaut : elle ne
  /// s'applique que si l'utilisateur n'a jamais choisi pour cette langue (ou
  /// si la voix qu'il avait choisie n'est plus installée).
  ///
  /// Les presets coach passent par [_selectVoiceWithSeed], qui reste de
  /// l'auto-sélection pure : pendant sa séance, un coach garde sa voix.
  ///
  /// [lead] : passe d'écriture appelante, quand il y en a une (cf.
  /// [_voiceLead]) — la sélection s'interrompt si elle perd la main.
  Future<void> _selectVoice({int? lead}) async {
    if (await _applyStoredUserVoice(lead: lead)) return;
    return _selectVoiceWithSeed(null, lead: lead);
  }

  /// Réapplique le choix de voix de l'utilisateur pour la langue courante.
  /// Retourne `true` si la voix a bien été poussée au moteur.
  Future<bool> _applyStoredUserVoice({int? lead}) async {
    // Linux : pas de sélection de voix programmatique, `_currentVoiceName`
    // n'est qu'un label de backend (cf. [_selectVoiceWithSeed]).
    if (_isLinux) return false;
    return _applyStoredVoice(userVoiceKey(_locale.languageCode), lead: lead);
  }

  /// Applique la voix mémorisée sous [prefsKey], si elle existe encore sur
  /// l'appareil. Retourne `true` si la voix a bien été poussée au moteur.
  ///
  /// Repli **silencieux** sur l'auto-sélection si la voix a disparu (pack de
  /// langue désinstallé, moteur TTS changé) — et la préférence est
  /// **conservée** : une voix peut être temporairement absente (moteur en
  /// cours de mise à jour), l'effacer sur un seul constat serait destructif.
  /// Elle reprendra d'elle-même dès que la voix réapparaît.
  Future<bool> _applyStoredVoice(String prefsKey, {int? lead}) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(prefsKey);
    if (stored == null) return false;
    try {
      final voices = await listVoicesForLocale(_locale);
      if (_voiceLeadLost(lead)) return false;
      final match = voices.firstWhereOrNull((v) => (v['name'] ?? '') == stored);
      if (match == null) {
        if (kDebugMode) {
          debugPrint('[TTS] voix choisie « $stored » absente de l\'appareil '
              '— auto-sélection, préférence conservée ($prefsKey)');
        }
        return false;
      }
      await setVoiceByName(
        stored,
        match['locale'] ?? _ttsLanguageTag(_locale),
      );
      return _currentVoiceName == stored;
    } catch (e) {
      if (kDebugMode) debugPrint('[TTS] restauration voix choisie KO : $e');
      return false;
    }
  }

  /// Comme [_selectVoice], mais rotate la liste de voix préférées selon un
  /// hash du `seed`. Permet à plusieurs presets coach (qui partagent la même
  /// locale fallback) d'avoir chacun une voix distincte. Avec `seed == null`,
  /// se comporte comme avant (1ère voix de la liste).
  ///
  /// `skipPreferredVoices` saute la liste `_preferredVoiceNamesByLanguage` :
  /// elle est calibrée féminine, un coach masculin n'y a rien à prendre. On
  /// attaque alors directement `_fallbackPick`. Ce n'est **pas** une demande
  /// de voix masculine : rien ici ne sait en formuler une, cf. [_fallbackPick].
  Future<void> _selectVoiceWithSeed(
    String? seed, {
    bool skipPreferredVoices = false,
    int? lead,
  }) async {
    // Linux : pas de sélection de voix programmatique (ni spd-say CLI ni
    // notre pipeline piper n'exposent une API « setVoice »). Le label
    // reflète juste quel backend a été détecté pour l'écran Profil.
    if (_isLinux) {
      _currentVoiceName =
          _piperConfig != null ? _linuxPiperVoiceLabel : _linuxVoiceLabel;
      return;
    }
    try {
      final voices = await listVoicesForLocale(_locale);
      if (_voiceLeadLost(lead) || voices.isEmpty) return;

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
        // Coach dont aucune voix de `_preferredVoiceNamesByLanguage` ne peut
        // porter la couleur vocale (liste calibrée femelle) : on la saute
        // pour aller direct au fallback.
        if (!skipPreferredVoices) {
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

  /// Dernier recours quand aucune voix de [_preferredVoiceNamesByLanguage]
  /// n'est installée : la première voix déclarée féminine, sinon la première
  /// venue.
  ///
  /// **Ce filtre ne mord pas partout, et jamais là où on l'attendait.** Le
  /// champ `gender` n'existe que sur deux canaux de `flutter_tts` : UWP
  /// (Windows) et `AVSpeechSynthesisVoice` (iOS/macOS natifs, hors cibles).
  /// Android ne remonte que nom, langue, qualité, latence, réseau et
  /// fonctionnalités — `android.speech.tts.Voice` n'expose rien de plus ; le
  /// canal web se limite à nom + langue. Sur ces deux-là, ce repli retourne
  /// donc toujours `voices.first`, et chercher un indice dans le nom n'aide
  /// pas non plus (les voix Google s'appellent `en-gb-x-gbd-local`).
  ///
  /// Le pendant masculin de cette fonction a été **retiré** pour cette
  /// raison : il n'était atteignable que hors Windows et hors Linux — donc
  /// sur Android et le web, exactement là où le genre n'est jamais déclaré.
  /// Sur ces deux canaux, rien ne permet de demander une voix masculine ; un
  /// coach masculin se règle à la main (cf. [setCoachVoice]), seule une
  /// oreille humaine peut trancher.
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
    final resolved = resolveText(text);
    try {
      if (_isLinux) {
        await _speakLinux(resolved);
        return;
      }
      await _tts.speak(resolved);
    } catch (e) {
      _markNotSpeaking();
      if (kDebugMode) debugPrint('[TTS] speak KO : $e');
    }
  }

  /// Route vers piper si dispo+voix matchant la locale, sinon spd-say.
  Future<void> _speakLinux(String text) async {
    _speaking = true;
    _linuxStopRequested = false;
    try {
      await _ensurePiperResolved();
      final cfg = _piperConfig;
      final voice = cfg?.voiceForLocale(_locale.languageCode);
      if (cfg != null && voice != null) {
        final ok = await _speakViaPiper(text, cfg.binaryPath, voice);
        if (ok) return;
        // Si [stop] a tué piper entre-temps, l'utilisateur veut le silence —
        // surtout pas relancer la phrase complète via spd-say. Sans cette
        // garde, un clic sur "Je suis prête" / "Arrêter" voit son TTS
        // immédiatement remplacé par un spd-say plus lent et plus
        // robotique, ce qui donne l'impression que le bouton n'a rien
        // fait (cf. issue #85).
        if (_linuxStopRequested) return;
        // piper a échoué (audio device pris, modèle KO, etc.) : on tente
        // un dernier coup via spd-say plutôt que de rester muet.
      }
      await _speakViaSpd(text);
    } finally {
      _speaking = false;
    }
  }

  /// Pipeline `piper(stdin=texte) | aplay(stdin=PCM brut)`. Garde une ref
  /// sur les deux process pour que [stop] puisse interrompre — un kill de
  /// spd-say (`spd-say -S`) ne touche pas un pipeline piper externe.
  Future<bool> _speakViaPiper(
    String text,
    String binaryPath,
    _PiperVoice voice,
  ) async {
    try {
      final piper = await Process.start(
        binaryPath,
        ['--model', voice.modelPath, '--output_raw'],
      );
      final aplay = await Process.start('aplay', [
        '-r',
        '${voice.sampleRate}',
        '-f',
        'S16_LE',
        '-t',
        'raw',
        '-c',
        '1',
        '-q',
        '-',
      ]);
      _linuxPiperProcess = piper;
      _linuxAplayProcess = aplay;

      // Détourner stderr de piper pour ne pas polluer la console release
      // (piper logge ses stats d'inférence par défaut).
      unawaited(piper.stderr.drain<void>());

      // Stream piper.stdout (PCM brut) → aplay.stdin. `pipe()` ferme le
      // sink quand le stream se termine, donc aplay reçoit EOF auto.
      final pipeDone = piper.stdout.pipe(aplay.stdin);

      piper.stdin.add(utf8.encode(text));
      await piper.stdin.close();
      await pipeDone;

      final code = await aplay.exitCode;
      return code == 0;
    } on ProcessException catch (e) {
      if (kDebugMode) debugPrint('[TTS] piper KO : ${e.message}');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[TTS] piper KO : $e');
      return false;
    } finally {
      _linuxPiperProcess = null;
      _linuxAplayProcess = null;
    }
  }

  /// Fallback : `spd-say -w` (CLI de speech-dispatcher). Toujours dispo en
  /// théorie (dep système du paquet), mais voix robotique par défaut
  /// (espeak-ng).
  Future<void> _speakViaSpd(String text) async {
    try {
      // Mapping : rate `0.1..1.0` (0.5 ≈ normal) → `-r -100..100`.
      // Pitch `0.5..2.0` (1.0 ≈ normal) → `-p -100..100`.
      final rate = ((_rate - 0.5) * 200).clamp(-100.0, 100.0).round();
      final pitch = ((_pitch - 1.0) * 100).clamp(-100.0, 100.0).round();
      await Process.run('spd-say', [
        '-w',
        '-l',
        _locale.languageCode,
        '-r',
        '$rate',
        '-p',
        '$pitch',
        text,
      ]);
    } on ProcessException catch (e) {
      if (kDebugMode) debugPrint('[TTS] spd-say introuvable : ${e.message}');
    }
  }

  /// Résout (1× par session) la dispo piper + la voix la plus pertinente
  /// par langue. Synchronisé : plusieurs `speak()` concurrents partagent
  /// la même résolution. Cf. [_PiperResolver].
  Future<void> _ensurePiperResolved() async {
    if (_piperResolved) return;
    final pending = _piperResolving;
    if (pending != null) {
      await pending;
      return;
    }
    final task = _PiperResolver.resolve().then((cfg) {
      _piperConfig = cfg;
      _piperResolved = true;
      if (kDebugMode) {
        if (cfg == null) {
          debugPrint('[TTS] piper non détecté → fallback spd-say');
        } else {
          debugPrint('[TTS] piper détecté : ${cfg.binaryPath} '
              '(langues : ${cfg.voicesByLang.keys.join(", ")})');
        }
      }
    });
    _piperResolving = task;
    await task;
    _piperResolving = null;
  }

  Future<void> stop() async {
    _markNotSpeaking();
    try {
      if (_isLinux) {
        // Signale au speak en cours (s'il y en a un) que la coupure est
        // volontaire — pas un échec piper à récupérer par fallback spd-say.
        _linuxStopRequested = true;
        // Backend piper : killer le pipeline piper+aplay courant.
        _linuxPiperProcess?.kill();
        _linuxAplayProcess?.kill();
        _linuxPiperProcess = null;
        _linuxAplayProcess = null;
        // Backend spd-say : annule les messages en file de
        // speech-dispatcher. Best-effort — pas grave si spd-say absent
        // ou si on était sur piper. On ne l'attend pas : sur Wayland
        // Ubuntu 24.04 le spawn peut prendre plusieurs centaines de ms,
        // et bloquer ici ferait paraître les boutons "Je suis prête" /
        // "Arrêter" non réactifs (cf. issue #85).
        unawaited(
          Process.run('spd-say', ['-S'])
              .catchError((Object _) => ProcessResult(0, 0, '', '')),
        );
        return;
      }
      await _tts.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('[TTS] stop KO : $e');
    }
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.1, 1.0);
    if (_isLinux) return; // appliqué par appel à _speakLinux
    await _tts.setSpeechRate(_effectiveRate(_rate));
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    if (_isLinux) return; // appliqué par appel à _speakLinux
    await _tts.setPitch(_pitch);
  }

  /// Enregistre le débit **choisi** par l'utilisateur pour la voix par
  /// défaut, et l'applique immédiatement.
  ///
  /// À distinguer de [setRate], qui pousse une valeur au moteur sans rien
  /// mémoriser : les presets coach et les restaurations passent par là et ne
  /// doivent jamais se substituer au choix de l'utilisateur. Même partage
  /// des rôles que [setUserVoice] face à [setVoiceByName] — seule
  /// cette méthode-ci fait autorité.
  ///
  /// C'est la valeur **retenue** qui est mémorisée, pas celle demandée : une
  /// valeur hors plage serait sinon relue puis reclampée à chaque
  /// démarrage, et le réglage rendu ne serait pas celui écrit.
  Future<void> setUserRate(double rate) async {
    await setRate(rate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_userRatePrefsKey, _rate);
  }

  /// Pendant de [setUserRate] pour la hauteur.
  Future<void> setUserPitch(double pitch) async {
    await setPitch(pitch);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_userPitchPrefsKey, _pitch);
  }

  /// Repose le débit et la hauteur choisis par l'utilisateur. Chaque valeur
  /// jamais réglée retombe sur son défaut plateforme — les deux sont
  /// indépendantes, régler l'une n'impose pas l'autre.
  ///
  /// Écrit **toujours** les deux, y compris quand rien n'est mémorisé : c'est
  /// aussi le chemin qui rend l'état vocal après une séance, où le débit posé
  /// par le coach doit repartir quoi qu'il arrive.
  Future<void> _applyStoredUserRateAndPitch({int? lead}) async {
    final prefs = await SharedPreferences.getInstance();
    await _applyRateAndPitch(
      lead,
      prefs.getDouble(_userRatePrefsKey) ?? _platformDefaultRate,
      prefs.getDouble(_userPitchPrefsKey) ?? _platformDefaultPitch,
    );
  }

  /// Clés de persistance du débit et de la hauteur par défaut. Publiques
  /// pour les mêmes raisons que [userVoiceKey] : l'export / import
  /// diagnostic compose les mêmes clés que ce service au lieu d'en dupliquer
  /// les littéraux.
  static String get userRateKey => _userRatePrefsKey;
  static String get userPitchKey => _userPitchPrefsKey;

  Future<void> setVolume(double volume) {
    if (_isLinux) return Future.value(); // spd-say n'a pas d'option volume
    return _tts.setVolume(volume.clamp(0.0, 1.0));
  }

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
    if (_isLinux) {
      // Pseudo-voix unique : reflète le backend détecté (piper si voix
      // posée + binaire dispo, sinon spd-say). Pas de sélection
      // utilisateur — la voix est définie par les fichiers `.onnx`
      // installés (cf. docs/LINUX_TTS.md).
      await _ensurePiperResolved();
      final lang = (locale ?? _locale).languageCode;
      final label = _piperConfig?.voiceForLocale(lang) != null
          ? _linuxPiperVoiceLabel
          : _linuxVoiceLabel;
      return [
        {
          'name': label,
          'locale': '$lang-${_defaultCountryFor(lang)}',
        },
      ];
    }
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
    if (_isLinux) {
      return const [
        {'name': 'speech-dispatcher'},
      ];
    }
    final raw = await _tts.getEngines;
    if (raw is! List) return const [];
    return raw.map((e) => {'name': e.toString()}).toList();
  }

  Future<void> setVoiceByName(String name, String locale) async {
    if (_isLinux) {
      // Pas de sélection de voix via spd-say (CLI) : on track juste le
      // nom pour que l'UI reste cohérente.
      _currentVoiceName = name;
      return;
    }
    try {
      await _tts.setVoice({'name': name, 'locale': locale});
      _currentVoiceName = name;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TTS] setVoiceByName KO ($name/$locale) : $e');
      }
    }
  }

  /// Enregistre un choix de voix **explicite** de l'utilisateur pour la
  /// langue courante, et l'applique immédiatement.
  ///
  /// À distinguer de [setVoiceByName], qui se contente de pousser une voix
  /// au moteur sans rien mémoriser : les presets coach et les rattrapages
  /// d'affichage passent par là, et ne doivent jamais se substituer au choix
  /// de l'utilisateur. Seule cette méthode-ci fait autorité.
  ///
  /// La préférence est **par langue** : une voix anglaise n'aurait pas de
  /// sens quand l'interface passe en allemand. Chaque langue garde donc son
  /// propre choix, et une langue jamais réglée reste en auto-sélection.
  /// Repasser dans une langue déjà réglée y retrouve la voix choisie.
  Future<void> setUserVoice(String name, String locale) async {
    await setVoiceByName(name, locale);
    // Linux : `_currentVoiceName` n'est qu'un label de backend (« piper
    // (neuronal) »), pas une voix sélectionnable — rien à mémoriser.
    if (_isLinux) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userVoiceKey(_locale.languageCode), name);
  }

  /// Clé de persistance de la voix par défaut choisie en [languageCode].
  ///
  /// Publique pour que l'export / import diagnostic compose les mêmes clés
  /// que ce service, au lieu d'en dupliquer les littéraux — une divergence
  /// y serait silencieuse (un réglage exporté sous une clé que la séance ne
  /// lit pas).
  static String userVoiceKey(String languageCode) =>
      '$_userVoicePrefsPrefix$languageCode';

  /// Clé de persistance de la voix choisie pour [coachId] en [languageCode].
  /// Composée, jamais parsée (cf. [_coachVoicePrefsPrefix]). Publique pour
  /// les mêmes raisons que [userVoiceKey].
  static String coachVoiceKey(String coachId, String languageCode) =>
      '$_coachVoicePrefsPrefix$coachId.$languageCode';

  /// `false` là où choisir une voix n'a aucune prise : sur Linux, ni
  /// `spd-say` ni le pipeline piper n'exposent d'API « choisir une voix »
  /// — le timbre y dépend des paquets installés (cf. `docs/LINUX_TTS.md`).
  /// L'UI s'en sert pour **expliquer** plutôt que masquer : un réglage
  /// introuvable relance la même incompréhension qu'un réglage sans effet.
  ///
  /// Volontairement le **même** prédicat que le court-circuit de
  /// [applyCoachVoicePreset], sans garde `kIsWeb` : sur Flutter Web,
  /// `defaultTargetPlatform` est dérivé du navigateur, donc une PWA ouverte
  /// sous Linux se déclare « Linux » des deux côtés. Elle n'y proposera donc
  /// pas un réglage que la séance ignorerait. Neutraliser ce faux positif
  /// relève d'un chantier séparé — il concerne aussi `_isWindows`, et donc le
  /// comportement actuel bien au-delà de ce réglage.
  static bool get supportsVoiceSelection => !_isLinux;

  /// Voix choisie par l'utilisateur pour [coachId] dans la langue courante,
  /// ou `null` si aucune — auquel cas le coach garde sa cascade d'origine.
  Future<String?> coachVoiceName(String coachId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(coachVoiceKey(coachId, _locale.languageCode));
  }

  /// Mémorise la voix [name] pour [coachId] dans la langue courante.
  ///
  /// **N'applique rien tout de suite** : hors séance, la voix du moteur est
  /// celle de l'utilisateur (cf. [setUserVoice]), pas celle d'un coach. Le
  /// réglage prend effet au prochain [applyCoachVoicePreset] de ce coach.
  ///
  /// Par langue, pour les mêmes raisons que [setUserVoice] : une voix
  /// anglaise choisie pour un coach n'existe pas en allemand.
  Future<void> setCoachVoice(String coachId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(coachVoiceKey(coachId, _locale.languageCode), name);
  }

  /// Rend [coachId] à sa cascade d'origine (« Automatique ») en **supprimant**
  /// la clé — on ne stocke jamais une chaîne magique qu'il faudrait ensuite
  /// distinguer d'un vrai nom de voix. Absence de clé = comportement d'origine,
  /// un seul état à raisonner.
  Future<void> clearCoachVoice(String coachId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(coachVoiceKey(coachId, _locale.languageCode));
  }

  /// Clés de persistance du débit et de la hauteur réglés pour [coachId].
  /// Composées, jamais parsées. Publiques pour les mêmes raisons que
  /// [coachVoiceKey].
  static String coachRateKey(String coachId) =>
      '$_coachRatePrefsPrefix$coachId';
  static String coachPitchKey(String coachId) =>
      '$_coachPitchPrefsPrefix$coachId';

  /// Débit et hauteur réglés pour [coachId]. Chaque champ `null` = celui de
  /// son preset d'origine ; les deux se règlent séparément.
  Future<({double? rate, double? pitch})> coachRateAndPitch(
      String coachId) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      rate: prefs.getDouble(coachRateKey(coachId)),
      pitch: prefs.getDouble(coachPitchKey(coachId)),
    );
  }

  /// Mémorise le débit de [coachId]. Comme [setCoachVoice], **n'applique
  /// rien tout de suite** : hors séance le moteur porte le réglage de
  /// l'utilisateur, pas celui d'un coach. Le réglage prend effet au prochain
  /// [applyCoachVoicePreset] de ce coach.
  Future<void> setCoachRate(String coachId, double rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(coachRateKey(coachId), rate.clamp(0.1, 1.0));
  }

  /// Pendant de [setCoachRate] pour la hauteur.
  Future<void> setCoachPitch(String coachId, double pitch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(coachPitchKey(coachId), pitch.clamp(0.5, 2.0));
  }

  /// Rend à [coachId] le débit et la hauteur de son preset d'origine, en
  /// **supprimant** les deux clés — même règle que [clearCoachVoice] :
  /// absence de clé = valeur d'origine, jamais une valeur magique qu'il
  /// faudrait ensuite distinguer d'un vrai réglage.
  ///
  /// Les deux ensemble parce que c'est un seul geste côté écran : « rends-lui
  /// sa voix ». Rien n'empêcherait d'en exposer deux, personne ne l'a demandé.
  Future<void> clearCoachRateAndPitch(String coachId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(coachRateKey(coachId));
    await prefs.remove(coachPitchKey(coachId));
  }

  /// Applique un preset vocal coach : voix nommée + rate + pitch. Toute
  /// valeur null laisse le réglage courant intact. Utilisé au start d'une
  /// session carrière pour donner sa « couleur vocale » à chaque coach
  /// (cf. `assets/career/coaches/<id>.json` → `tts.voice/rate/pitch`).
  ///
  /// Si la voix demandée n'existe pas sur l'appareil, on tombe sur
  /// `_selectVoice()` (auto-sélection préférée locale) plutôt que
  /// d'échouer silencieusement avec une voix exotique.
  ///
  /// [coachId] active les réglages manuels de ce coach — voix, débit,
  /// hauteur — qui priment chacun sur ce que le preset ou la plateforme
  /// aurait posé. Si l'utilisateur a choisi une voix pour ce coach dans la
  /// langue active, elle prime sur toute la cascade. C'est le seul moyen de donner une voix masculine à un coach
  /// masculin — aucun des canaux que la cascade atteint (Android, web) ne
  /// déclare le genre d'une voix (cf. [_fallbackPick]), donc seule une
  /// oreille humaine peut trancher.
  Future<void> applyCoachVoicePreset({
    String? coachId,
    String? voiceName,
    String? voiceLocale,
    double? rate,
    double? pitch,
    bool skipPreferredVoices = false,
  }) async {
    final lead = _voiceLead;
    if (!_initialized) await init();
    // Débit et hauteur réglés à la main pour ce coach : ils priment sur le
    // preset **et** sur ce que la plateforme impose, exactement comme le
    // réglage manuel de voix prime sur le forçage Windows plus bas.
    //
    // Résolus **une seule fois, ici** : cette méthode a quatre sorties, et
    // chacune pousse son propre couple débit/hauteur. Les résoudre au fil des
    // sorties, c'est quatre occasions d'en oublier une.
    final manual = coachId == null
        ? (rate: null, pitch: null)
        : await coachRateAndPitch(coachId);
    // Linux : pas de sélection de voix, mais on garde le rate/pitch du
    // coach — c'est ce qui distingue les coachs entre eux. Ni lecture ni
    // écriture d'un réglage manuel : il n'aurait aucune prise (cf.
    // [supportsVoiceSelection]).
    if (_isLinux) {
      await _applyRateAndPitch(
          lead, manual.rate ?? rate, manual.pitch ?? pitch);
      return;
    }
    // Réglage manuel de l'utilisateur pour ce coach : il prime sur tout le
    // reste, **y compris** le forçage Windows de Julie. Ce forçage est un
    // défaut raisonnable (« une seule voix FR locale correcte »), pas une
    // contrainte technique — et un choix explicite prime sur un défaut,
    // exactement comme `setUserVoice` prime sur l'auto-sélection.
    //
    // Voix disparue de l'appareil : repli silencieux sur la cascade
    // ci-dessous, et la préférence reste en base (cf. [_applyStoredVoice]).
    if (coachId != null &&
        await _applyStoredVoice(coachVoiceKey(coachId, _locale.languageCode),
            lead: lead)) {
      // Ceux du coach, sauf là où l'utilisateur les a réglés lui aussi :
      // choisir un timbre n'impose pas un rythme, et réciproquement.
      await _applyRateAndPitch(
          lead, manual.rate ?? rate, manual.pitch ?? pitch);
      return;
    }
    // Override Windows : tous les coachs utilisent Julie + rate/pitch
    // Windows par defaut. Les voix Android-specifiques (`fr-fr-x-*-local`)
    // n'existent pas sous SAPI, et on n'a typiquement qu'une voix FR
    // locale correcte (Julie) — donc pas de variation de voix possible.
    // Les coachs gardent leur identite via leurs phrases. Un coach masculin
    // reste donc avec une voix Julie féminine sur Windows tant qu'aucune voix
    // n'a été choisie pour lui ci-dessus — dissonance assumée pour cette
    // plateforme, que le réglage manuel lève quand une seconde voix locale
    // existe (en anglais, typiquement).
    if (_isWindows) {
      // `_selectVoiceWithSeed` et non `_selectVoice` : pendant sa séance, le
      // coach garde la voix imposée par la plateforme (Julie), pas celle que
      // l'utilisateur a réglée par ailleurs.
      await _selectVoiceWithSeed(null, lead: lead);
      await _applyRateAndPitch(
        lead,
        manual.rate ?? _windowsDefaultRate,
        manual.pitch ?? _windowsDefaultPitch,
      );
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
        if (_voiceLeadLost(lead)) return;
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
          await _selectVoiceWithSeed(null,
              skipPreferredVoices: skipPreferredVoices, lead: lead);
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
      await _selectVoiceWithSeed(voiceName,
          skipPreferredVoices: skipPreferredVoices, lead: lead);
    } else if (skipPreferredVoices) {
      // Pas de voix nommée, et la liste préférée de la langue ne convient pas
      // à ce coach (Marc) : on relance la sélection auto en la sautant, donc
      // sur la première voix de la locale.
      await _selectVoiceWithSeed(null,
          skipPreferredVoices: skipPreferredVoices, lead: lead);
    }
    await _applyRateAndPitch(lead, manual.rate ?? rate, manual.pitch ?? pitch);
  }

  /// Chaîne des écritures de l'état vocal faites par le **réglage de voix**
  /// (aperçu d'une voix de coach, puis restauration à la fermeture de la
  /// feuille). Cf. [enqueueVoiceOp].
  Future<void> _voiceOps = Future<void>.value();

  /// Numéro de la passe d'écriture qui a la **main** sur l'état vocal.
  ///
  /// Voix, débit et hauteur ne sont pas trois réglages indépendants : ils
  /// font un état composite. Deux écritures qui s'entrelacent en produisent
  /// donc un troisième — le timbre de l'une sur le débit de l'autre — que ni
  /// l'une ni l'autre n'a voulu. Une file ne suffit pas à l'empêcher : elle
  /// ordonne ce qu'on lui confie, elle n'empêche personne d'écrire à côté.
  ///
  /// Chaque écriture composite ([applyCoachVoicePreset],
  /// [restoreDefaultVoicePreset]) capture ce numéro à son démarrage et
  /// cesse d'envoyer quoi que ce soit au moteur dès qu'il a changé. Comme
  /// les invocations déjà parties gardent leur ordre d'émission, l'état
  /// final est intégralement celui de la dernière passe. Seul
  /// [takeVoiceLead] incrémente ce numéro.
  int _voiceLead = 0;

  /// `true` quand la passe [lead] s'est fait reprendre la main. `null` =
  /// écriture hors passe (init, changement de langue), jamais interrompue.
  bool _voiceLeadLost(int? lead) => lead != null && lead != _voiceLead;

  /// Pousse [rate] et [pitch] au moteur tant que la passe [lead] a la main.
  /// `lead` null = écriture hors passe (init), jamais interrompue.
  Future<void> _applyRateAndPitch(
      int? lead, double? rate, double? pitch) async {
    if (rate != null && !_voiceLeadLost(lead)) await setRate(rate);
    if (pitch != null && !_voiceLeadLost(lead)) await setPitch(pitch);
  }

  /// Reprend la main sur l'état vocal, puis exécute [op] **tout de suite**.
  ///
  /// Point d'entrée des presets posés par une **séance**. Ce qu'un réglage a
  /// laissé en vol s'arrête à son prochain point de reprise, ce qu'il a
  /// laissé en attente dans [enqueueVoiceOp] ne démarrera pas, et [op] part
  /// sans rien attendre : une séance qui démarre ne fait jamais la queue
  /// derrière une opération d'interface — un moteur qui tarde à répondre au
  /// réglage ne peut donc pas retenir la séance.
  ///
  /// Le prix est qu'un aperçu ou une restauration en cours est abandonné en
  /// chemin. C'est le bon arbitrage : l'utilisateur vient de demander une
  /// séance, l'état qu'il attend est celui du coach, et une passe
  /// abandonnée ne laisse rien à réparer — la suivante repose voix, débit
  /// et hauteur ensemble.
  Future<void> takeVoiceLead(Future<void> Function() op) {
    _voiceLead++;
    return op();
  }

  /// Enchaîne [op] derrière les écritures de voix déjà en vol, et renvoie
  /// son achèvement.
  ///
  /// **Pourquoi une file plutôt qu'un rattrapage.** La feuille de sélection
  /// se ferme par n'importe quel geste — bouton retour, tap hors zone,
  /// glissement vers le bas — et rend la main **sans attendre** l'aperçu
  /// qu'un `onTap` a lancé. Les deux chaînes écrivent alors le même état :
  /// si la restauration finit la première, l'aperçu repose derrière elle le
  /// timbre, le débit et la hauteur du coach, que le Profil présente ensuite
  /// comme le réglage par défaut de l'utilisateur — la confusion même que ce
  /// réglage existe pour dissiper. La restauration étant toujours la
  /// dernière enfilée, c'est elle qui a le dernier mot, quel que soit le
  /// moment de la fermeture.
  ///
  /// La file est portée par le **service** et non par l'écran qui ouvre la
  /// feuille : c'est l'état du service qu'elle protège, plusieurs écrans
  /// ouvrent la même feuille, et quitter l'écran pendant une opération en
  /// vol ne doit pas repartir d'une file neuve.
  ///
  /// Sa portée s'arrête là : elle ordonne les écritures **du réglage** entre
  /// elles. Elle ne dit rien de celles qu'une séance pose de son côté — et
  /// justement, la durée de vie qui lui permet de survivre à l'écran lui
  /// permet aussi de croiser un démarrage de séance. C'est [takeVoiceLead]
  /// qui tranche ce croisement-là, et une opération enfilée avant qu'une
  /// séance ait pris la main ne démarre plus : elle reposerait l'état
  /// d'avant par-dessus celui du coach.
  Future<void> enqueueVoiceOp(Future<void> Function() op) {
    final lead = _voiceLead;
    final next = _voiceOps.then((_) => _voiceLeadLost(lead) ? null : op());
    // Une opération en échec ne doit pas condamner celles d'après : c'est
    // la restauration qui compte, et elle passe en dernier.
    _voiceOps = next.catchError((Object _) {});
    return next;
  }

  /// Rend la main au réglage hors-carrière. Appelé en sortie de session
  /// carrière pour ne pas qu'un preset coach contamine les autres écrans
  /// (SONS, autre coach, scénario hors carrière).
  ///
  /// Le coach a le droit d'imposer **sa** voix pendant sa séance ; il n'a pas
  /// le droit de détruire le réglage de l'utilisateur en repartant. La voix
  /// restituée est donc celle qu'il a choisie s'il en a une (cf.
  /// [setUserVoice] via [_selectVoice]), et seulement à défaut
  /// l'auto-sélection. Même règle pour le débit et la hauteur : ceux qu'il a
  /// réglés (cf. [setUserRate]), à défaut les défauts plateforme.
  Future<void> restoreDefaultVoicePreset() async {
    final lead = _voiceLead;
    if (!_initialized) await init();
    await _applyStoredUserRateAndPitch(lead: lead);
    if (_voiceLeadLost(lead)) return;
    await _selectVoice(lead: lead);
  }

  Future<void> dispose() async {
    _speakingWatchdog?.cancel();
    _speakingWatchdog = null;
    if (_isLinux) {
      _linuxPiperProcess?.kill();
      _linuxAplayProcess?.kill();
      try {
        await Process.run('spd-say', ['-S']);
      } on ProcessException {
        // pas grave, on ferme l'app
      }
      return;
    }
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

/// Configuration piper résolue : chemin du binaire + voix indexées par
/// code langue (`fr`, `en`, `de`…). Une seule voix par langue est retenue
/// — la 1ʳᵉ trouvée par ordre alphabétique des fichiers `.onnx`.
class _PiperConfig {
  final String binaryPath;
  final Map<String, _PiperVoice> voicesByLang;

  const _PiperConfig({required this.binaryPath, required this.voicesByLang});

  _PiperVoice? voiceForLocale(String languageCode) =>
      voicesByLang[languageCode.toLowerCase()];
}

class _PiperVoice {
  final String modelPath;
  final int sampleRate;

  const _PiperVoice({required this.modelPath, required this.sampleRate});
}

/// Détection paresseuse de piper + des voix posées par l'utilisateur.
/// Pure fonction utilitaire — pas d'état, juste un `resolve()` qui scanne
/// disque/PATH et retourne une config (ou null).
class _PiperResolver {
  /// Dossiers conventionnels où chercher les voix `.onnx`, par priorité
  /// décroissante. Le 1er match par langue gagne.
  static List<String> get _candidateDirs {
    final env = Platform.environment;
    final home = env['HOME'] ?? '';
    final xdg = env['XDG_DATA_HOME'];
    return [
      if (xdg != null && xdg.isNotEmpty) '$xdg/piper-voices',
      if (home.isNotEmpty) '$home/.local/share/piper-voices',
      '/usr/local/share/piper-voices',
      '/usr/share/piper-voices',
    ];
  }

  static Future<_PiperConfig?> resolve() async {
    final bin = await _locateBinary();
    if (bin == null) return null;
    final voices = await _collectVoices();
    if (voices.isEmpty) return null;
    return _PiperConfig(binaryPath: bin, voicesByLang: voices);
  }

  /// `which piper` puis fallback `~/.local/bin/piper` (chemin standard de
  /// `pipx install piper-tts` quand `pipx ensurepath` n'a pas été fait).
  static Future<String?> _locateBinary() async {
    try {
      final res = await Process.run('which', ['piper']);
      final out = (res.stdout as String).trim();
      if (out.isNotEmpty && File(out).existsSync()) return out;
    } on ProcessException {
      // `which` peut manquer dans des conteneurs minimaux — on continue.
    }
    final home = Platform.environment['HOME'];
    if (home != null) {
      final candidate = '$home/.local/bin/piper';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Scanne les dossiers et retourne une voix par code langue. Le code
  /// langue est extrait du préfixe du nom de fichier avant `_` ou `-`
  /// (convention piper : `fr_FR-siwis-medium.onnx` → `fr`).
  static Future<Map<String, _PiperVoice>> _collectVoices() async {
    final byLang = <String, _PiperVoice>{};
    for (final dirPath in _candidateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      final entries = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in entries) {
        if (!f.path.endsWith('.onnx')) continue;
        final base = f.path.split('/').last;
        final lang = base.split(RegExp(r'[_\-]')).first.toLowerCase();
        if (lang.isEmpty) continue;
        if (byLang.containsKey(lang)) continue; // dossier prioritaire gagne
        final sampleRate = await _readSampleRate('${f.path}.json');
        byLang[lang] = _PiperVoice(modelPath: f.path, sampleRate: sampleRate);
      }
    }
    return byLang;
  }

  static Future<int> _readSampleRate(String jsonPath) async {
    try {
      final raw = await File(jsonPath).readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final audio = decoded['audio'] as Map<String, dynamic>?;
      final sr = audio?['sample_rate'];
      if (sr is int) return sr;
      if (sr is num) return sr.toInt();
    } catch (_) {
      // sidecar manquant ou JSON invalide → défaut piper standard
    }
    return 22050;
  }
}
