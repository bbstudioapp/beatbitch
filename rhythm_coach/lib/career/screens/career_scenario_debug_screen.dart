import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/enum_labels.dart';
import '../../main.dart' show milestoneService;
import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/humiliation_engine.dart';
import '../../services/stats_service.dart';
import '../../theme/app_theme.dart';
import '../models/career_level.dart';
import '../models/level_milestone.dart';
import '../models/phrase_bank.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';
import '../services/career_progress_service.dart';
import '../services/career_session_generator.dart';
import '../services/milestone_loader.dart';
import '../services/phrase_bank_loader.dart';
import '../services/specialization_service.dart';

/// Écran de debug pour visualiser une session générée par le mode carrière
/// sans la jouer. Permet de faire varier les paramètres d'entrée (niveau,
/// humil, obed, milestones, unlocks…) et d'inspecter la liste des steps,
/// le profil stamina projeté, et de simuler un branchement
/// Supplier ou un fail à un instant précis.
class CareerScenarioDebugScreen extends StatefulWidget {
  const CareerScenarioDebugScreen({super.key});

  @override
  State<CareerScenarioDebugScreen> createState() =>
      _CareerScenarioDebugScreenState();
}

class _CareerScenarioDebugScreenState
    extends State<CareerScenarioDebugScreen> {
  bool _ready = false;
  PhraseBank? _bank;
  List<LevelMilestone> _catalog = const [];
  SpecializationAllocation _spec = SpecializationAllocation.empty();

  // Inputs.
  int _level = 1;
  double _humil = 0;
  double _obed = 0;
  bool _includeHand = true;
  bool _quickie = false;
  bool _intense = false;
  int _durationOverride = 0; // 0 = auto
  String _milestoneChoice = _kAuto;
  String _finalMilestoneChoice = _kAuto;
  Set<UnlockKey> _unlocks = const {};
  bool _paramsExpanded = true;
  bool _showText = false;

  // Sortie.
  CareerGenerationResult? _result;
  LevelMilestone? _appliedMilestone;
  LevelMilestone? _appliedFinalMilestone;

  // Branche Supplier (régénération à partir d'un instant T).
  CareerGenerationResult? _forkResult;
  int? _forkStartTime;
  int? _forkLevel;
  LevelMilestone? _forkAppliedMilestone;
  LevelMilestone? _forkAppliedFinalMilestone;

  // Snapshot fail simulé (annotation).
  int? _failSimulatedAtStepTime;
  double? _failSimulatedNewHumil;
  double? _failSimulatedNewObed;
  int? _failSimulatedNextStepTime;

  static const String _kAuto = '__auto__';
  static const String _kNone = '__none__';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    await milestoneService.ensureLoaded();
    final bank = await PhraseBankLoader().load();
    final catalog = await MilestoneLoader().load();
    final stats = StatsService();
    final progress = CareerProgressService();
    final spec = await SpecializationService().load();
    final humil = await stats.getHumiliationLevel();
    final obed = await stats.getObedienceLevel();
    final maxLevel = await progress.getMaxLevel();
    final includeHand = await progress.getIncludeHand();
    if (!mounted) return;
    setState(() {
      _bank = bank;
      _catalog = catalog;
      _spec = spec;
      _humil = humil;
      _obed = obed;
      _level = maxLevel.clamp(1, 20);
      _includeHand = includeHand;
      _unlocks = milestoneService.acquiredUnlockKeys();
      _ready = true;
    });
    _regenerate();
  }

  void _regenerate() {
    final bank = _bank;
    if (bank == null) return;
    final milestone = _resolveMilestone(_milestoneChoice,
        placement: MilestonePlacement.body);
    final finalMilestone = _resolveMilestone(_finalMilestoneChoice,
        placement: MilestonePlacement.finalApotheose);
    final result = CareerSessionGenerator().generate(
      level: _level,
      bank: bank,
      includeHand: _includeHand,
      quickie: _quickie,
      intense: _intense,
      humiliationCareer: _humil,
      obedience: _obed,
      durationSeconds: _durationOverride > 0 ? _durationOverride : null,
      specialization: _spec,
      milestone: milestone,
      finalMilestone: finalMilestone,
      unlockedKeys: _unlocks,
      milestoneTextResolver: milestoneService.getStepText,
    );
    setState(() {
      _result = result;
      _appliedMilestone = milestone;
      _appliedFinalMilestone = finalMilestone;
      _forkResult = null;
      _forkStartTime = null;
      _forkLevel = null;
      _forkAppliedMilestone = null;
      _forkAppliedFinalMilestone = null;
      _failSimulatedAtStepTime = null;
    });
  }

  LevelMilestone? _resolveMilestone(
    String choice, {
    required MilestonePlacement placement,
  }) {
    if (choice == _kNone) return null;
    if (choice == _kAuto) {
      if (placement == MilestonePlacement.body) {
        return milestoneService.pendingFor(
          humiliationScore: _humil,
          obedience: _obed,
          allocation: _spec,
        );
      }
      return milestoneService.pendingFinalFor(
        humiliationScore: _humil,
        obedience: _obed,
        playerLevel: _level,
        allocation: _spec,
      );
    }
    return _catalog.firstWhere(
      (m) => m.id == choice,
      orElse: () => _catalog.first,
    );
  }

  void _simulateSupplier(int stepTime) {
    final bank = _bank;
    if (bank == null) return;
    final result = _result;
    if (result == null) return;
    const begDuration = 12;
    const levelJump = 2;
    final remaining = result.session.durationSeconds - stepTime;
    if (remaining < begDuration + 30) return;
    final newLevel = (_level + levelJump).clamp(1, 30);
    final genDuration = remaining - begDuration;
    // Mêmes règles qu'en prod : intense + level+2, mais on prend humil
    // persisté + obed live (qu'on simule = obed courant — pas de pénalité
    // de fail simulée ici).
    final milestone = milestoneService.pendingFor(
      humiliationScore: _humil,
      obedience: _obed,
      allocation: _spec,
    );
    final finalMilestone = milestoneService.pendingFinalFor(
      humiliationScore: _humil,
      obedience: _obed,
      allocation: _spec,
    );
    final fork = CareerSessionGenerator().generate(
      durationSeconds: genDuration,
      level: newLevel,
      bank: bank,
      includeHand: _includeHand,
      specialization: _spec,
      intense: true,
      humiliationCareer: _humil,
      obedience: _obed,
      milestone: milestone,
      finalMilestone: finalMilestone,
      unlockedKeys: _unlocks,
      milestoneTextResolver: milestoneService.getStepText,
    );
    setState(() {
      _forkResult = fork;
      _forkStartTime = stepTime;
      _forkLevel = newLevel;
      _forkAppliedMilestone = milestone;
      _forkAppliedFinalMilestone = finalMilestone;
      _failSimulatedAtStepTime = null;
    });
  }

  void _simulateFail(int stepTime) {
    final result = _result;
    if (result == null) return;
    final session = result.session;
    final inLastMinute = (session.durationSeconds - stepTime) <= 60;
    final humilDelta = inLastMinute ? -2.0 : -1.0;
    final obedDelta = inLastMinute ? -4.0 : -2.0;
    final newHumil = (_humil + humilDelta).clamp(0.0, 999.0);
    final newObed = (_obed + obedDelta).clamp(0.0, 999.0);
    int? nextStep;
    for (final s in session.steps) {
      if (s.time > stepTime && !s.isTextOnly) {
        nextStep = s.time;
        break;
      }
    }
    setState(() {
      _failSimulatedAtStepTime = stepTime;
      _failSimulatedNewHumil = newHumil;
      _failSimulatedNewObed = newObed;
      _failSimulatedNextStepTime = nextStep;
      _forkResult = null;
      _forkStartTime = null;
    });
  }

  void _clearFork() {
    setState(() {
      _forkResult = null;
      _forkStartTime = null;
      _forkLevel = null;
      _forkAppliedMilestone = null;
      _forkAppliedFinalMilestone = null;
    });
  }

  void _clearFailSnapshot() {
    setState(() {
      _failSimulatedAtStepTime = null;
      _failSimulatedNewHumil = null;
      _failSimulatedNewObed = null;
      _failSimulatedNextStepTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: Text(t.careerDebugTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t.careerDebugTitle),
        actions: [
          IconButton(
            tooltip: t.careerDebugRegenerate,
            onPressed: _regenerate,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildParamsCard(t),
          const SizedBox(height: 16),
          _buildScenarioHeader(t),
          const SizedBox(height: 8),
          ..._buildStepsList(t),
        ],
      ),
    );
  }

  // ---------------- Params card ----------------

  Widget _buildParamsCard(AppLocalizations t) {
    return Card(
      color: AppTheme.surface,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _paramsExpanded,
          onExpansionChanged: (v) => setState(() => _paramsExpanded = v),
          title: Text(
            t.careerDebugSectionParams,
            style: const TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _slider(
              label: '${t.careerDebugLevel} : $_level',
              value: _level.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              onChanged: (v) => setState(() => _level = v.round()),
            ),
            _slider(
              label:
                  '${t.careerDebugHumiliation} : ${_humil.toStringAsFixed(0)}',
              value: _humil,
              min: 0,
              max: 200,
              divisions: 200,
              onChanged: (v) => setState(() => _humil = v),
            ),
            _slider(
              label:
                  '${t.careerDebugObedience} : ${_obed.toStringAsFixed(0)}',
              value: _obed,
              min: 0,
              max: 200,
              divisions: 200,
              onChanged: (v) => setState(() => _obed = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.careerDebugIncludeHand,
                  style: const TextStyle(color: AppTheme.textPrimary)),
              value: _includeHand,
              onChanged: (v) => setState(() => _includeHand = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.careerDebugQuickie,
                  style: const TextStyle(color: AppTheme.textPrimary)),
              value: _quickie,
              onChanged: (v) => setState(() => _quickie = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.careerDebugIntense,
                  style: const TextStyle(color: AppTheme.textPrimary)),
              value: _intense,
              onChanged: (v) => setState(() => _intense = v),
            ),
            _slider(
              label: _durationOverride <= 0
                  ? '${t.careerDebugDurationOverride} : ${t.careerDebugAuto}'
                  : '${t.careerDebugDurationOverride} : ${_formatTime(_durationOverride)}',
              value: _durationOverride.toDouble(),
              min: 0,
              max: 2700,
              divisions: 90,
              onChanged: (v) {
                setState(() => _durationOverride = v.round());
              },
            ),
            const SizedBox(height: 8),
            _milestonePicker(
              t: t,
              label: t.careerDebugMilestoneBody,
              placement: MilestonePlacement.body,
              value: _milestoneChoice,
              onChanged: (v) => setState(() => _milestoneChoice = v),
            ),
            const SizedBox(height: 8),
            _milestonePicker(
              t: t,
              label: t.careerDebugMilestoneFinal,
              placement: MilestonePlacement.finalApotheose,
              value: _finalMilestoneChoice,
              onChanged: (v) => setState(() => _finalMilestoneChoice = v),
            ),
            const SizedBox(height: 12),
            Text(t.careerDebugUnlocks,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: UnlockKey.values.map((k) {
                final on = _unlocks.contains(k);
                return FilterChip(
                  label: Text(k.serialized,
                      style: const TextStyle(fontSize: 11)),
                  selected: on,
                  onSelected: (v) {
                    setState(() {
                      final next = Set<UnlockKey>.of(_unlocks);
                      if (v) {
                        next.add(k);
                      } else {
                        next.remove(k);
                      }
                      _unlocks = next;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(
                      () => _unlocks = milestoneService.acquiredUnlockKeys()),
                  child: Text(t.careerDebugUnlocksLoadCurrent),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _unlocks = const <UnlockKey>{}),
                  child: Text(t.careerDebugUnlocksClear),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _unlocks = UnlockKey.values.toSet()),
                  child: Text(t.careerDebugUnlocksAll),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.careerDebugShowTtsTexts,
                  style: const TextStyle(color: AppTheme.textPrimary)),
              value: _showText,
              onChanged: (v) => setState(() => _showText = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _regenerate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(t.careerDebugRegenerate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 12)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _milestonePicker({
    required AppLocalizations t,
    required String label,
    required MilestonePlacement placement,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final candidates = _catalog
        .where((m) => m.placement == placement)
        .toList()
      ..sort((a, b) => a.humilRequired.compareTo(b.humilRequired));
    final auto = placement == MilestonePlacement.body
        ? milestoneService.pendingFor(
            humiliationScore: _humil,
            obedience: _obed,
            allocation: _spec,
          )
        : milestoneService.pendingFinalFor(
            humiliationScore: _humil,
            obedience: _obed,
            allocation: _spec,
          );
    final autoLabel = auto != null
        ? '${t.careerDebugAuto} (${auto.id})'
        : '${t.careerDebugAuto} (${t.careerDebugNone})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          items: [
            DropdownMenuItem(
              value: _kAuto,
              child: Text(autoLabel,
                  style: const TextStyle(color: AppTheme.textPrimary)),
            ),
            DropdownMenuItem(
              value: _kNone,
              child: Text(t.careerDebugNone,
                  style: const TextStyle(color: AppTheme.textPrimary)),
            ),
            for (final m in candidates)
              DropdownMenuItem(
                value: m.id,
                child: Text(
                  'humil≥${m.humilRequired.toStringAsFixed(1)} — ${m.id}',
                  style: const TextStyle(color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  // ---------------- Header ----------------

  Widget _buildScenarioHeader(AppLocalizations t) {
    final res = _result;
    if (res == null) return const SizedBox.shrink();
    final session = res.session;
    final cfg = CareerLevel.forLevel(_level);
    final modes = <SessionMode>{
      for (final s in session.steps)
        if (s.mode != null) s.mode!,
    }.toList();
    final staminaFinal =
        res.staminaProfile.isEmpty ? 0.0 : res.staminaProfile.last;
    final humilCapFinal = _humil + 4.0;
    return Card(
      color: AppTheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.careerDebugSectionScenario} — lvl $_level',
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 4),
            Text(
              '${cfg.title} • ${_formatTime(session.durationSeconds)} • ${session.steps.length} steps',
              style:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            if (_appliedMilestone != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${t.careerDebugMilestoneBody} : ${_appliedMilestone!.id} (humil≥${_appliedMilestone!.humilRequired.toStringAsFixed(1)})',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12),
                ),
              ),
            if (_appliedFinalMilestone != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${t.careerDebugMilestoneFinal} : ${_appliedFinalMilestone!.id} (humil≥${_appliedFinalMilestone!.humilRequired.toStringAsFixed(1)})',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: modes
                  .map((m) => _modeBadge(context, m, dense: true))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statTile(t.careerDebugStatStamina,
                    staminaFinal.toStringAsFixed(1)),
                const SizedBox(width: 8),
                _statTile(t.careerDebugStatHumilCap,
                    humilCapFinal.toStringAsFixed(1)),
              ],
            ),
            const SizedBox(height: 8),
            _profileGraph(res),
            if (_failSimulatedAtStepTime != null)
              _buildFailSnapshot(t)
            else if (_forkResult != null)
              _buildForkBanner(t),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 10)),
            Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _profileGraph(CareerGenerationResult res) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(
        painter: _ProfilePainter(
          stamina: res.staminaProfile,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildFailSnapshot(AppLocalizations t) {
    final time = _failSimulatedAtStepTime!;
    final humil = _failSimulatedNewHumil!;
    final obed = _failSimulatedNewObed!;
    final next = _failSimulatedNextStepTime;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.careerDebugFailSnapshotTitle} (${_formatTime(time)})',
            style: const TextStyle(
                color: Colors.redAccent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${t.careerDebugHumiliation} : ${_humil.toStringAsFixed(1)} → ${humil.toStringAsFixed(1)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
          Text(
            '${t.careerDebugObedience} : ${_obed.toStringAsFixed(1)} → ${obed.toStringAsFixed(1)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
          Text(
            next == null
                ? t.careerDebugFailSnapshotNoNext
                : '${t.careerDebugFailSnapshotNext} : ${_formatTime(next)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _clearFailSnapshot,
              child: Text(t.careerDebugClearAnnotation),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForkBanner(AppLocalizations t) {
    final fork = _forkResult!;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.careerDebugForkBanner} — lvl $_forkLevel',
            style: const TextStyle(
                color: AppTheme.accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${t.careerDebugForkFrom} ${_formatTime(_forkStartTime!)} • ${fork.session.steps.length} ${t.careerDebugForkSteps}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
          if (_forkAppliedMilestone != null)
            Text(
              '${t.careerDebugMilestoneBody} : ${_forkAppliedMilestone!.id}',
              style:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          if (_forkAppliedFinalMilestone != null)
            Text(
              '${t.careerDebugMilestoneFinal} : ${_forkAppliedFinalMilestone!.id}',
              style:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _clearFork,
              child: Text(t.careerDebugClearFork),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Steps list ----------------

  List<Widget> _buildStepsList(AppLocalizations t) {
    final res = _result;
    if (res == null) return const [];
    final session = res.session;
    final widgets = <Widget>[];
    final cutoff = _forkStartTime;
    for (var i = 0; i < session.steps.length; i++) {
      final step = session.steps[i];
      if (cutoff != null && step.time >= cutoff) break;
      widgets.add(_stepCard(
        t: t,
        index: i,
        step: step,
        result: res,
        forkRoot: false,
      ));
    }
    final fork = _forkResult;
    if (fork != null && cutoff != null) {
      widgets.add(_forkSeparator(t, cutoff));
      for (var i = 0; i < fork.session.steps.length; i++) {
        final step = fork.session.steps[i];
        widgets.add(_stepCard(
          t: t,
          index: i,
          step: step,
          result: fork,
          forkRoot: true,
          timeOffset: cutoff,
        ));
      }
    }
    return widgets;
  }

  Widget _forkSeparator(AppLocalizations t, int time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: AppTheme.accent.withValues(alpha: 0.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${t.careerDebugForkBanner} • ${_formatTime(time)}',
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: AppTheme.accent.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard({
    required AppLocalizations t,
    required int index,
    required SessionStep step,
    required CareerGenerationResult result,
    required bool forkRoot,
    int timeOffset = 0,
  }) {
    final session = result.session;
    final absTime = step.time + timeOffset;
    final tags = _tagsFor(step, session, forkRoot: forkRoot);
    final mode = step.mode;
    final stepStart = step.time;
    final endTime = step.time + (step.duration ?? 0);
    final staminaStart = _profileAt(result.staminaProfile, stepStart);
    final staminaEnd = _profileAt(result.staminaProfile, endTime);
    final humilReq = (mode != null && !step.isTextOnly)
        ? HumiliationScale.requiredFor(
            mode: mode,
            from: step.from,
            to: step.to,
            bpm: step.bpm,
            duration: step.duration,
          )
        : 0.0;
    final isFailMarker = !forkRoot &&
        _failSimulatedAtStepTime != null &&
        absTime == _failSimulatedAtStepTime;
    final isFailSkipped = !forkRoot &&
        _failSimulatedAtStepTime != null &&
        _failSimulatedNextStepTime != null &&
        absTime > _failSimulatedAtStepTime! &&
        absTime < _failSimulatedNextStepTime!;
    // Fond coloré selon le tag dominant (milestone/boost/final/postFinal)
    // — remplace les anciens badges textuels qui surchargeaient la ligne.
    // Priorité : forkRoot > isFailMarker > tag de step. Le tag finalStep
    // bat boost (un step peut être les deux dans la fenêtre finish).
    Color? tagBg;
    Color? tagBorder;
    if (tags.contains(_StepTag.milestoneFinal)) {
      tagBg = Colors.deepPurpleAccent.withValues(alpha: 0.16);
      tagBorder = Colors.deepPurpleAccent.withValues(alpha: 0.5);
    } else if (tags.contains(_StepTag.milestoneBody)) {
      tagBg = Colors.purpleAccent.withValues(alpha: 0.14);
      tagBorder = Colors.purpleAccent.withValues(alpha: 0.45);
    } else if (tags.contains(_StepTag.finalStep)) {
      tagBg = Colors.redAccent.withValues(alpha: 0.18);
      tagBorder = Colors.redAccent.withValues(alpha: 0.55);
    } else if (tags.contains(_StepTag.boost)) {
      tagBg = Colors.orangeAccent.withValues(alpha: 0.14);
      tagBorder = Colors.orangeAccent.withValues(alpha: 0.45);
    } else if (tags.contains(_StepTag.postFinal)) {
      tagBg = Colors.lightGreen.withValues(alpha: 0.12);
      tagBorder = Colors.lightGreen.withValues(alpha: 0.4);
    }
    final bgColor = forkRoot
        ? AppTheme.accent.withValues(alpha: 0.08)
        : isFailMarker
            ? Colors.red.withValues(alpha: 0.10)
            : (tagBg ?? AppTheme.surface);
    final borderSide = forkRoot
        ? BorderSide(color: AppTheme.accent.withValues(alpha: 0.4))
        : (tagBorder != null ? BorderSide(color: tagBorder) : BorderSide.none);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: borderSide,
      ),
      child: Opacity(
        opacity: isFailSkipped ? 0.35 : 1,
        child: InkWell(
          onTap: step.isTextOnly
              ? null
              : () => _showStepActions(t, absTime),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '#${index + 1} • ${_formatTime(absTime)}',
                      style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(width: 8),
                    if (mode != null) _modeBadge(context, mode),
                    const Spacer(),
                    if (step.duration != null)
                      Text(
                        '${step.duration}s',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (step.from != null || step.to != null)
                      _chip(_positionLabel(context, step)),
                    if (step.bpm != null)
                      _chip(step.bpmEnd != null && step.bpmEnd != step.bpm
                          ? '${step.bpm}→${step.bpmEnd} BPM'
                          : '${step.bpm} BPM'),
                    if (step.isTextOnly) _chip(t.careerDebugTextOnly),
                    if (humilReq > 0)
                      _chip(
                          '${t.careerDebugHumilReq} ${humilReq.toStringAsFixed(1)}'),
                    // Les tags milestone/boost/final/postFinal sont
                    // matérialisés par la couleur de fond de la Card et
                    // n'apparaissent plus en badge ici — l'œil parse plus
                    // vite une coloration que de lire un texte.
                  ],
                ),
                if (_showText && step.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '« ${step.text} »',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (!step.isTextOnly)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        // Lecture : « début → fin » de la stamina projetée
                        // pour ce step. Sans ce delta on ne distinguait pas
                        // un breath (rampe ↑) d'un step rythme (rampe ↓) —
                        // la valeur fin seule pouvait afficher 70 pour un
                        // breath qui démarrait à 30 et remontait à 70.
                        _miniStat('stam.',
                            '${staminaStart.toStringAsFixed(0)} → ${staminaEnd.toStringAsFixed(0)}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Text(
      '$label $value',
      style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
      ),
    );
  }

  Widget _modeBadge(BuildContext context, SessionMode mode,
      {bool dense = false}) {
    final color = _modeColor(mode);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        mode.shortLabel(context),
        style: TextStyle(
          color: color,
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  void _showStepActions(AppLocalizations t, int absTime) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  '${t.careerDebugStepActionsTitle} — ${_formatTime(absTime)}',
                  style: const TextStyle(
                      color: AppTheme.accent, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.red),
                title: Text(t.careerDebugSimulateFail,
                    style: const TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _simulateFail(absTime);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upgrade, color: AppTheme.accent),
                title: Text(t.careerDebugSimulateSupplier,
                    style: const TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _simulateSupplier(absTime);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---------------- Helpers ----------------

  List<_StepTag> _tagsFor(SessionStep step, Session session,
      {required bool forkRoot}) {
    final tags = <_StepTag>[];
    if (session.milestoneStartTime != null &&
        session.milestoneDurationSeconds != null) {
      final start = session.milestoneStartTime!;
      final end = start + session.milestoneDurationSeconds!;
      if (step.time >= start && step.time < end) {
        tags.add(_StepTag.milestoneBody);
      }
    }
    if (session.finalMilestoneStartTime != null &&
        session.finalMilestoneDurationSeconds != null) {
      final start = session.finalMilestoneStartTime!;
      final end = start + session.finalMilestoneDurationSeconds!;
      if (step.time >= start && step.time < end) {
        tags.add(_StepTag.milestoneFinal);
      }
    }
    if (session.silentFinishStartTime != null &&
        step.time >= session.silentFinishStartTime!) {
      // Boost = entre silentFinishStartTime et finalStepTime (exclusif),
      // hors fenêtre milestone-final.
      if (session.finalStepTime != null &&
          step.time < session.finalStepTime!) {
        if (!tags.contains(_StepTag.milestoneFinal)) {
          tags.add(_StepTag.boost);
        }
      } else if (session.finalStepTime != null &&
          step.time == session.finalStepTime!) {
        tags.add(_StepTag.finalStep);
      } else if (session.finalStepTime != null &&
          step.time > session.finalStepTime!) {
        tags.add(_StepTag.postFinal);
      }
    }
    return tags;
  }

  double _profileAt(List<double> profile, int seconds) {
    if (profile.isEmpty) return 0;
    final idx = seconds.clamp(0, profile.length - 1);
    return profile[idx];
  }

  String _positionLabel(BuildContext context, SessionStep step) {
    final from = step.from?.localizedLabel(context);
    final to = step.to?.localizedLabel(context);
    if (from != null && to != null && from != to) return '$from → $to';
    return to ?? from ?? '';
  }

  static String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static Color _modeColor(SessionMode mode) {
    switch (mode) {
      case SessionMode.rhythm:
        return AppTheme.accent;
      case SessionMode.lick:
        return Colors.cyanAccent;
      case SessionMode.hold:
        return Colors.yellowAccent;
      case SessionMode.biffle:
        return Colors.redAccent;
      case SessionMode.breath:
        return Colors.lightGreenAccent;
      case SessionMode.beg:
        return Colors.purpleAccent;
      case SessionMode.freestyle:
        return Colors.grey;
      case SessionMode.hand:
        return const Color(0xFFFF9E80);
    }
  }
}

enum _StepTag {
  milestoneBody,
  milestoneFinal,
  boost,
  finalStep,
  postFinal,
}

class _ProfilePainter extends CustomPainter {
  final List<double> stamina;
  _ProfilePainter({required this.stamina});

  @override
  void paint(Canvas canvas, Size size) {
    if (stamina.isEmpty) return;
    final n = stamina.length;
    if (n < 2) return;
    const maxStamina = 100.0;
    final staminaPaint = Paint()
      ..color = const Color(0xFF80CBC4)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final staminaPath = Path();
    for (var i = 0; i < n; i++) {
      final dx = (i / (n - 1)) * size.width;
      final dy = size.height -
          (stamina[i].clamp(0.0, maxStamina) / maxStamina) * size.height;
      if (i == 0) {
        staminaPath.moveTo(dx, dy);
      } else {
        staminaPath.lineTo(dx, dy);
      }
    }
    canvas.drawPath(staminaPath, staminaPaint);
  }

  @override
  bool shouldRepaint(covariant _ProfilePainter old) =>
      old.stamina != stamina;
}
