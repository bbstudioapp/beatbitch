import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/humiliation_engine.dart';
import '../models/level_milestone.dart';
import '../models/specialization.dart';
import '../models/milestone_text_override.dart';
import '../models/unlock_key.dart';

class MilestoneLoader {
  static const String _assetPath = 'assets/career/milestones.json';

  Future<List<LevelMilestone>> load() async {
    final raw = await rootBundle.loadString(_assetPath);
    final data = json.decode(raw) as Map<String, dynamic>;
    final list = (data['milestones'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(_parse)
        .whereType<LevelMilestone>()
        .toList();
  }

  /// Charge la surcharge textuelle pour la milestone [id] dans la langue
  /// [lang]. Retourne `null` si le fichier n'existe pas ou est invalide.
  Future<MilestoneTextOverride?> loadOverride(String id, String lang) async {
    final path = 'assets/career/milestones/${id}_$lang.json';
    try {
      final raw = await rootBundle.loadString(path);
      final data = json.decode(raw) as Map<String, dynamic>;
      final stepTextsRaw = data['stepTexts'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final stepTexts = <int, String>{};
      stepTextsRaw.forEach((k, v) {
        final time = int.tryParse(k);
        if (time != null && v is String) {
          stepTexts[time] = v;
        }
      });
      final announcement = data['unlockAnnouncement'] as String?;
      final label = data['displayLabel'] as String?;
      return MilestoneTextOverride(
        stepTexts: stepTexts,
        unlockAnnouncement: announcement,
        displayLabel: label,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MilestoneLoader] no override for $id/$lang ($e)');
      }
      return null;
    }
  }

  LevelMilestone? _parse(Map<String, dynamic> raw) {
    final id = raw['id'] as String?;
    // `level` du JSON = niveau global minimum pour que la milestone soit
    // candidate (garde-fou explicite, complémentaire au filtre humil).
    // Default 1 = pas de garde si non spécifié.
    final minLevel = (raw['level'] as num?)?.toInt() ?? 1;
    final label = raw['displayLabel'] as String?;
    final seqRaw = raw['sequence'] as List<dynamic>? ?? const [];
    if (id == null || label == null || seqRaw.isEmpty) {
      return null;
    }
    // Flag pédagogique au niveau milestone : activer le countdown visuel
    // sur les steps "scénarisés à durée connue" de la séquence — hold
    // profonds (throat/full) où doser l'effort est crucial, et breath où
    // anticiper la reprise aide. Pas de propag sur hold tip/head/mid
    // (pas un défi physique) ni sur rhythm/lick/hand/biffle/beg (le tempo
    // donne déjà le repère). Cf. memo `feedback_hold_countdown_scope`.
    final countdown = raw['showCountdown'] == true;
    bool wantsCountdown(SessionStep s) {
      if (!countdown) return false;
      if (s.mode == SessionMode.breath) return true;
      if (s.mode == SessionMode.hold &&
          (s.to == Position.throat || s.to == Position.full)) {
        return true;
      }
      return false;
    }

    // Expand chainAction : un step JSON avec `chainAction` produit deux
    // SessionStep consécutifs dans la séquence. Le second hérite du `time`
    // du parent + sa durée.
    final sequence = <SessionStep>[];
    for (final raw in seqRaw.whereType<Map<String, dynamic>>()) {
      final parsed = SessionStep.fromJson(raw);
      final parent = wantsCountdown(parsed)
          ? SessionStep(
              time: parsed.time,
              text: parsed.text,
              from: parsed.from,
              to: parsed.to,
              bpm: parsed.bpm,
              bpmEnd: parsed.bpmEnd,
              duration: parsed.duration,
              mode: parsed.mode,
              chainAction: parsed.chainAction,
              swallowMode: parsed.swallowMode,
              background: parsed.background,
              showCountdown: true,
            )
          : parsed;
      sequence.add(parent);
      final chain = parent.chainAction;
      if (chain != null) {
        final chainStep = SessionStep(
          time: parent.time + (parent.duration ?? 0),
          text: chain.text,
          from: chain.from,
          to: chain.to,
          bpm: chain.bpm,
          duration: chain.duration,
          mode: chain.mode,
        );
        sequence.add(wantsCountdown(chainStep)
            ? SessionStep(
                time: chainStep.time,
                text: chainStep.text,
                from: chainStep.from,
                to: chainStep.to,
                bpm: chainStep.bpm,
                duration: chainStep.duration,
                mode: chainStep.mode,
                showCountdown: true,
              )
            : chainStep);
      }
    }
    final last = sequence.last;
    final duration = last.time + (last.duration ?? 0);
    final unlocks = (raw['unlocks'] as List<dynamic>? ?? const [])
        .map((e) => UnlockKey.fromString(e as String?))
        .whereType<UnlockKey>()
        .toList();
    final requires = (raw['requires'] as List<dynamic>? ?? const [])
        .map((e) => UnlockKey.fromString(e as String?))
        .whereType<UnlockKey>()
        .toList();
    final insertMin = (raw['insertAtMinSeconds'] as num?)?.toInt();
    final insertMax = (raw['insertAtMaxSeconds'] as num?)?.toInt();
    final maxRetry = (raw['maxRetry'] as num?)?.toInt() ?? 1;
    final requiresHands = (raw['requiresHands'] as bool?) ?? false;
    final branches = _parseBranches(raw);
    final placement = _parsePlacement(raw['placement'] as String?);
    return LevelMilestone(
      id: id,
      minLevel: minLevel,
      humilRequired: _computeHumilRequired(sequence),
      displayLabel: label,
      sequence: sequence,
      durationSeconds: duration,
      unlocks: unlocks,
      requires: requires,
      insertAtMinSeconds: insertMin,
      insertAtMaxSeconds: insertMax,
      maxRetry: maxRetry,
      requiresHands: requiresHands,
      branches: branches,
      placement: placement,
    );
  }

  /// Humiliation maximale requise par la séquence — sert de seuil de
  /// candidature côté `MilestoneService.pendingFor(...)`. Calculée une
  /// fois au load (le résultat est figé dans le modèle).
  ///
  /// Règle : pour les `hold`, on **agrège la durée** des steps consécutifs
  /// qui partagent le même `to`. Sémantique pédagogique : tenir 7s + 9s
  /// + 8s à mid sans pause au milieu équivaut physiquement à un hold mid
  /// 24s, pas à trois holds courts isolés. Toute step de mode différent
  /// OU de position différente (y compris un `breath`) casse la chaîne
  /// et déclenche son évaluation. Les autres modes (rhythm/lick/beg/
  /// biffle/hand/breath/freestyle) ne dépendent pas de la durée dans
  /// `requiredFor`, donc l'agrégation n'a pas d'effet sur eux — on les
  /// évalue step par step comme avant.
  static double _computeHumilRequired(List<SessionStep> sequence) {
    var max = 0.0;
    Position? chainTo;
    int chainDur = 0;

    void flushChain() {
      if (chainTo == null) return;
      final r = HumiliationScale.requiredFor(
        mode: SessionMode.hold,
        to: chainTo,
        duration: chainDur,
      );
      if (r > max) max = r;
      chainTo = null;
      chainDur = 0;
    }

    for (final s in sequence) {
      final mode = s.mode ?? SessionMode.rhythm;
      if (mode == SessionMode.hold && s.to != null) {
        if (chainTo == s.to) {
          chainDur += s.duration ?? 0;
        } else {
          flushChain();
          chainTo = s.to;
          chainDur = s.duration ?? 0;
        }
        continue;
      }
      flushChain();
      final r = HumiliationScale.requiredFor(
        mode: mode,
        from: s.from,
        to: s.to,
        bpm: s.bpm,
        duration: s.duration,
      );
      if (r > max) max = r;
    }
    flushChain();
    return max;
  }

  /// Parse `placement: "final"` (ou `"final_apotheose"`) en
  /// `MilestonePlacement.finalApotheose`. Toute autre valeur (ou absent)
  /// retombe sur `body` — comportement historique.
  static MilestonePlacement _parsePlacement(String? raw) {
    if (raw == null) return MilestonePlacement.body;
    final lower = raw.toLowerCase().trim();
    if (lower == 'final' || lower == 'final_apotheose') {
      return MilestonePlacement.finalApotheose;
    }
    return MilestonePlacement.body;
  }

  /// Lit les branches d'un milestone depuis le JSON. Accepte deux formats :
  /// - `"branches": ["endurance", "resilience"]` (multi, recommandé)
  /// - `"branch": "endurance"` (singleton, rétrocompatibilité)
  /// Si les deux sont présents, `branches` gagne. Strings inconnues sont
  /// silencieusement filtrées.
  static List<SpecializationBranch> _parseBranches(Map<String, dynamic> raw) {
    final list = raw['branches'];
    if (list is List) {
      return list
          .map((e) => _parseBranch(e?.toString()))
          .whereType<SpecializationBranch>()
          .toList();
    }
    final single = _parseBranch(raw['branch'] as String?);
    return single == null ? const [] : [single];
  }

  static SpecializationBranch? _parseBranch(String? raw) {
    if (raw == null) return null;
    final lower = raw.toLowerCase();
    for (final b in SpecializationBranch.values) {
      if (b.name == lower) return b;
    }
    if (lower == 'rythme_biffle' || lower == 'rythme-biffle') {
      return SpecializationBranch.rythmeBiffle;
    }
    return null;
  }
}
