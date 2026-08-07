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
///
/// ## Ce qu'elle ne peut pas faire
///
/// **Empêcher l'app de démarrer.** Elle est le deuxième appel de `main()` :
/// une exception y remonterait hors de `main()` et une attente qui ne se
/// résout jamais figerait le lancement avant le premier `runApp`. Les deux
/// seraient pires que le défaut corrigé. D'où trois garde-fous :
/// lectures tolérantes au type persisté ([_readDouble]), écritures ordonnées
/// pour qu'une passe interrompue reste rattrapable, et un [startupBudget]
/// doublé d'un `catch` total dans [runIfNeeded].
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

  /// Temps accordé à la passe au démarrage. Elle enchaîne une vingtaine de
  /// lectures et d'écritures sur des préférences persistées, dont chaque
  /// écriture repasse par le canal de plateforme natif : si le canal se
  /// fige, l'attente ne se résout jamais et un `try`/`catch` n'y peut rien.
  /// Passé ce budget on rend la main **sans poser [flagKey]** — l'app
  /// démarre sur un profil non réconcilié et la passe se rejouera au
  /// prochain lancement.
  static const Duration startupBudget = Duration(seconds: 2);

  /// Point d'entrée applicatif — à appeler une fois au démarrage.
  /// Renvoie `null` si la passe a déjà tourné, a échoué ou a dépassé son
  /// budget ; sinon le rapport (qui peut être vide sur un profil sain).
  ///
  /// Ne propage **rien** : un profil non réconcilié est un désagrément
  /// (une bannière absurde de plus jusqu'au prochain lancement), une
  /// exception ici est une app qui ne démarre pas.
  static Future<ProfileReconciliationReport?> runIfNeeded() async {
    try {
      return await _resolveAndApply().timeout(startupBudget);
    } on Object catch (e) {
      debugPrint('ProfileReconciliation: passe abandonnée ($e)');
      return null;
    }
  }

  static Future<ProfileReconciliationReport?> _resolveAndApply() async {
    final prefs = await SharedPreferences.getInstance();
    return applyTo(prefs);
  }

  /// Idem, sur une instance de prefs fournie (tests).
  ///
  /// Non protégée, volontairement : c'est ici qu'on veut voir échouer un
  /// profil pathologique en test, pendant que [runIfNeeded] garantit qu'un
  /// échec ne coûte que la réconciliation.
  @visibleForTesting
  static Future<ProfileReconciliationReport?> applyTo(
    SharedPreferences prefs,
  ) async {
    if (_readBool(prefs, flagKey)) return null;

    // 1. Diagnostic — aucune écriture : on décide de tout avant de toucher
    //    quoi que ce soit.
    final fixes = <_AxisFix>[];
    for (final axis in CapabilityAxis.values) {
      if (axis.unit != CapabilityUnit.bpm) continue;
      final fix = _diagnoseAxis(prefs, axis);
      if (fix != null) fixes.add(fix);
    }

    double? humiliationBefore;
    double? humiliationAfter;
    // Le thermomètre n'est touché que sur les profils dont un axe BPM prouve
    // la dérive. Un profil sain garde son score, aussi haut soit-il.
    if (fixes.isNotEmpty) {
      final ceiling = careerHumiliationCeiling;
      final current = _readDouble(prefs, _humiliationKey);
      if (current != null && current > ceiling) {
        humiliationBefore = current;
        humiliationAfter = ceiling;
      }
    }

    // 2. Écritures — l'humiliation d'abord, les axes ensuite, [flagKey] en
    //    tout dernier. Chaque écriture peut être la dernière (canal figé,
    //    processus tué) : tant qu'un axe reste hors du jouable, la preuve
    //    matérielle de la dérive subsiste et la passe se rejouera. L'ordre
    //    inverse laisserait un profil dont plus rien ne prouve la dérive,
    //    avec un thermomètre jamais rattrapé.
    if (humiliationAfter != null) {
      await prefs.setDouble(_humiliationKey, humiliationAfter);
    }
    for (final fix in fixes) {
      await _applyAxisFix(prefs, fix);
    }

    final report = ProfileReconciliationReport(
      axes: <String, ReconciledAxis>{
        for (final fix in fixes) fix.axis.storageKey: fix.report,
      },
      humiliationBefore: humiliationBefore,
      humiliationAfter: humiliationAfter,
    );
    if (!report.isEmpty) {
      await prefs.setString(reportKey, jsonEncode(report.toJson()));
    }
    await prefs.setString(ranAtKey, DateTime.now().toUtc().toIso8601String());
    await prefs.setBool(flagKey, true);
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

  /// Ce qu'un axe hors du jouable exige : les valeurs à écrire (`null` =
  /// rien à écrire pour ce champ) et la ligne de rapport correspondante.
  static _AxisFix? _diagnoseAxis(
    SharedPreferences prefs,
    CapabilityAxis axis,
  ) {
    final base = '$_prefix${axis.storageKey}';
    final best = _readDouble(prefs, '$base$_suffixBest');
    final comfort = _readDouble(prefs, '$base$_suffixComfort');
    final ceiling = BeepEngine.kMaxBpm.toDouble();

    final bestOver = best != null && best > ceiling;
    final comfortOver = comfort != null && comfort > ceiling;
    if (!bestOver && !comfortOver) return null;

    return (
      axis: axis,
      best: bestOver ? ceiling : null,
      comfort: comfortOver ? ceiling : null,
      report: ReconciledAxis(
        bestBefore: best,
        bestAfter: bestOver ? ceiling : best,
        comfortBefore: comfort,
        comfortAfter: comfortOver ? ceiling : comfort,
        successRateBefore: _readDouble(prefs, '$base$_suffixSuccessRate'),
        successRateAfter: CapabilityService.defaultSuccessRate,
      ),
    );
  }

  /// Écrit le diagnostic. `successRate` en premier, puis les valeurs hors
  /// du jouable : ce sont elles qui prouvent la dérive, donc les dernières
  /// à disparaître (cf. l'ordre d'écriture de [applyTo]).
  static Future<void> _applyAxisFix(
    SharedPreferences prefs,
    _AxisFix fix,
  ) async {
    final base = '$_prefix${fix.axis.storageKey}';
    await prefs.setDouble(
      '$base$_suffixSuccessRate',
      CapabilityService.defaultSuccessRate,
    );
    if (fix.best != null) {
      await prefs.setDouble('$base$_suffixBest', fix.best!);
    }
    if (fix.comfort != null) {
      await prefs.setDouble('$base$_suffixComfort', fix.comfort!);
    }
  }

  /// Lecture tolérante d'un réel persisté.
  ///
  /// [SharedPreferences.getDouble] fait un **cast direct** sur la valeur en
  /// cache : une clé écrite avec un autre type (migration ratée, payload
  /// d'import fabriqué, préférences corrompues) y jette un `TypeError`. Au
  /// deuxième appel de `main()`, c'est un crash au lancement. Une valeur
  /// illisible vaut donc « absente » : l'axe est laissé tel quel et le
  /// reste du profil est réconcilié quand même. Un entier est accepté —
  /// c'est bien un nombre, seul son type de stockage diffère.
  static double? _readDouble(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    return raw is num ? raw.toDouble() : null;
  }

  /// Idem pour le drapeau : un type inattendu vaut « la passe n'a pas
  /// tourné », donc elle tourne et réécrit la clé proprement.
  static bool _readBool(SharedPreferences prefs, String key) =>
      prefs.get(key) == true;
}

/// Le diagnostic d'un axe : quoi écrire, et quoi en dire.
typedef _AxisFix = ({
  CapabilityAxis axis,
  double? best,
  double? comfort,
  ReconciledAxis report,
});
