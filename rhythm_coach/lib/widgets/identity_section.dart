import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/coach_phrases_loader.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';

/// Section "Identité" : prénom utilisatrice + listes de surnoms
/// (défauts toggleables + surnoms custom). Branchée directement sur
/// `UserProfileService` (ChangeNotifier) — rebuild auto à chaque mise à
/// jour. Optionnellement, le bouton « Tester » lit
/// `CoachPhrasesService.instance.current.testIdentityPhrase` via le TTS
/// fourni si présent.
class IdentitySection extends StatefulWidget {
  final UserProfileService userProfile;

  /// Si fourni, un bouton « Tester » fait parler la phrase d'identité de
  /// la coach par-dessus le TTS courant. Sans TTS, le bouton est masqué.
  final TtsService? tts;

  const IdentitySection({
    super.key,
    required this.userProfile,
    this.tts,
  });

  @override
  State<IdentitySection> createState() => _IdentitySectionState();
}

class _IdentitySectionState extends State<IdentitySection> {
  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _newNicknameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.userProfile.addListener(_onProfileChanged);
    _prenomController.text = widget.userProfile.prenom ?? '';
  }

  @override
  void dispose() {
    widget.userProfile.removeListener(_onProfileChanged);
    _prenomController.dispose();
    _newNicknameController.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (!mounted) return;
    final prenom = widget.userProfile.prenom ?? '';
    if (_prenomController.text != prenom) {
      _prenomController.text = prenom;
    }
    setState(() {});
  }

  Future<void> _testIdentity() async {
    final tts = widget.tts;
    if (tts == null) return;
    await tts.stop();
    await tts.speak(CoachPhrasesService.instance.current.testIdentityPhrase);
  }

  Future<void> _addCustomNickname() async {
    final value = _newNicknameController.text.trim();
    if (value.isEmpty) return;
    await widget.userProfile.addCustomNickname(value);
    _newNicknameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final showTest = widget.tts != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.soundsIdentitySubtitle('name'),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _prenomController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: t.soundsFirstNameLabel,
              helperText: t.soundsFirstNameHelper,
            ),
            onSubmitted: (v) => widget.userProfile.setPrenom(v),
            onEditingComplete: () =>
                widget.userProfile.setPrenom(_prenomController.text),
          ),
          if (showTest) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testIdentity,
              icon: const Icon(Icons.volume_up_outlined),
              label: Text(t.soundsTestSubstitution),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: BorderSide(
                  color: AppTheme.accent.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            t.soundsDefaultNicknames,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          for (final n in widget.userProfile.defaultNicknames)
            _NicknameToggleTile(
              label: n,
              enabled: !widget.userProfile.disabledDefaults.contains(n),
              onChanged: (v) => widget.userProfile.setDefaultEnabled(n, v),
            ),
          const SizedBox(height: 12),
          Text(
            t.soundsCustomNicknames,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          if (widget.userProfile.customNicknames.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                t.soundsNoCustomNicknames,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          for (final n in widget.userProfile.customNicknames)
            _NicknameRemovableTile(
              label: n,
              onRemove: () => widget.userProfile.removeCustomNickname(n),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newNicknameController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: t.soundsAddNicknameLabel,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addCustomNickname(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: t.commonAdd,
                icon: const Icon(Icons.add_circle, color: AppTheme.accent),
                onPressed: _addCustomNickname,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NicknameToggleTile extends StatelessWidget {
  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _NicknameToggleTile({
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.check_box : Icons.check_box_outline_blank,
              color: enabled ? AppTheme.accent : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NicknameRemovableTile extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _NicknameRemovableTile({
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.label_important_outline,
              color: AppTheme.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).soundsRemoveNicknameTooltip,
            icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
