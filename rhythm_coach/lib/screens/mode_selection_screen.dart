import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../career/screens/career_screen.dart';
import '../career/screens/custom_mode_screen.dart';
import '../career/services/career_progress_service.dart';
import '../models/ambience_pack.dart';
import '../services/adult_consent_service.dart';
import '../services/ambience_engine.dart';
import '../services/ambience_pack_loader.dart';
import '../services/backgrounds_loader.dart';
import '../services/backgrounds_service.dart';
import '../services/beep_engine.dart';
import '../services/locale_service.dart';
import '../services/onboarding_service.dart';
import '../services/platform_capabilities.dart';
import '../services/surprise_alert_service.dart';
import '../services/surprise_router.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adult_gate_dialog.dart';
import '../widgets/onboarding_sheet.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'sound_demo_screen.dart';
import 'surprise_settings_screen.dart';

/// Premier écran de l'app : sélection entre Scénario (sessions JSON) et
/// Carrière (sessions générées). Possède les services partagés (TTS, beep,
/// ambiance) qui survivent à la navigation entre les deux modes.
class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen>
    with WidgetsBindingObserver {
  /// Niveau carrière minimum pour débloquer les notifications surprise.
  /// Niveau 5 = palier "Petite Salope Confirmée" — premier palier
  /// non-débutant. Cohérent avec _includeHandUnlockLevel (4) et plus
  /// strict que _quickieUnlockLevel (8).
  static const int _surpriseUnlockLevel = 5;

  late final TtsService _tts;
  late final BeepEngine _beep;
  late final AmbienceEngine _ambience;
  late final UserProfileService _userProfile;
  late final CareerProgressService _careerProgress;
  late final Future<List<AmbiencePack>> _ambiencePacksFuture;

  /// Niveau max persisté. Null tant que pas chargé → on cache l'icône
  /// surprise par défaut (état pessimiste, évite un flash de l'icône).
  int? _maxLevel;

  /// Garde-fou pour éviter de pousser deux fois la SessionScreen surprise
  /// (entre le tap et l'arrivée du resumed sur la même action).
  bool _surpriseInFlight = false;

  @override
  void initState() {
    super.initState();
    _tts = TtsService(locale: LocaleService.instance.current);
    _beep = BeepEngine();
    _ambience = AmbienceEngine();
    _userProfile = UserProfileService();
    _careerProgress = CareerProgressService();
    _tts.attachProfile(_userProfile);
    LocaleService.instance.addListener(_handleLocaleChanged);
    // Chargement asynchrone du profil — pas besoin d'await ici, le service
    // expose un `notifyListeners` et la résolution `{name}` se contente du
    // fallback tant que le load n'est pas terminé.
    _userProfile.load();
    unawaited(_refreshMaxLevel());
    _ambiencePacksFuture = AmbiencePackLoader().load();
    // Catalogue des fonds média poussé dans le singleton dédié. Bundle
    // vide possible (= JSON sans entrées) → le widget retombe sur le
    // placeholder animé. Pas d'attente côté UI.
    BackgroundsLoader().load().then(BackgroundsService.instance.setBundle);
    WidgetsBinding.instance.addObserver(this);
    // Cold start : si l'app a été lancée par tap d'une notif surprise,
    // un flag d'intent a été posé dans main(). On le consume après la
    // première frame pour avoir un context utilisable.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _runFirstRunFlow();
      if (!mounted) return;
      _maybeLaunchSurprise();
    });
  }

  /// Adult gate (18+) puis onboarding 3 étapes. Bloque le reste du flow
  /// (notifs surprise comprises) tant que le consent n'est pas donné.
  Future<void> _runFirstRunFlow() async {
    if (!mounted) return;
    if (!AdultConsentService.instance.isAccepted) {
      final accepted = await AdultGateDialog.show(context);
      if (!mounted || !accepted) return;
    }
    if (!mounted) return;
    if (!OnboardingService.instance.hasBeenShown) {
      await OnboardingSheet.show(
        context,
        onTestVoice: () {
          if (!mounted) return;
          _openSoundDemo();
        },
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocaleService.instance.removeListener(_handleLocaleChanged);
    _tts.dispose();
    _beep.dispose();
    _ambience.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    unawaited(_tts.setLocale(LocaleService.instance.current));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Warm tap : l'utilisatrice a tapé une notif et l'app revient au
      // foreground. Le callback top-level a déjà posé le flag d'intent.
      _maybeLaunchSurprise();
      // Le niveau peut avoir bougé pendant que l'app était en background
      // (ex. session terminée par un share intent ou autre flow).
      unawaited(_refreshMaxLevel());
    }
  }

  Future<void> _refreshMaxLevel() async {
    final lvl = await _careerProgress.getMaxLevel();
    if (!mounted) return;
    if (_maxLevel != lvl) setState(() => _maxLevel = lvl);
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    showAboutDialog(
      context: context,
      applicationIcon: Image.asset(
        'assets/icon/app_icon.png',
        height: 48,
        width: 48,
        filterQuality: FilterQuality.medium,
      ),
      applicationName: info.appName,
      applicationVersion: 'v${info.version} (build ${info.buildNumber})',
      applicationLegalese: t.profileAboutOffline,
    );
  }

  Future<void> _maybeLaunchSurprise() async {
    if (!mounted || _surpriseInFlight) return;
    final fired = await SurpriseAlertService.instance.consumeNextIntent();
    if (!fired || !mounted) return;
    // Si une autre route est déjà au-dessus (l'utilisatrice est en
    // session ou sur l'écran carrière), on ne push pas. L'intent a été
    // consommé pour ne pas re-déclencher au prochain resumed.
    if (Navigator.of(context).canPop()) return;
    // Consomme la fenêtre entière : annule toutes les autres alarms
    // programmées au niveau natif. Sinon une autre notif pourrait tomber
    // pendant que l'utilisatrice est en pleine session (l'app est
    // foreground, donc l'observer `resumed` n'est pas re-déclenché et ne
    // les annule pas par la voie habituelle).
    await SurpriseAlertService.instance.consumeWindow();
    if (!mounted) return;
    _surpriseInFlight = true;
    try {
      await SurpriseRouter.launchSession(
        context: context,
        tts: _tts,
        beep: _beep,
        ambience: _ambience,
      );
    } finally {
      if (mounted) _surpriseInFlight = false;
    }
  }

  void _openSurpriseSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SurpriseSettingsScreen(),
      ),
    );
  }

  Future<void> _openSoundDemo() async {
    final ambiencePacks = await _ambiencePacksFuture;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoundDemoScreen(
          beep: _beep,
          tts: _tts,
          ambience: _ambience,
          ambiencePacks: ambiencePacks,
          userProfile: _userProfile,
        ),
      ),
    );
  }

  void _openScenario() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          tts: _tts,
          beep: _beep,
          ambience: _ambience,
        ),
      ),
    );
  }

  void _openCareer() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CareerScreen(
              tts: _tts,
              beep: _beep,
              ambience: _ambience,
              userProfile: _userProfile,
            ),
          ),
        )
        .then((_) => _refreshMaxLevel());
  }

  void _openCustom() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomModeScreen(
          tts: _tts,
          beep: _beep,
          ambience: _ambience,
          userProfile: _userProfile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: InkWell(
            onTap: _showAbout,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                'assets/icon/app_icon.png',
                height: 32,
                width: 32,
                filterQuality: FilterQuality.medium,
                semanticLabel: t.modeSelectionAppBarTitle,
              ),
            ),
          ),
        ),
        actions: [
          if (PlatformCapabilities.supportsSurpriseNotifications &&
              (_maxLevel ?? 1) >= _surpriseUnlockLevel)
            IconButton(
              tooltip: t.modeSelectionSurpriseTooltip,
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: _openSurpriseSettings,
            ),
          IconButton(
            tooltip: t.modeSelectionProfileTooltip,
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfileScreen(
                  userProfile: _userProfile,
                  tts: _tts,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: t.modeSelectionSoundsTooltip,
            icon: const Icon(Icons.graphic_eq),
            onPressed: _openSoundDemo,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.modeSelectionHeaderTitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.modeSelectionHeaderSubtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _ModeCard(
                  title: t.modeSelectionCareerTitle,
                  subtitle: t.modeSelectionCareerSubtitle,
                  icon: Icons.military_tech_outlined,
                  onTap: _openCareer,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ModeCard(
                  title: t.modeSelectionScenarioTitle,
                  subtitle: t.modeSelectionScenarioSubtitle,
                  icon: Icons.menu_book_outlined,
                  onTap: _openScenario,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ModeCard(
                  title: t.modeSelectionCustomTitle,
                  subtitle: t.modeSelectionCustomSubtitle,
                  icon: Icons.tune,
                  onTap: _openCustom,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppTheme.accent, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textMuted,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
