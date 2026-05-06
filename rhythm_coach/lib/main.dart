import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'career/services/coach_loader.dart';
import 'career/services/coach_service.dart';
import 'career/services/milestone_service.dart';
import 'l10n/app_localizations.dart';
import 'screens/mode_selection_screen.dart';
import 'services/coach_phrases_loader.dart';
import 'services/locale_service.dart';
import 'theme/app_theme.dart';

/// Singleton CoachService partagé entre les écrans Carrière. Instancié à
/// l'init pour que `MaterialApp` puisse écouter ses changements (badge
/// "Hors palier" mis à jour quand un nouveau Principal est débloqué).
final CoachService coachService = CoachService();

/// Singleton MilestoneService : catalogue des milestones et set des
/// unlocks acquittés. Consommé par le générateur (gating) et le controller
/// (markCompleted en fin de session).
final MilestoneService milestoneService = MilestoneService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleService.instance.init();
  await CoachPhrasesService.instance.ensureLoaded();
  // Charge le catalogue puis greffe les packs de phrases par coach
  // (assets/career/coaches/<id>_<lang>.json). Tout asset manquant est
  // toléré : le coach reste utilisable, ses phrases retomberont sur la
  // PhraseBank globale via Coach.toPhraseBank.
  await coachService.load();
  final coachesWithPhrases = await CoachLoader().load();
  coachService.attachPhrases(coachesWithPhrases);
  await milestoneService.ensureLoaded();
  // Rebrancher les services dépendants de la locale quand celle-ci change
  // à chaud (sélecteur dans SoundDemoScreen). MaterialApp rebuild son UI
  // via AnimatedBuilder ; ce listener s'occupe du contenu éditorial caché
  // dans les singletons (phrases coach, overrides milestone, packs coach).
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
  runApp(const RhythmCoachApp());
}

class RhythmCoachApp extends StatelessWidget {
  const RhythmCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocaleService.instance,
      builder: (context, _) {
        return MaterialApp(
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
