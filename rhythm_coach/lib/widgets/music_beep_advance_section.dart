import 'package:flutter/material.dart';

import '../career/services/debug_settings_service.dart';
import '../controllers/session_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class MusicBeepAdvanceSection extends StatefulWidget {
  const MusicBeepAdvanceSection({super.key});

  @override
  State<MusicBeepAdvanceSection> createState() =>
      _MusicBeepAdvanceSectionState();
}

class _MusicBeepAdvanceSectionState extends State<MusicBeepAdvanceSection> {
  final DebugSettingsService _settings = DebugSettingsService();
  int _ms = DebugSettingsService.defaultMusicBeepAdvanceMs;

  @override
  void initState() {
    super.initState();
    _settings.getMusicBeepAdvanceMs().then((value) {
      if (!mounted) return;
      setState(
          () => _ms = value.clamp(0, SessionController.musicBeepAdvanceMaxMs));
    });
  }

  Future<void> _set(int ms) async {
    final clamped = ms.clamp(0, SessionController.musicBeepAdvanceMaxMs);
    setState(() => _ms = clamped);
    await _settings.setMusicBeepAdvanceMs(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    const step = SessionController.musicBeepAdvanceStepMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.profileMusicBeepAdvanceTitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: t.sessionDebugMusicBeepAdvanceDecrease,
              icon: const Icon(Icons.remove),
              onPressed: () => _set(_ms - step),
            ),
            Text('$_ms ms', key: const Key('profileMusicBeepAdvanceValue')),
            IconButton(
              tooltip: t.sessionDebugMusicBeepAdvanceIncrease,
              icon: const Icon(Icons.add),
              onPressed: () => _set(_ms + step),
            ),
          ],
        ),
        Text(
          t.profileMusicBeepAdvanceSubtitle,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}
