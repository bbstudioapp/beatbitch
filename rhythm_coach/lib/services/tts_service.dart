import 'dart:async' show unawaited;
import 'dart:convert' show json, utf8;
import 'dart:io'
    show Directory, File, Platform, Process, ProcessException, ProcessResult;
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
    'de': [
      'de-de-x-deg-local',
      'de-de-x-de2-local',
      'de-de-x-nfh-local',
      'de-de-x-deb-local',
    ],
  };

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  Locale _locale;

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

    // Linux : le plugin flutter_tts ne déclare aucun pluginClass pour
    // Linux → tout appel sur le method channel jette
    // MissingPluginException. On ne touche pas au plugin et on délègue à
    // `piper` (préféré, voix neuronale) ou `spd-say` (fallback) selon ce
    // qui est installé. Cf. _speakLinux / docs/LINUX_TTS.md.
    if (_isLinux) {
      await _ensurePiperResolved();
      _currentVoiceName =
          _piperConfig != null ? _linuxPiperVoiceLabel : _linuxVoiceLabel;
      _initialized = true;
      return;
    }

    await _tts.setLanguage(_ttsLanguageTag(_locale));
    await _tts.setPitch(_platformDefaultPitch);
    await _tts.setSpeechRate(_platformDefaultRate);
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

  Future<void> _selectVoice() async {
    return _selectVoiceWithSeed(null);
  }

  /// Comme [_selectVoice], mais rotate la liste de voix préférées selon un
  /// hash du `seed`. Permet à plusieurs presets coach (qui partagent la même
  /// locale fallback) d'avoir chacun une voix distincte. Avec `seed == null`,
  /// se comporte comme avant (1ère voix de la liste).
  Future<void> _selectVoiceWithSeed(String? seed) async {
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
    final resolved = resolveText(text);
    try {
      if (_isLinux) {
        await _speakLinux(resolved);
        return;
      }
      await _tts.speak(resolved);
    } catch (e) {
      _speaking = false;
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
    _speaking = false;
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
    await _tts.setSpeechRate(_rate);
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    if (_isLinux) return; // appliqué par appel à _speakLinux
    await _tts.setPitch(_pitch);
  }

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
    // Linux : pas de sélection de voix, mais on garde le rate/pitch du
    // coach — c'est ce qui distingue les coachs entre eux.
    if (_isLinux) {
      if (rate != null) await setRate(rate);
      if (pitch != null) await setPitch(pitch);
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
