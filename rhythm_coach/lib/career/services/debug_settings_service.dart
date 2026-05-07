import 'package:shared_preferences/shared_preferences.dart';

/// Flags de debug visibles dans l'écran SONS. Persiste entre lancements.
class DebugSettingsService {
  static const String _kShowStaminaBar = 'debug.show_stamina_bar';
  static const String _kShowTimer = 'debug.show_timer';
  static const String _kShowHumiliationBar = 'debug.show_humiliation_bar';
  static const String _kShowObedienceBar = 'debug.show_obedience_bar';
  static const String _kShowSalivaBar = 'debug.show_saliva_bar';
  static const String _kShowSessionControls = 'debug.show_session_controls';
  static const String _kShowModeBadge = 'debug.show_mode_badge';
  static const String _kCameraHoldCheck = 'debug.camera_hold_check';
  static const String _kSkipSessionButton = 'debug.skip_session_button';
  static const String _kShowBackgroundMedia = 'pref.show_background_media';

  Future<bool> getShowStaminaBar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowStaminaBar) ?? false;
  }

  Future<void> setShowStaminaBar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowStaminaBar, value);
  }

  /// Quand true, l'écran de session affiche le timer mm:ss à la place
  /// de l'animation des mouvements. Réservé au debug : par défaut, le
  /// téléphone est posé sur le côté et l'utilisatrice n'a pas à lire
  /// le temps qui s'écoule.
  Future<bool> getShowTimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowTimer) ?? false;
  }

  Future<void> setShowTimer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowTimer, value);
  }

  Future<bool> getShowHumiliationBar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowHumiliationBar) ?? false;
  }

  Future<void> setShowHumiliationBar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowHumiliationBar, value);
  }

  Future<bool> getShowObedienceBar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowObedienceBar) ?? false;
  }

  Future<void> setShowObedienceBar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowObedienceBar, value);
  }

  Future<bool> getShowSalivaBar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowSalivaBar) ?? false;
  }

  Future<void> setShowSalivaBar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowSalivaBar, value);
  }

  /// Quand true, l'écran de session affiche les boutons play/pause et stop.
  /// Réservé au debug : en prod, la séance se déroule de bout en bout sans
  /// interaction (téléphone posé sur le côté), seul le bouton FAIL reste
  /// utile.
  Future<bool> getShowSessionControls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowSessionControls) ?? false;
  }

  Future<void> setShowSessionControls(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowSessionControls, value);
  }

  /// Quand true, l'écran de session affiche le badge mode + BPM + position
  /// au-dessus de l'animation. Réservé au debug : en prod l'animation des
  /// mouvements suffit à indiquer ce qui se passe, le téléphone est posé
  /// sur le côté donc ces infos textuelles ne sont pas lues.
  Future<bool> getShowModeBadge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowModeBadge) ?? false;
  }

  Future<void> setShowModeBadge(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowModeBadge, value);
  }

  /// Quand true, la caméra avant vérifie pendant les holds que la position
  /// attendue est tenue. Le coach lance un rappel vocal court si l'utilisateur
  /// dérive plus de ~1.5 s. Pas d'auto-fail à ce niveau.
  ///
  /// Off par défaut : la fonctionnalité demande une calibration préalable et
  /// reste expérimentale tant que le tracking n'a pas été éprouvé en
  /// conditions réelles.
  Future<bool> getCameraHoldCheck() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCameraHoldCheck) ?? false;
  }

  Future<void> setCameraHoldCheck(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCameraHoldCheck, value);
  }

  /// Quand true, l'écran de session expose un bouton « DEBUG : terminer en
  /// succès » qui clôt la séance immédiatement comme si elle avait été
  /// jouée intégralement sans fail (badges, milestones, niveau). Pratique
  /// pour itérer sur le contenu sans devoir rejouer une séance entière.
  Future<bool> getSkipSessionButton() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSkipSessionButton) ?? false;
  }

  Future<void> setSkipSessionButton(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSkipSessionButton, value);
  }

  /// Quand true (défaut), l'écran de session affiche les médias listés
  /// dans `assets/backgrounds.json` en arrière-plan (rotation à chaque
  /// step). Quand false, on retombe sur le placeholder animé (dégradé
  /// radial) — utile si l'utilisatrice n'a posé aucun fichier dans le
  /// dossier ou veut un visuel sobre pour une session donnée.
  Future<bool> getShowBackgroundMedia() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowBackgroundMedia) ?? true;
  }

  Future<void> setShowBackgroundMedia(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowBackgroundMedia, value);
  }
}
