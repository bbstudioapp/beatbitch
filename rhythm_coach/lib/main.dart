import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'career/services/coach_loader.dart';
import 'career/services/coach_service.dart';
import 'career/services/milestone_service.dart';
import 'l10n/app_localizations.dart';
import 'screens/mode_selection_screen.dart';
import 'services/adult_consent_service.dart';
import 'services/coach_phrases_loader.dart';
import 'services/locale_service.dart';
import 'services/onboarding_service.dart';
import 'services/platform_capabilities.dart';
import 'services/profile_reconciliation.dart';
import 'services/surprise_alert_service.dart';
import 'services/surprise_lifecycle_observer.dart';
import 'services/surprise_notifications_bootstrap.dart';
import 'theme/app_theme.dart';

final CoachService coachService = CoachService();

final MilestoneService milestoneService = MilestoneService();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleService.instance.init();
  await ProfileReconciliation.runIfNeeded();
  await AdultConsentService.instance.init();
  await OnboardingService.instance.init();
  await CoachPhrasesService.instance.ensureLoaded();
  await coachService.load();
  final coachesWithPhrases = await CoachLoader().load();
  coachService.attachPhrases(coachesWithPhrases);
  await milestoneService.ensureLoaded();
  LocaleService.instance.addListener(() {
    unawaited(() async {
      await CoachPhrasesService.instance.ensureLoaded();
      final coachesWithPhrases = await CoachLoader().load();
      coachService.attachPhrases(coachesWithPhrases);
      await milestoneService.reloadLocaleOverrides();
    }());
  });
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  if (PlatformCapabilities.locksPortrait(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    shortestSide: view.physicalSize.shortestSide / view.devicePixelRatio,
  )) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  if (PlatformCapabilities.supportsSurpriseNotifications) {
    // Titre de secours des notifs programmées avant un changement de locale.
    await SurpriseNotificationsBootstrap.init(
      localizedTitle: "C'est l'heure",
      onTap: surpriseNotificationTapHandler,
    );
    final coldStartPayload =
        await SurpriseNotificationsBootstrap.consumeColdStartPayload();
    if (coldStartPayload != null) {
      await SurpriseAlertService.markIntentPending(coldStartPayload);
    }
    await SurpriseAlertService.instance.init();
  }

  runApp(const RhythmCoachApp());
  if (PlatformCapabilities.supportsSurpriseNotifications) {
    WidgetsBinding.instance.addObserver(SurpriseLifecycleObserver());
  }
}

class RhythmCoachApp extends StatelessWidget {
  const RhythmCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocaleService.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(),
          locale: LocaleService.instance.current,
          supportedLocales: kSupportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ModeSelectionScreen(),
        );
      },
    );
  }
}
