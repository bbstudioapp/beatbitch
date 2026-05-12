import 'capability_axis.dart';
import 'capability_service.dart';

/// Payload « classement online » du profil de capacités (§10 / §12 de la spec).
///
/// **On fige juste la forme des données** — rien n'est envoyé : le classement
/// online lui-même est dans le backlog. Cette classe est le contrat de
/// sérialisation qu'un futur uploader consommera (et qu'un backend peut déjà
/// modéliser). Elle se construit depuis un [CapabilityProfile] déjà chargé
/// (cf. `CapabilityService.snapshotProfile`) — pas de lecture
/// `shared_preferences` ici.
///
/// Le `comfort` (cible adaptative) **n'est pas** exposé : c'est le bouton de
/// difficulté du générateur, pas un trophée. Seul le `best` (record propre,
/// monotone) part au classement. Les catégories sont les axes eux-mêmes —
/// « bien plus parlantes que le score de réputation global ».
class CapabilityLeaderboardPayload {
  /// Version du schéma de ce payload. À incrémenter si on change la forme des
  /// entrées (ajout/retrait de champ, renommage de clé) — un backend peut s'y
  /// fier pour router sa désérialisation.
  static const int currentSchemaVersion = 1;

  final int schemaVersion;

  /// Niveau de carrière au moment de la capture (contexte de comparaison —
  /// un `best` posé au niveau 4 ≠ un `best` posé au niveau 20).
  final int careerLevel;

  /// Horodatage de la capture (epoch ms, UTC).
  final int generatedAtMs;

  /// Une entrée par axe portant des données (`best != null`). Ordre = ordre
  /// d'affichage canonique (`CapabilityAxis.displayOrder`).
  final List<CapabilityLeaderboardAxisEntry> axes;

  const CapabilityLeaderboardPayload({
    required this.schemaVersion,
    required this.careerLevel,
    required this.generatedAtMs,
    required this.axes,
  });

  /// Construit le payload depuis un profil déjà chargé. [now] est injectable
  /// pour les tests (sinon `DateTime.now()`).
  factory CapabilityLeaderboardPayload.fromProfile(
    CapabilityProfile profile, {
    required int careerLevel,
    DateTime? now,
  }) {
    final entries = <CapabilityLeaderboardAxisEntry>[];
    for (final axis in CapabilityAxis.displayOrder) {
      final best = profile.bestOf(axis);
      if (best == null) continue;
      entries.add(CapabilityLeaderboardAxisEntry(
        key: axis.storageKey,
        best: best,
        kind: axis.recordKind,
        unit: axis.unit,
        pilotant: axis.pilotant,
      ));
    }
    return CapabilityLeaderboardPayload(
      schemaVersion: currentSchemaVersion,
      careerLevel: careerLevel,
      generatedAtMs: (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
      axes: entries,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'career_level': careerLevel,
        'generated_at_ms': generatedAtMs,
        'axes': [for (final e in axes) e.toJson()],
      };

  /// `true` s'il n'y a aucune donnée à publier (profil neuf).
  bool get isEmpty => axes.isEmpty;
}

/// Une catégorie de classement = un axe du profil, avec son record (`best`),
/// son sens de record et son unité — assez pour qu'un backend formate sans
/// connaître l'enum côté app.
class CapabilityLeaderboardAxisEntry {
  /// Clé stable de l'axe (`CapabilityAxis.storageKey`, ex. `gorge.apnee_streak`).
  final String key;

  /// Record propre (jamais le `comfort`).
  final double best;

  /// Sens dans lequel `best` évolue (`maximize` / `minimize` / `accumulate`).
  final CapabilityRecordKind kind;

  /// Unité d'affichage (`seconds` / `bpm` / `depthCran` / `count`).
  final CapabilityUnit unit;

  /// `true` si le générateur pilote sur cet axe (les autres sont enregistrés
  /// seulement). Exposé pour qu'un classement puisse distinguer les axes
  /// « cœur de difficulté » des axes purement descriptifs.
  final bool pilotant;

  const CapabilityLeaderboardAxisEntry({
    required this.key,
    required this.best,
    required this.kind,
    required this.unit,
    required this.pilotant,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'best': best,
        'kind': kind.name,
        'unit': unit.name,
        'pilotant': pilotant,
      };
}
