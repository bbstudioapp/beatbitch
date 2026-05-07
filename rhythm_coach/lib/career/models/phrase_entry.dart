import 'dart:math';

import '../../models/session.dart';
import '../../models/session_step.dart';

/// Entrée d'une banque de phrases. Stocke un texte + contraintes optionnelles
/// d'apparition. Permet d'écrire dans les JSON soit une string simple
/// (« phrase ») soit un objet `{ "text": "...", "min_depth": "...", ... }`
/// pour réserver la phrase à un contexte précis.
///
/// Filtres supportés :
/// - [minDepth] / [maxDepth] : fenêtre de profondeur. Une phrase
///   « respire par le nez » peut être bornée à `max_depth: "mid"` pour
///   ne pas tomber en hold throat/full où respirer est impossible.
/// - [minBpm] / [maxBpm] : fenêtre de BPM.
/// - [requiresUnlock] : ne sort que si toutes ces clés d'unlock sont
///   acquises pour la session courante (cf. `UnlockKey.serialized`).
class PhraseEntry {
  final String text;
  final Position? minDepth;
  final Position? maxDepth;
  final int? minBpm;
  final int? maxBpm;
  final List<String> requiresUnlock;

  const PhraseEntry({
    required this.text,
    this.minDepth,
    this.maxDepth,
    this.minBpm,
    this.maxBpm,
    this.requiresUnlock = const [],
  });

  bool get hasNoConstraints =>
      minDepth == null &&
      maxDepth == null &&
      minBpm == null &&
      maxBpm == null &&
      requiresUnlock.isEmpty;

  /// Vrai si cette phrase peut sortir dans le contexte donné. Un paramètre
  /// `null` désactive le check correspondant (« on ne sait pas, on accepte »).
  bool matches({
    Position? depth,
    int? bpm,
    Set<String> unlockedKeys = const {},
  }) {
    if (minDepth != null) {
      if (depth == null || depth.index < minDepth!.index) return false;
    }
    if (maxDepth != null) {
      if (depth != null && depth.index > maxDepth!.index) return false;
    }
    if (minBpm != null) {
      if (bpm == null || bpm < minBpm!) return false;
    }
    if (maxBpm != null) {
      if (bpm != null && bpm > maxBpm!) return false;
    }
    for (final k in requiresUnlock) {
      if (!unlockedKeys.contains(k)) return false;
    }
    return true;
  }

  /// Désérialise depuis un JSON brut. Accepte :
  /// - une string simple → entrée sans contraintes
  /// - un objet `{ text, min_depth?, max_depth?, min_bpm?, max_bpm?,
  ///   requires_unlock? }` (la clé `requires_unlock` accepte string ou
  ///   liste de strings).
  ///
  /// Retourne null si le brut est inutilisable (texte vide ou type
  /// inattendu).
  static PhraseEntry? fromJson(dynamic raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return PhraseEntry(text: trimmed);
    }
    if (raw is Map<String, dynamic>) {
      final text = (raw['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) return null;

      final unlockRaw = raw['requires_unlock'];
      final requiresUnlock = <String>[];
      if (unlockRaw is String && unlockRaw.isNotEmpty) {
        requiresUnlock.add(unlockRaw);
      } else if (unlockRaw is List) {
        for (final v in unlockRaw) {
          if (v is String && v.isNotEmpty) requiresUnlock.add(v);
        }
      }

      return PhraseEntry(
        text: text,
        minDepth: Position.fromString(raw['min_depth'] as String?),
        maxDepth: Position.fromString(raw['max_depth'] as String?),
        minBpm: (raw['min_bpm'] as num?)?.toInt(),
        maxBpm: (raw['max_bpm'] as num?)?.toInt(),
        requiresUnlock: requiresUnlock,
      );
    }
    return null;
  }

  /// Désérialise une liste mixte (strings et objets) en `List<PhraseEntry>`,
  /// en filtrant les entrées invalides. Retourne une liste vide si [raw]
  /// n'est pas une liste.
  static List<PhraseEntry> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final out = <PhraseEntry>[];
    for (final item in raw) {
      final entry = PhraseEntry.fromJson(item);
      if (entry != null) out.add(entry);
    }
    return out;
  }
}

/// Tire une phrase d'un pool en filtrant par contexte. Si aucune phrase
/// filtrée ne matche, retombe sur les phrases sans contraintes du pool ;
/// si même ce fallback est vide, retourne null.
///
/// Si [context] est null, aucun filtre n'est appliqué : tirage uniforme
/// dans tout le pool. Permet aux call sites qui n'ont pas de contexte
/// (intros, congrats…) de continuer à tirer sans changer leur appel.
String? pickPhraseEntry(
  List<PhraseEntry> entries,
  Random rng, {
  PhraseContext? context,
}) {
  if (entries.isEmpty) return null;
  if (context == null) {
    return entries[rng.nextInt(entries.length)].text;
  }
  final matching = entries.where((e) => e.matches(
        depth: context.depth,
        bpm: context.bpm,
        unlockedKeys: context.unlockedKeys,
      )).toList();
  if (matching.isNotEmpty) {
    return matching[rng.nextInt(matching.length)].text;
  }
  // Fallback : phrases sans contraintes uniquement. On ne tire pas dans
  // tout le pool sinon une phrase contrainte qui ne matchait pas le
  // contexte tomberait quand même (« nez collé » sur un hold mid…).
  final loose = entries.where((e) => e.hasNoConstraints).toList();
  if (loose.isEmpty) return null;
  return loose[rng.nextInt(loose.length)].text;
}

/// Contexte de tirage d'une phrase. Tous les champs optionnels.
class PhraseContext {
  /// Profondeur courante du step (typiquement `to ?? from`).
  final Position? depth;

  /// BPM courant du step (rhythm/lick/biffle/hand).
  final int? bpm;

  /// Mode courant. Pas filtré par PhraseEntry pour l'instant (la banque
  /// indexe déjà par mode), mais transmis pour usage futur.
  final SessionMode? mode;

  /// Compétences acquises pour la session courante (au format
  /// `UnlockKey.serialized`). Set vide = pas de filtre par unlock.
  final Set<String> unlockedKeys;

  const PhraseContext({
    this.depth,
    this.bpm,
    this.mode,
    this.unlockedKeys = const {},
  });
}
