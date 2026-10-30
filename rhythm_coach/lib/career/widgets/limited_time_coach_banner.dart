import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

class LimitedTimeCoachBanner extends StatelessWidget {
  final String coachName;
  final DateTime until;
  final VoidCallback onTry;

  const LimitedTimeCoachBanner({
    super.key,
    required this.coachName,
    required this.until,
    required this.onTry,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.dark_mode_outlined,
              color: AppTheme.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.coachLimitedTimeBanner(coachName, until),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onTry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(t.coachLimitedTimeBannerAction,
                style: const TextStyle(fontSize: 11, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}
