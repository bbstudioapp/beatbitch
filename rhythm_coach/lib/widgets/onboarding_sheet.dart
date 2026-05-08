import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';

/// Sheet d'onboarding 3 étapes affichée à la première ouverture (après
/// l'adult gate). Étapes : pose latérale du téléphone, volume haut,
/// proposition d'aller tester sa voix dans `SoundDemoScreen`.
///
/// La sheet est marquée comme vue dès qu'on la ferme (skip ou complétion)
/// via `OnboardingService.markShown` — peu importe le chemin de sortie.
class OnboardingSheet extends StatefulWidget {
  /// Callback déclenché quand l'utilisatrice tape « Tester ma voix » à la
  /// dernière étape. Le caller pousse l'écran SONS et ferme la sheet.
  final VoidCallback onTestVoice;

  const OnboardingSheet({
    super.key,
    required this.onTestVoice,
  });

  /// Présente la sheet (modale, pas dismissible par swipe pour éviter de
  /// la rater par accident). Marque l'onboarding comme vu en sortie.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onTestVoice,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => OnboardingSheet(onTestVoice: onTestVoice),
    );
    await OnboardingService.instance.markShown();
  }

  @override
  State<OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends State<OnboardingSheet> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pages = <_OnboardingPage>[
      _OnboardingPage(
        icon: Icons.stay_current_landscape,
        title: t.onboardingStep1Title,
        body: t.onboardingStep1Body,
      ),
      _OnboardingPage(
        icon: Icons.volume_up_outlined,
        title: t.onboardingStep2Title,
        body: t.onboardingStep2Body,
      ),
      _OnboardingPage(
        icon: Icons.record_voice_over_outlined,
        title: t.onboardingStep3Title,
        body: t.onboardingStep3Body,
      ),
    ];
    final isLast = _step == pages.length - 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(pages.length, (i) {
                    final active = i == _step;
                    return Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: active ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? AppTheme.accent
                            : AppTheme.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    t.onboardingSkip,
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _OnboardingPageView(page: pages[_step]),
            const SizedBox(height: 24),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: BorderSide(
                          color: AppTheme.textMuted.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(t.onboardingPrevious),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      if (isLast) {
                        Navigator.of(context).pop();
                        widget.onTestVoice();
                      } else {
                        setState(() => _step++);
                      }
                    },
                    child: Text(
                      isLast ? t.onboardingTestVoice : t.onboardingNext,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  const _OnboardingPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(page.icon, color: AppTheme.accent, size: 32),
        ),
        const SizedBox(height: 16),
        Text(
          page.title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          page.body,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
