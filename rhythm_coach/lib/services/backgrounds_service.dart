import 'dart:math';

import 'package:flutter/foundation.dart';

import 'backgrounds_loader.dart';

@immutable
class BackgroundContext {
  final String? mode;
  final String? position;
  final String? coach;
  final String? phase;
  final String? tier;

  const BackgroundContext({
    this.mode,
    this.position,
    this.coach,
    this.phase,
    this.tier,
  });

  String? valueFor(BackgroundTagCategory cat) => switch (cat) {
        BackgroundTagCategory.mode => mode,
        BackgroundTagCategory.position => position,
        BackgroundTagCategory.coach => coach,
        BackgroundTagCategory.phase => phase,
        BackgroundTagCategory.tier => tier,
        BackgroundTagCategory.viewpoint => null,
        BackgroundTagCategory.moment => 'play',
      };
}

class BackgroundsService {
  BackgroundsService._();

  static final BackgroundsService instance = BackgroundsService._();

  final ValueNotifier<BackgroundEntry?> current =
      ValueNotifier<BackgroundEntry?>(null);

  BackgroundsBundle _bundle = BackgroundsBundle.empty;
  Random _rng = Random();

  @visibleForTesting
  set debugRandom(Random rng) => _rng = rng;

  static const Set<String> handRaisedHolds = {
    'helene-pack-hold-26002-ltx-pp-s26002',
    'helene-pack-nu1-hold-26002-ltx-pp-s26002',
    'helene-pack-nu2-hold-26002-anim',
    'lina-pack-hold-25001-ltx-pp-s25001',
    'lina-pack-hold-25002-ltx-pp-s25002',
    'lina-pack-nu1-hold-25001-anim',
    'lina-pack-nu1-hold-25002-anim',
    'lina-pack-nu2-hold-25001-anim',
    'lina-pack-nu2-hold-25002-anim',
  };

  static const List<String> _tierNames = ['nu1', 'nu2'];
  static int _rankOf(String? tier) => _tierNames.indexOf(tier ?? '') + 1;
  static String? _nameOf(int rank) => rank == 0 ? null : _tierNames[rank - 1];

  Set<String> _tieredCoaches = const {};
  int _tierRank = 0;
  final List<BackgroundEntry> _transitions = [];
  BackgroundContext? _afterTransitions;
  BackgroundContext? _lastGesture;
  BackgroundEntry? _intro;
  ({BackgroundEntry? entry})? _beforeMilestone;

  void _resetTiers() {
    _tierRank = 0;
    _transitions.clear();
    _afterTransitions = null;
    _lastGesture = null;
    _beforeMilestone = null;
  }

  void setBundle(BackgroundsBundle bundle) {
    _bundle = bundle;
    _tieredCoaches = {
      for (final e in bundle.entries)
        if (e.tier != null) ...?e.tagsByCategory[BackgroundTagCategory.coach],
    };
    _resetTiers();
    final cur = current.value;
    if (cur != null && _bundle.byId(cur.id) == null) {
      current.value = null;
    }
  }

  bool get hasEntries => _bundle.entries.isNotEmpty;

  void setById(String id) {
    final entry = _bundle.byId(id);
    if (entry == null) return;
    _transitions.clear();
    _afterTransitions = null;
    current.value = entry;
  }

  void pickForContext(BackgroundContext ctx, {bool playerScene = false}) {
    if (_bundle.entries.isEmpty) return;
    if (current.value != _intro) _intro = null;
    final shown = current.value;
    if (shown != null && (shown.isPov || shown.isMilestone)) {
      _transitions.clear();
      _afterTransitions = null;
      _beforeMilestone = null;
    }
    final tiered = ctx.coach != null && _tieredCoaches.contains(ctx.coach);
    final before = _tierRank;
    if (tiered) _tierRank = max(_tierRank, _rankOf(ctx.tier));
    final effective = BackgroundContext(
      mode: ctx.mode,
      position: ctx.position,
      coach: ctx.coach,
      phase: ctx.phase,
      tier: tiered ? _nameOf(_tierRank) : null,
    );
    final wasPlaying = _transitions.isNotEmpty;
    for (var r = before + 1; r <= _tierRank; r++) {
      final strip = _transitionTo(ctx.coach, r);
      if (strip != null) _transitions.add(strip);
    }
    if (_transitions.isNotEmpty) {
      _afterTransitions = effective;
      if (!wasPlaying) current.value = _transitions.first;
      return;
    }
    if (playerScene && _insertPlayerScene(effective)) return;
    _pick(effective);
  }

  bool _insertPlayerScene(BackgroundContext ctx) {
    final shown = current.value;
    if (ctx.phase != null ||
        shown == null ||
        shown.isIntro ||
        shown == _intro ||
        shown.isPov ||
        shown.isTierTransition ||
        shown.tagsByCategory.containsKey(BackgroundTagCategory.phase)) {
      return false;
    }
    final scenes =
        _bundle.entries.where((e) => e.isPov && _sceneMatches(e, ctx)).toList();
    if (scenes.isEmpty || _rng.nextInt(3) != 0) return false;
    final scene = scenes[_rng.nextInt(scenes.length)];
    _transitions.add(scene);
    _afterTransitions = ctx;
    current.value = scene;
    return true;
  }

  static bool _sceneMatches(BackgroundEntry e, BackgroundContext ctx) =>
      (!e.tags.contains('suckle') || ctx.position == 'head') &&
      [BackgroundTagCategory.mode, BackgroundTagCategory.position].every(
          (cat) => e.tagsByCategory[cat]?.contains(ctx.valueFor(cat)) ?? true);

  void transitionFinished(BackgroundEntry entry) {
    if (_transitions.isEmpty || _transitions.first.id != entry.id) return;
    _transitions.removeAt(0);
    if (_transitions.isNotEmpty) {
      current.value = _transitions.first;
      return;
    }
    final ctx = _afterTransitions;
    final before = _beforeMilestone;
    _afterTransitions = null;
    _beforeMilestone = null;
    if (ctx != null) {
      _pick(ctx);
    } else if (before != null) {
      current.value = before.entry;
    }
  }

  bool pickFail(String? coach) {
    final tiered = coach != null && _tieredCoaches.contains(coach);
    final best = _rank(
      BackgroundContext(
        coach: coach,
        phase: 'fail',
        tier: tiered ? _nameOf(_tierRank) : null,
      ),
      where: (e) => e.tags.contains('fail'),
    ).best;
    if (best.isEmpty) return false;
    _transitions.clear();
    _afterTransitions = null;
    _setExcluding(best);
    return true;
  }

  bool pickPunish(String? coach) {
    final own = _momentOf(coach, 'punish');
    if (own.isEmpty) return false;
    _transitions.clear();
    _afterTransitions = null;
    _beforeMilestone = null;
    _setExcluding(own);
    return true;
  }

  bool pickMilestone(String? coach) {
    final own = _momentOf(coach, 'milestone');
    if (own.isEmpty) return false;
    _beforeMilestone = _transitions.isEmpty ? (entry: current.value) : null;
    final milestone = own[_rng.nextInt(own.length)];
    _transitions
      ..clear()
      ..add(milestone);
    current.value = milestone;
    return true;
  }

  List<BackgroundEntry> _momentOf(String? coach, String moment) {
    final tier = coach != null && _tieredCoaches.contains(coach)
        ? _nameOf(_tierRank)
        : null;
    return _bundle.entries
        .where((e) =>
            e.tier == tier &&
            (e.tagsByCategory[BackgroundTagCategory.moment]?.contains(moment) ??
                false) &&
            (e.tagsByCategory[BackgroundTagCategory.coach]?.contains(coach) ??
                false))
        .toList();
  }

  bool pickIntro(String? coach, {String? tier}) {
    final own = _bundle.entries.where((e) =>
        e.tagsByCategory[BackgroundTagCategory.coach]?.contains(coach) ??
        false);
    final intros = own.where((e) => e.isIntro && e.tier == tier).toList();
    final candidates = intros.isNotEmpty
        ? intros
        : own
            .where((e) =>
                e.tagsByCategory[BackgroundTagCategory.moment]
                    ?.contains('play') ??
                false)
            .take(1)
            .toList();
    if (candidates.isEmpty) {
      _transitions.clear();
      _afterTransitions = null;
      current.value = null;
      return false;
    }
    _transitions.clear();
    _afterTransitions = null;
    if (!candidates.contains(current.value)) _setExcluding(candidates);
    _intro = current.value;
    return true;
  }

  BackgroundEntry? _transitionTo(String? coach, int rank) {
    final candidates = _bundle.entries
        .where((e) =>
            e.isTierTransition &&
            e.tier == _nameOf(rank) &&
            (e.tagsByCategory[BackgroundTagCategory.coach]?.contains(coach) ??
                false))
        .toList();
    return candidates.isEmpty
        ? null
        : candidates[_rng.nextInt(candidates.length)];
  }

  void _pick(BackgroundContext ctx) {
    final ranked = _rank(ctx);
    if (ranked.withheld) {
      _keepGesture(ctx);
      return;
    }
    if (ranked.best.isNotEmpty) {
      _lastGesture = ctx;
      _setExcluding(ranked.best);
      return;
    }
    if (ranked.untagged.isNotEmpty) {
      _setExcluding(ranked.untagged);
      return;
    }
    if (ctx.coach != null) {
      _keepCoach(ctx);
      return;
    }
    current.value = null;
  }

  void _keepCoach(BackgroundContext ctx) {
    final own = _bundle.entries
        .where((e) =>
            !e.isTierTransition &&
            !e.isPov &&
            !handRaisedHolds.contains(e.id) &&
            (e.tagsByCategory[BackgroundTagCategory.phase]
                    ?.contains(ctx.phase) ??
                true) &&
            (e.tagsByCategory[BackgroundTagCategory.coach]
                    ?.contains(ctx.coach) ??
                false))
        .toList();
    final atTier = own.where((e) => e.tier == ctx.tier).toList();
    final pool = atTier.isEmpty ? own : atTier;
    if (!pool.contains(current.value)) _setExcluding(pool);
  }

  void _keepGesture(BackgroundContext ctx) {
    final last = _lastGesture;
    final gesture = last?.mode == 'rhythm'
        ? _rank(BackgroundContext(
            mode: last!.mode,
            position: last.position,
            coach: ctx.coach,
            phase: ctx.phase,
            tier: ctx.tier,
          )).best
        : const <BackgroundEntry>[];
    if (gesture.isEmpty) {
      if (last != null || (current.value?.isTierTransition ?? false)) {
        final rhythms = _coachRhythmsAt(ctx);
        if (!rhythms.contains(current.value)) _setExcluding(rhythms);
      }
      return;
    }
    if (!gesture.contains(current.value)) _setExcluding(gesture);
  }

  List<BackgroundEntry> _coachRhythmsAt(BackgroundContext ctx) {
    final rhythms = _bundle.entries
        .where((e) =>
            e.tier == ctx.tier &&
            (e.tagsByCategory[BackgroundTagCategory.mode]?.contains('rhythm') ??
                false) &&
            (e.tagsByCategory[BackgroundTagCategory.phase]
                    ?.contains(ctx.phase) ??
                true) &&
            !handRaisedHolds.contains(e.id) &&
            (e.tagsByCategory[BackgroundTagCategory.coach]
                    ?.contains(ctx.coach) ??
                false))
        .toList();
    final samePosition = rhythms
        .where((e) =>
            e.tagsByCategory[BackgroundTagCategory.position]
                ?.contains(ctx.position) ??
            false)
        .toList();
    return samePosition.isEmpty ? rhythms : samePosition;
  }

  ({
    List<BackgroundEntry> best,
    List<BackgroundEntry> untagged,
    bool withheld,
  }) _rank(
    BackgroundContext ctx, {
    bool Function(BackgroundEntry)? where,
  }) {
    var bestScore = -1;
    final byScore = <int, List<BackgroundEntry>>{};
    final untagged = <BackgroundEntry>[];
    var withheldScore = -1;
    for (final e in _bundle.entries) {
      if (e.isTierTransition || (where != null && !where(e))) continue;
      if (!e.hasTags) {
        untagged.add(e);
        continue;
      }
      final score = _scoreEntry(e, ctx);
      if (score < 0) continue;
      if (handRaisedHolds.contains(e.id)) {
        withheldScore = max(withheldScore, score);
        continue;
      }
      byScore.putIfAbsent(score, () => <BackgroundEntry>[]).add(e);
      if (score > bestScore) bestScore = score;
    }
    return (
      best: bestScore > 0
          ? (byScore[bestScore] ?? const <BackgroundEntry>[])
          : const <BackgroundEntry>[],
      untagged: untagged,
      withheld: withheldScore > bestScore,
    );
  }

  static int _scoreEntry(BackgroundEntry e, BackgroundContext ctx) {
    if (ctx.tier != null && e.tier == null) return -1;
    var score = 0;
    for (final cat in BackgroundTagCategory.values) {
      final entryTags = e.tagsByCategory[cat];
      if (entryTags == null || entryTags.isEmpty) continue;
      final wanted = ctx.valueFor(cat);
      if (wanted == null) return -1;
      if (!entryTags.contains(wanted)) return -1;
      score += switch (cat) {
        BackgroundTagCategory.phase => 3,
        BackgroundTagCategory.moment => 0,
        _ => 1,
      };
    }
    return score;
  }

  void _setExcluding(List<BackgroundEntry> candidates) {
    if (candidates.isEmpty) return;
    if (candidates.length == 1) {
      current.value = candidates.first;
      return;
    }
    final cur = current.value;
    final idx = cur == null ? -1 : candidates.indexOf(cur);
    if (idx < 0) {
      current.value = candidates[_rng.nextInt(candidates.length)];
      return;
    }
    final draw = _rng.nextInt(candidates.length - 1);
    final pick = draw >= idx ? draw + 1 : draw;
    current.value = candidates[pick];
  }

  void clear({bool keepTier = false}) {
    current.value = null;
    final rank = _tierRank;
    _resetTiers();
    if (keepTier) _tierRank = rank;
  }

  @visibleForTesting
  void debugResetForTest() {
    _bundle = BackgroundsBundle.empty;
    _tieredCoaches = const {};
    current.value = null;
    _resetTiers();
  }
}
