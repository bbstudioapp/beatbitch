/// Rattrapage des profils dérivés par la boucle des défis BPM (§ « Correctif
/// proposé » de `docs/analysis/2026-08-07-challenge-bpm-target-runaway.md`).
///
/// Borner le calcul arrête l'hémorragie mais ne répare rien : `comfort` ne
/// redescend que sur signal négatif imputé, `best` est monotone par
/// construction, et le score d'humiliation carrière n'a **aucun** mécanisme
/// de retour. Sans réconciliation, une joueuse qui a subi la dérive garde sa
/// bannière absurde après mise à jour et son thermomètre de difficulté reste
/// neutralisé — tout le contenu qu'il gate ouvert d'un coup, définitivement.
///
/// ## Ce qui est ramené
///
/// - **Axes BPM** (`CapabilityUnit.bpm`) : `best` et `comfort` sont clampés
///   **par le haut** à [BeepEngine.kMaxBpm]. Pas de clamp par le bas : les
///   axes `minimize` (planchers BPM) descendent légitimement jusqu'à
///   `CapabilityRegulator.kBpmFloorPractical` (18), sous [BeepEngine.kMinBpm].
/// - **`successRate`** des axes ainsi corrigés : remis à
///   [CapabilityService.defaultSuccessRate]. Il a été construit sur des
///   succès dont on sait maintenant qu'ils étaient fictifs (crédités sur une
///   valeur jamais produite) ; le remettre au neutre, c'est dire « on ne sait
///   pas », ce qui est la vérité. Il se reconstruit en quelques séances
///   (EMA α = 0.30).
/// - **Score d'humiliation carrière** : plafonné à
///   [careerHumiliationCeiling], **et seulement si au moins un axe BPM a été
///   corrigé** — c'est-à-dire seulement sur les profils dont on a la preuve
///   matérielle qu'ils ont subi la dérive.
///
/// ## Ce que ça peut détruire à tort
///
/// On ne peut pas distinguer après coup un plancher d'humiliation issu de la
/// dérive d'une progression légitime. Sur un profil dérivé qui aurait *aussi*
/// dépassé [careerHumiliationCeiling] par un vrai parcours (beaucoup de
/// séances, beaucoup d'encores), la part légitime au-dessus du plafond est
/// écrasée. Le dommage est borné : le plafond est calibré au-dessus de toute
/// exigence du contenu, donc rien de ce qui était débloqué ne se reverrouille.
/// Un profil **sain** n'est jamais touché, quel que soit son score.
///
/// ## Quand
///
/// Une fois, au démarrage ([runIfNeeded] depuis `main`). Idempotente via
/// [flagKey] : le second lancement sort immédiatement. Un profil sain paie
/// une lecture de booléen puis, au premier lancement seulement, un scan des
/// axes — sans écriture.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';
import '../models/session_step.dart';
import 'beep_engine.dart';
import 'capability_axis.dart';
import 'capability_service.dart';
import 'humiliation_engine.dart';

/// Ce qu'une réconciliation a effectivement modifié. Sérialisé dans
/// [ProfileReconciliation.reportKey] et exposé par l'export diagnostic — un
/// profil modifié en silence est un profil qu'on ne peut pas diagnostiquer.
@immutable
class ProfileReconciliationReport {
  /// Par `CapabilityAxis.storageKey` : les valeurs avant/après.
  final Map<String, ReconciledAxis> axes;

  /// Score d'humiliation carrière avant/après, `null` si non touché.
  final double? humiliationBefore;
  final double? humiliationAfter;

  const ProfileReconciliationReport({
    required this.axes,
    this.humiliationBefore,
    this.humiliationAfter,
  });

  bool get isEmpty => axes.isEmpty && humiliationAfter == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'axes': <String, dynamic>{
          for (final e in axes.entries) e.key: e.value.toJson(),
        },
        if (humiliationAfter != null)
          'humiliationCareer': <String, dynamic>{
            'before': humiliationBefore,
            'after': humiliationAfter,
          },
      };

  static ProfileReconciliationReport? fromJson(Map<String, dynamic> j) {
    final rawAxes = j['axes'];
    final axes = <String, ReconciledAxis>{};
    if (rawAxes is Map) {
      for (final e in rawAxes.entries) {
        final v = e.value;
        if (v is Map) {
          axes[e.key.toString()] =
              ReconciledAxis.fromJson(v.cast<String, dynamic>());
        }
      }
    }
    final humil = j['humiliationCareer'];
    return ProfileReconciliationReport(
      axes: axes,
      humiliationBefore:
          humil is Map ? (humil['before'] as num?)?.toDouble() : null,
      humiliationAfter:
          humil is Map ? (humil['after'] as num?)?.toDouble() : null,
    );
  }
}

/// Valeurs avant/après pour un axe ramené dans le jouable.
@immutable
class ReconciledAxis {
  final double? bestBefore;
  final double? bestAfter;
  final double? comfortBefore;
  final double? comfortAfter;
  final double? successRateBefore;
  final double? successRateAfter;

  const ReconciledAxis({
    this.bestBefore,
    this.bestAfter,
    this.comfortBefore,
    this.comfortAfter,
    this.successRateBefore,
    this.successRateAfter,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'best': <String, dynamic>{'before': bestBefore, 'after': bestAfter},
        'comfort': <String, dynamic>{
          'before': comfortBefore,
          'after': comfortAfter,
        },
        'successRate': <String, dynamic>{
          'before': successRateBefore,
          'after': successRateAfter,
        },
      };

  static ReconciledAxis fromJson(Map<String, dynamic> j) {
    double? at(String field, String side) {
      final v = j[field];
      return v is Map ? (v[side] as num?)?.toDouble() : null;
    }

    return ReconciledAxis(
      bestBefore: at('best', 'before'),
      bestAfter: at('best', 'after'),
      comfortBefore: at('comfort', 'before'),
      comfortAfter: at('comfort', 'after'),
      successRateBefore: at('successRate', 'before'),
      successRateAfter: at('successRate', 'after'),
    );
  }
}

class ProfileReconciliation {
  /// Drapeau d'idempotence. Versionné : une réconciliation ultérieure d'une
  /// autre nature prendra `.v2` et se rejouera une fois de son côté.
  static const String flagKey = 'profile.reconcile.bpm_runaway.v1';

  /// Trace JSON de ce qui a été modifié. Absente si rien n'a bougé.
  static const String reportKey = 'profile.reconcile.bpm_runaway.v1.report';

  /// Horodatage ISO-8601 de la passe (posé même quand rien n'a bougé —
  /// il dit « la v1 a tourné le … », ce qui est l'information utile en
  /// diagnostic).
  static const String ranAtKey = 'profile.reconcile.bpm_runaway.v1.at';

  static const String _prefix = 'cap.';
  static const String _suffixBest = '.best';
  static const String _suffixComfort = '.comfort';
  static const String _suffixSuccessRate = '.sr';
  static const String _humiliationKey = 'stats.humiliation_level';

  /// Plafond appliqué au score d'humiliation carrière d'un profil dérivé.
  ///
  /// = le plancher le plus élevé qu'un défi BPM **jouable** puisse
  /// légitimement poser : `rhythm tip→full` à [BeepEngine.kMaxBpm], soit le
  /// pire cas de `_raiseHumiliationFloorFromRecord` une fois borné (≈ 269).
  ///
  /// Choisi là et pas plus bas parce qu'il domine toutes les exigences du
  /// contenu — le final le plus coûteux est le `hold full` au cap de 80 s de
  /// `_pickFinal`, qui demande 222,5. Ramener un profil dérivé à ce plafond
  /// ne **reverrouille** donc rien de ce qui lui était accessible : ça lui
  /// rend seulement un thermomètre qui bouge.
  static double get careerHumiliationCeiling => HumiliationScale.requiredFor(
        mode: SessionMode.rhythm,
        from: Position.tip,
        to: Position.full,
        bpm: BeepEngine.kMaxBpm,
        duration: 0,
      );

  /// Point d'entrée applicatif — à appeler une fois au démarrage.
  /// Renvoie `null` si la passe a déjà tourné, sinon le rapport (qui peut
  /// être vide sur un profil sain).
  static Future<ProfileReconciliationReport?> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    return applyTo(prefs);
  }

  /// Idem, sur une instance de prefs fournie (tests).
  @visibleForTesting
  static Future<ProfileReconciliationReport?> applyTo(
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(flagKey) ?? false) return null;

    final axes = <String, ReconciledAxis>{};
    for (final axis in CapabilityAxis.values) {
      if (axis.unit != CapabilityUnit.bpm) continue;
      final adjusted = await _reconcileAxis(prefs, axis);
      if (adjusted != null) axes[axis.storageKey] = adjusted;
    }

    double? humiliationBefore;
    double? humiliationAfter;
    // Le thermomètre n'est touché que sur les profils dont un axe BPM prouve
    // la dérive. Un profil sain garde son score, aussi haut soit-il.
    if (axes.isNotEmpty) {
      final ceiling = careerHumiliationCeiling;
      final current = prefs.getDouble(_humiliationKey);
      if (current != null && current > ceiling) {
        humiliationBefore = current;
        humiliationAfter = ceiling;
        await prefs.setDouble(_humiliationKey, ceiling);
      }
    }

    final report = ProfileReconciliationReport(
      axes: axes,
      humiliationBefore: humiliationBefore,
      humiliationAfter: humiliationAfter,
    );
    await prefs.setBool(flagKey, true);
    await prefs.setString(ranAtKey, DateTime.now().toUtc().toIso8601String());
    if (!report.isEmpty) {
      await prefs.setString(reportKey, jsonEncode(report.toJson()));
    }
    return report;
  }

  /// Relit la trace persistée (export diagnostic). `null` si la passe n'a
  /// rien modifié ou n'a pas encore tourné.
  static ProfileReconciliationReport? storedReport(SharedPreferences prefs) {
    final raw = prefs.getString(reportKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ProfileReconciliationReport.fromJson(
        decoded.cast<String, dynamic>(),
      );
    } on FormatException {
      return null;
    }
  }

  /// Clamp par le haut de `best` / `comfort`, et remise à neutre du
  /// `successRate` si l'un des deux a bougé. Renvoie `null` si l'axe était
  /// déjà dans le jouable (cas de tout profil sain).
  static Future<ReconciledAxis?> _reconcileAxis(
    SharedPreferences prefs,
    CapabilityAxis axis,
  ) async {
    final base = '$_prefix${axis.storageKey}';
    final best = prefs.getDouble('$base$_suffixBest');
    final comfort = prefs.getDouble('$base$_suffixComfort');
    final ceiling = BeepEngine.kMaxBpm.toDouble();

    final bestOver = best != null && best > ceiling;
    final comfortOver = comfort != null && comfort > ceiling;
    if (!bestOver && !comfortOver) return null;

    final sr = prefs.getDouble('$base$_suffixSuccessRate');
    if (bestOver) await prefs.setDouble('$base$_suffixBest', ceiling);
    if (comfortOver) await prefs.setDouble('$base$_suffixComfort', ceiling);
    await prefs.setDouble(
      '$base$_suffixSuccessRate',
      CapabilityService.defaultSuccessRate,
    );

    return ReconciledAxis(
      bestBefore: best,
      bestAfter: bestOver ? ceiling : best,
      comfortBefore: comfort,
      comfortAfter: comfortOver ? ceiling : comfort,
      successRateBefore: sr,
      successRateAfter: CapabilityService.defaultSuccessRate,
    );
  }
}
