import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/enum_labels.dart';
import '../../l10n/format_helpers.dart';
import '../../main.dart' show coachService;
import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../theme/app_theme.dart';
import '../models/custom_session_config.dart';
import 'custom_coach_picker_screen.dart';

/// Résultat retourné par l'éditeur : la config (potentiellement modifiée) +
/// `launch` true si l'utilisateur a tapé « Enregistrer et lancer ».
class CustomEditorResult {
  final CustomSessionConfig config;
  final bool launch;
  const CustomEditorResult({required this.config, required this.launch});
}

/// Écran d'édition d'une [CustomSessionConfig] (nouvelle ou existante).
class CustomConfigEditorScreen extends StatefulWidget {
  final CustomSessionConfig initial;
  final bool isNew;

  const CustomConfigEditorScreen({
    super.key,
    required this.initial,
    required this.isNew,
  });

  @override
  State<CustomConfigEditorScreen> createState() =>
      _CustomConfigEditorScreenState();
}

class _CustomConfigEditorScreenState extends State<CustomConfigEditorScreen> {
  late final TextEditingController _nameCtrl;
  late int _durationSeconds;
  late bool _nonStop;
  late int _cycleDurationSeconds;
  late bool _progressiveDifficulty;
  late String? _coachId;
  late Map<SessionMode, ModeDose> _doses;
  late CustomDifficulty _difficulty;
  late int _maxDepthIndex;
  late RangeValues _bpmRange;
  late RangeValues _holdRange;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _nameCtrl = TextEditingController(text: c.name);
    _durationSeconds = c.durationSeconds ?? 12 * 60;
    _nonStop = c.nonStop;
    _cycleDurationSeconds = c.cycleDurationSeconds;
    _progressiveDifficulty = c.progressiveDifficulty;
    _coachId = c.coachId;
    _doses = {
      for (final m in SessionMode.values) m: c.doses[m] ?? ModeDose.normal
    };
    _difficulty = c.difficulty;
    _maxDepthIndex = c.maxDepthIndex;
    _bpmRange = RangeValues(c.bpmMin.toDouble(), c.bpmMax.toDouble());
    _holdRange = RangeValues(
      c.holdDurationMin.toDouble(),
      c.holdDurationMax.toDouble(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _activeMouthModeCount => CustomSessionConfig.mouthModes
      .where((m) => _doses[m] != ModeDose.none)
      .length;

  bool _isLastActiveMouthMode(SessionMode m) =>
      CustomSessionConfig.mouthModes.contains(m) &&
      _doses[m] != ModeDose.none &&
      _activeMouthModeCount <= 1;

  void _setDose(SessionMode m, ModeDose dose) {
    if (dose == ModeDose.none && _isLastActiveMouthMode(m)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).customDangerNoMouthMode)),
        );
      return;
    }
    setState(() => _doses[m] = dose);
  }

  CustomSessionConfig _build() {
    return widget.initial.copyWith(
      name: _nameCtrl.text.trim(),
      durationSeconds: _nonStop ? null : _durationSeconds,
      nonStop: _nonStop,
      cycleDurationSeconds: _cycleDurationSeconds,
      progressiveDifficulty: _progressiveDifficulty,
      coachId: _coachId,
      clearCoachId: _coachId == null,
      doses: Map.of(_doses),
      difficulty: _difficulty,
      maxDepthIndex: _maxDepthIndex,
      bpmMin: _bpmRange.start.round(),
      bpmMax: _bpmRange.end.round(),
      holdDurationMin: _holdRange.start.round(),
      holdDurationMax: _holdRange.end.round(),
    );
  }

  Future<void> _finish({required bool launch}) async {
    // Garde-fou : au moins un mode bouche actif.
    if (_activeMouthModeCount == 0) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).customDangerNoMouthMode)),
        );
      return;
    }
    Navigator.of(context)
        .pop(CustomEditorResult(config: _build(), launch: launch));
  }

  Future<void> _pickCoach() async {
    final picked = await CustomCoachPickerScreen.pick(
      context,
      service: coachService,
      selectedCoachId: _coachId,
    );
    if (picked == null || !mounted) return;
    setState(() => _coachId = picked.coachId);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String coachLabel = t.customCoachDefaultVoice;
    if (_coachId != null) {
      for (final c in coachService.coaches) {
        if (c.id == _coachId) {
          coachLabel = c.name;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.isNew ? t.customEditorTitleNew : t.customEditorTitleEdit),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // ─── Nom ─────────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.customFieldNameLabel,
              hintText: t.customFieldNameHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // ─── Coach ───────────────────────────────────────────────────
          _SectionLabel(t.customSectionCoach),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            tileColor: AppTheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(Icons.school_outlined, color: AppTheme.accent),
            ),
            title: Text(coachLabel,
                style: const TextStyle(color: AppTheme.textPrimary)),
            trailing: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ),
            onTap: _pickCoach,
          ),
          const SizedBox(height: 24),

          // ─── Durée / non-stop ────────────────────────────────────────
          _SectionLabel(t.customSectionDuration),
          const SizedBox(height: 8),
          if (!_nonStop) ...[
            _MinutesSlider(
              valueSeconds: _durationSeconds,
              minSeconds: CustomSessionConfig.minDurationSeconds,
              maxSeconds: CustomSessionConfig.maxDurationSeconds,
              onChanged: (v) => setState(() => _durationSeconds = v),
            ),
            const SizedBox(height: 8),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.customNonStopToggle,
                style:
                    const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
            subtitle: Text(t.customNonStopDescription,
                style:
                    const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            value: _nonStop,
            onChanged: (v) => setState(() => _nonStop = v),
          ),
          if (_nonStop) ...[
            _LabeledValue(
              label: t.customCycleDurationLabel,
              value: t.customDurationMinutes(_cycleDurationSeconds ~/ 60),
            ),
            _MinutesSlider(
              valueSeconds: _cycleDurationSeconds,
              minSeconds: CustomSessionConfig.minCycleDurationSeconds,
              maxSeconds: CustomSessionConfig.maxCycleDurationSeconds,
              onChanged: (v) => setState(() => _cycleDurationSeconds = v),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.customProgressiveDifficultyToggle,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textPrimary)),
              subtitle: Text(t.customProgressiveDifficultyDescription,
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              value: _progressiveDifficulty,
              onChanged: (v) => setState(() => _progressiveDifficulty = v),
            ),
          ],
          const SizedBox(height: 24),

          // ─── Difficulté globale ──────────────────────────────────────
          _SectionLabel(t.customSectionDifficulty),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final d in CustomDifficulty.values)
                ChoiceChip(
                  label: Text(d.localizedLabel(context)),
                  selected: _difficulty == d,
                  onSelected: (_) => setState(() => _difficulty = d),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // ─── Profondeur max + bornes BPM/hold ────────────────────────
          _SectionLabel(t.customSectionAdvanced),
          const SizedBox(height: 8),
          _LabeledValue(
            label: t.customMaxDepthLabel,
            value: Position.values[_maxDepthIndex].localizedLabel(context),
          ),
          Slider(
            value: _maxDepthIndex.toDouble(),
            min: 0,
            max: 4,
            divisions: 4,
            label: Position.values[_maxDepthIndex].localizedLabel(context),
            onChanged: (v) => setState(() => _maxDepthIndex = v.round()),
          ),
          const SizedBox(height: 12),
          _LabeledValue(
            label: t.customBpmRangeLabel,
            value: t.customBpmRangeValue(
              _bpmRange.start.round(),
              _bpmRange.end.round(),
            ),
          ),
          RangeSlider(
            values: _bpmRange,
            min: CustomSessionConfig.minBpmLimit.toDouble(),
            max: CustomSessionConfig.maxBpmLimit.toDouble(),
            divisions: CustomSessionConfig.maxBpmLimit -
                CustomSessionConfig.minBpmLimit,
            labels: RangeLabels(
              '${_bpmRange.start.round()}',
              '${_bpmRange.end.round()}',
            ),
            onChanged: (v) => setState(() => _bpmRange = v),
          ),
          Text(t.customBpmRangeHint,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          _LabeledValue(
            label: t.customHoldDurationRangeLabel,
            value: t.customHoldDurationRangeValue(
              _holdRange.start.round(),
              _holdRange.end.round(),
            ),
          ),
          RangeSlider(
            values: _holdRange,
            min: CustomSessionConfig.minHoldDurationLimit.toDouble(),
            max: CustomSessionConfig.maxHoldDurationLimit.toDouble(),
            divisions: CustomSessionConfig.maxHoldDurationLimit -
                CustomSessionConfig.minHoldDurationLimit,
            labels: RangeLabels(
              '${_holdRange.start.round()}',
              '${_holdRange.end.round()}',
            ),
            onChanged: (v) => setState(() => _holdRange = v),
          ),
          Text(t.customHoldDurationRangeHint,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 24),

          // ─── Dosage des modes ────────────────────────────────────────
          _SectionLabel(t.customSectionDoses),
          const SizedBox(height: 4),
          Text(t.customDosesHint,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          for (final m in CustomSessionConfig.dosableModes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      m.shortLabel(context),
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textPrimary),
                    ),
                  ),
                  DropdownButton<ModeDose>(
                    value: _doses[m],
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final d in ModeDose.values)
                        DropdownMenuItem(
                          value: d,
                          child: Text(d.localizedLabel(context)),
                        ),
                    ],
                    onChanged: (d) {
                      if (d != null) _setDose(m, d);
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),

          // ─── Actions ─────────────────────────────────────────────────
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => _finish(launch: true),
            child: Text(
              t.customSaveAndLaunch,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _finish(launch: false),
            child: Text(t.customSaveOnly),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppTheme.accent,
      ),
    );
  }
}

class _LabeledValue extends StatelessWidget {
  final String label;
  final String value;
  const _LabeledValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
      ],
    );
  }
}

class _MinutesSlider extends StatelessWidget {
  final int valueSeconds;
  final int minSeconds;
  final int maxSeconds;
  final ValueChanged<int> onChanged;

  const _MinutesSlider({
    required this.valueSeconds,
    required this.minSeconds,
    required this.maxSeconds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final minM = (minSeconds / 60).round();
    final maxM = (maxSeconds / 60).round();
    final curM = (valueSeconds / 60).round().clamp(minM, maxM);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatDurationCompact(context, curM * 60),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.accent,
          ),
        ),
        Slider(
          value: curM.toDouble(),
          min: minM.toDouble(),
          max: maxM.toDouble(),
          divisions: maxM - minM,
          label: t.customDurationMinutes(curM),
          onChanged: (v) => onChanged(v.round() * 60),
        ),
      ],
    );
  }
}
