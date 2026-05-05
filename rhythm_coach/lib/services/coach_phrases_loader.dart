import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'locale_service.dart';

/// Phrases TTS « système » prononcées par le coach hors contenu éditorial
/// (sessions / punitions / commentaires aléatoires) :
/// - rappels de position pendant les holds vérifiés caméra (`HoldVerifier`)
/// - décompte avant démarrage d'une session
/// - phrases de test depuis l'écran SONS
///
/// Une instance par locale. Le fichier `assets/coach/coach_<lang>.json` doit
/// déclarer `"lang": "<lang>"` au top-level (sécurité contre les mismatch).
class CoachPhrases {
  final String lang;
  final List<String> goDeeper;
  final List<String> goUp;
  final List<String> lost;
  final String prepCountdownTemplate;
  final String testVoicePhrase;
  final String testIdentityPhrase;
  final String encoreFallback;

  const CoachPhrases({
    required this.lang,
    required this.goDeeper,
    required this.goUp,
    required this.lost,
    required this.prepCountdownTemplate,
    required this.testVoicePhrase,
    required this.testIdentityPhrase,
    required this.encoreFallback,
  });

  /// Substitue `{seconds}` dans le template du décompte de préparation.
  String prepCountdown(int seconds) =>
      prepCountdownTemplate.replaceAll('{seconds}', seconds.toString());
}

/// Singleton qui maintient la banque de phrases coach pour la locale active.
/// Init asynchrone une fois au démarrage (via [ensureLoaded]). Accès synchrone
/// par [current] ensuite. Recharge auto si la locale change.
class CoachPhrasesService extends ChangeNotifier {
  CoachPhrasesService._();
  static final CoachPhrasesService instance = CoachPhrasesService._();

  CoachPhrases? _current;
  Locale? _loadedFor;
  Future<void>? _inflight;

  CoachPhrases get current {
    final c = _current;
    if (c == null) {
      throw StateError(
        'CoachPhrasesService.current accessed before ensureLoaded() completed.',
      );
    }
    return c;
  }

  bool get isLoaded => _current != null;

  Future<void> ensureLoaded({Locale? locale}) async {
    final target = locale ?? LocaleService.instance.current;
    if (_loadedFor?.languageCode == target.languageCode && _current != null) {
      return;
    }
    if (_inflight != null) {
      await _inflight;
      if (_loadedFor?.languageCode == target.languageCode) return;
    }
    final fut = _doLoad(target);
    _inflight = fut;
    try {
      await fut;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _doLoad(Locale locale) async {
    final loaded = await CoachPhrasesLoader().load(locale);
    _current = loaded;
    _loadedFor = locale;
    notifyListeners();
  }
}

class CoachPhrasesLoader {
  Future<CoachPhrases> load(Locale locale) async {
    final lang = locale.languageCode;
    final path = 'assets/coach/coach_$lang.json';
    String raw;
    try {
      raw = await rootBundle.loadString(path);
    } catch (_) {
      // Fallback FR si la locale demandée n'a pas de pack coach.
      raw = await rootBundle.loadString('assets/coach/coach_fr.json');
    }
    final data = json.decode(raw) as Map<String, dynamic>;
    final declaredLang = (data['lang'] as String?) ?? lang;

    final hold = (data['hold_nudges'] as Map<String, dynamic>?) ?? const {};
    final system = (data['system'] as Map<String, dynamic>?) ?? const {};
    final tests = (data['test_phrases'] as Map<String, dynamic>?) ?? const {};

    List<String> strList(dynamic v) =>
        (v as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

    return CoachPhrases(
      lang: declaredLang,
      goDeeper: strList(hold['go_deeper']),
      goUp: strList(hold['go_up']),
      lost: strList(hold['lost']),
      prepCountdownTemplate: (system['prep_countdown'] as String?) ?? '',
      testVoicePhrase: (tests['voice'] as String?) ?? '',
      testIdentityPhrase: (tests['identity'] as String?) ?? '',
      encoreFallback: (system['encore_fallback'] as String?) ?? '',
    );
  }
}
