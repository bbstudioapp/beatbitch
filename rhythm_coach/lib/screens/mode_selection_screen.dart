import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../career/screens/career_screen.dart';
import '../models/ambience_pack.dart';
import '../services/ambience_engine.dart';
import '../services/ambience_pack_loader.dart';
import '../services/backgrounds_loader.dart';
import '../services/backgrounds_service.dart';
import '../services/beep_engine.dart';
import '../services/locale_service.dart';
import '../services/surprise_alert_service.dart';
import '../services/surprise_router.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
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
  late final TtsService _tts;
  late final BeepEngine _beep;
  late final AmbienceEngine _ambience;
  late final UserProfileService _userProfile;
  late final Future<List<AmbiencePack>> _ambiencePacksFuture;

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
    _tts.attachProfile(_userProfile);
    // Chargement asynchrone du profil — pas besoin d'await ici, le service
    // expose un `notifyListeners` et la résolution `{name}` se contente du
    // fallback tant que le load n'est pas terminé.
    _userProfile.load();
    _ambiencePacksFuture = AmbiencePackLoader().load();
    // Catalogue des fonds média poussé dans le singleton dédié. Bundle
    // vide possible (= JSON sans entrées) → le widget retombe sur le
    // placeholder animé. Pas d'attente côté UI.
    BackgroundsLoader()
        .load()
        .then((b) => BackgroundsService.instance.setBundle(b));
    WidgetsBinding.instance.addObserver(this);
    // Cold start : si l'app a été lancée par tap d'une notif surprise,
    // un flag d'intent a été posé dans main(). On le consume après la
    // première frame pour avoir un context utilisable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLaunchSurprise();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tts.dispose();
    _beep.dispose();
    _ambience.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Warm tap : l'utilisatrice a tapé une notif et l'app revient au
      // foreground. Le callback top-level a déjà posé le flag d'intent.
      _maybeLaunchSurprise();
    }
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CareerScreen(
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
        title: Text(t.modeSelectionAppBarTitle),
        actions: [
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
                builder: (_) => const ProfileScreen(),
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
                  title: t.modeSelectionScenarioTitle,
                  subtitle: t.modeSelectionScenarioSubtitle,
                  icon: Icons.menu_book_outlined,
                  onTap: _openScenario,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ModeCard(
                  title: t.modeSelectionCareerTitle,
                  subtitle: t.modeSelectionCareerSubtitle,
                  icon: Icons.military_tech_outlined,
                  onTap: _openCareer,
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
