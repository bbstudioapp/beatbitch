import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_localizations.dart';
import '../services/surprise_alert_service.dart';
import '../services/surprise_router.dart';
import '../theme/app_theme.dart';

/// Écran « Rappel surprise » : toggle on/off, sliders fenêtre / nombre /
/// durée, affichage de l'état armé. Au save, appelle `arm()` ; au toggle
/// off, appelle `disarm()`.
class SurpriseSettingsScreen extends StatefulWidget {
  const SurpriseSettingsScreen({super.key});

  @override
  State<SurpriseSettingsScreen> createState() => _SurpriseSettingsScreenState();
}

class _SurpriseSettingsScreenState extends State<SurpriseSettingsScreen> {
  final SurpriseAlertService _service = SurpriseAlertService.instance;

  bool _loaded = false;
  bool _enabled = false;
  int _windowMinutes = 60;
  int _alertCount = 3;
  int _durationMin = 60;
  int _durationMax = 240;
  SurpriseScheduleSnapshot? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled = await _service.isEnabled();
    final windowSeconds = await _service.getWindowSeconds();
    final alertCount = await _service.getAlertCount();
    final range = await _service.getDurationRangeSeconds();
    final state = await _service.currentState();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _windowMinutes = (windowSeconds / 60).round().clamp(15, 240);
      _alertCount = alertCount;
      _durationMin = range.min;
      _durationMax = range.max;
      _state = state;
      _loaded = true;
    });
  }

  Future<void> _onEnabledToggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    if (value) {
      await _persistSettings();
      final result = await _service.arm(
        bodyVariants: SurpriseRouter.resolveBodyVariants(t),
      );
      if (!mounted) return;
      switch (result) {
        case SurpriseArmResult.ok:
          break;
        case SurpriseArmResult.notificationPermissionDenied:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.surpriseSettingsPermissionMissing)),
          );
          await _service.disarm();
          if (mounted) setState(() => _busy = false);
          await _refreshState(setEnabled: false);
          return;
        case SurpriseArmResult.exactAlarmDenied:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.surpriseSettingsExactAlarmMissing)),
          );
          await _service.disarm();
          if (mounted) setState(() => _busy = false);
          await _refreshState(setEnabled: false);
          return;
      }
    } else {
      await _service.disarm();
    }
    if (mounted) setState(() => _busy = false);
    await _refreshState(setEnabled: value);
  }

  Future<void> _persistSettings() async {
    await _service.setWindowSeconds(_windowMinutes * 60);
    await _service.setAlertCount(_alertCount);
    await _service.setDurationRangeSeconds(_durationMin, _durationMax);
  }

  Future<void> _refreshState({bool? setEnabled}) async {
    final state = await _service.currentState();
    final enabled = setEnabled ?? await _service.isEnabled();
    if (!mounted) return;
    setState(() {
      _state = state;
      _enabled = enabled;
    });
  }

  /// Si l'utilisatrice modifie un slider alors que la fenêtre est armée,
  /// on doit re-arm pour que les nouveaux réglages prennent effet sur la
  /// prochaine fenêtre. On ne re-déclenche **pas** automatiquement : le
  /// toggle est désactivé pendant qu'une fenêtre est active. C'est plus
  /// prévisible.
  bool get _slidersDisabled => _busy || _state != null;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.surpriseSettingsAppBarTitle)),
      body: _loaded
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.surpriseSettingsHeaderSubtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildEnableSwitch(t),
                  const SizedBox(height: 8),
                  _buildStatusCard(t),
                  const SizedBox(height: 24),
                  _buildWindowSlider(t),
                  const SizedBox(height: 16),
                  _buildAlertCountSlider(t),
                  const SizedBox(height: 16),
                  _buildDurationRangeSlider(t),
                  const SizedBox(height: 24),
                  _buildBatteryHint(t),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildEnableSwitch(AppLocalizations t) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: SwitchListTile(
        value: _enabled,
        onChanged: _busy ? null : _onEnabledToggle,
        title: Text(
          t.surpriseSettingsEnableLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(t.surpriseSettingsEnableSubtitle),
      ),
    );
  }

  Widget _buildStatusCard(AppLocalizations t) {
    final state = _state;
    final text = state == null
        ? t.surpriseSettingsInactiveStatus
        : '${t.surpriseSettingsActiveStatus(_formatTime(state.windowEnd))} · '
            '${t.surpriseSettingsActiveAlertsLeft(state.pendingAlertCount)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          color: state == null ? AppTheme.textMuted : AppTheme.accent,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildWindowSlider(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t.surpriseSettingsWindowLabel,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(t.surpriseSettingsWindowValue(_windowMinutes),
                style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
        Slider(
          value: _windowMinutes.toDouble(),
          min: 15,
          max: 240,
          divisions: (240 - 15) ~/ 15,
          label: t.surpriseSettingsWindowValue(_windowMinutes),
          onChanged: _slidersDisabled
              ? null
              : (v) => setState(() => _windowMinutes = v.round()),
        ),
      ],
    );
  }

  Widget _buildAlertCountSlider(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t.surpriseSettingsAlertCountLabel,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(t.surpriseSettingsAlertCountValue(_alertCount),
                style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
        Slider(
          value: _alertCount.toDouble(),
          min: SurpriseAlertService.alertCountMin.toDouble(),
          max: SurpriseAlertService.alertCountMax.toDouble(),
          divisions: SurpriseAlertService.alertCountMax -
              SurpriseAlertService.alertCountMin,
          label: '$_alertCount',
          onChanged: _slidersDisabled
              ? null
              : (v) => setState(() => _alertCount = v.round()),
        ),
      ],
    );
  }

  Widget _buildDurationRangeSlider(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t.surpriseSettingsDurationLabel,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              t.surpriseSettingsDurationValue(_durationMin, _durationMax),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
        RangeSlider(
          values: RangeValues(
            _durationMin.toDouble(),
            _durationMax.toDouble(),
          ),
          min: SurpriseAlertService.durationSecondsMin.toDouble(),
          max: SurpriseAlertService.durationSecondsMax.toDouble(),
          divisions: (SurpriseAlertService.durationSecondsMax -
                  SurpriseAlertService.durationSecondsMin) ~/
              10,
          labels: RangeLabels('${_durationMin}s', '${_durationMax}s'),
          onChanged: _slidersDisabled
              ? null
              : (r) => setState(() {
                    _durationMin = r.start.round();
                    _durationMax = r.end.round();
                    if (_durationMax < _durationMin + 10) {
                      _durationMax = _durationMin + 10;
                    }
                  }),
        ),
      ],
    );
  }

  Widget _buildBatteryHint(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.battery_alert_outlined,
                  size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                t.surpriseSettingsBatteryHintTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.surpriseSettingsBatteryHintBody,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(t.surpriseSettingsOpenBatterySettings),
              onPressed: () => openAppSettings(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
