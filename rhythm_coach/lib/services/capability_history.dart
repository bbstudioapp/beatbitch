import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Valeurs d'un axe à la fin d'une séance, telles que persistées par
/// `CapabilityService.commit`.
class CapabilityHistoryAxis {
  final double best;
  final double comfort;
  final double successRate;

  const CapabilityHistoryAxis({
    required this.best,
    required this.comfort,
    required this.successRate,
  });
}

/// Une entrée par séance qui met à jour le profil : l'état de **tous** les
/// axes porteurs de données, après la mise à jour.
class CapabilityHistoryEntry {
  final DateTime at;
  final int sessionIndex;

  /// Clé = `CapabilityAxis.storageKey`. Gardée en chaîne : un axe retiré ou
  /// ajouté plus tard ne rend pas l'historique illisible.
  final Map<String, CapabilityHistoryAxis> axes;

  const CapabilityHistoryEntry({
    required this.at,
    required this.sessionIndex,
    required this.axes,
  });
}

/// Historique borné du profil de capacités (`shared_preferences`, clé
/// [prefsKey]), pour un futur écran de progression. Aucun écran ne le lit
/// aujourd'hui.
///
/// Format versionné :
/// `{"v":1,"entries":[{"t":<ms UTC>,"i":<index séance>,"a":{"<axe>":[best,comfort,successRate]}}]}`
/// Tolérant : tout ce qui est illisible est ignoré, jamais propagé.
class CapabilityHistory {
  CapabilityHistory._();

  static const String prefsKey = 'cap.history';
  static const int schemaVersion = 1;
  static const int maxEntries = 1000;

  /// Historique persisté, de la plus ancienne à la plus récente entrée.
  /// Vide si la clé est absente, d'un autre type ou illisible.
  static List<CapabilityHistoryEntry> read(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(prefsKey);
      if (raw == null) return const <CapabilityHistoryEntry>[];
      return fromJson(json.decode(raw));
    } catch (_) {
      return const <CapabilityHistoryEntry>[];
    }
  }

  /// Ajoute [entry] en fin d'historique et ne garde que les [maxEntries]
  /// dernières. Un historique illisible repart de zéro.
  static Future<void> append(
    SharedPreferences prefs,
    CapabilityHistoryEntry entry,
  ) async {
    final all = [...read(prefs), entry];
    final kept =
        all.length > maxEntries ? all.sublist(all.length - maxEntries) : all;
    await prefs.setString(prefsKey, json.encode(toJson(kept)));
  }

  /// Relit un historique déjà décodé (stockage ou section d'export). Les
  /// entrées et axes abîmés sont ignorés ; une version inconnue donne une liste
  /// vide.
  static List<CapabilityHistoryEntry> fromJson(Object? decoded) {
    if (decoded is! Map || decoded['v'] != schemaVersion) {
      return const <CapabilityHistoryEntry>[];
    }
    final entries = decoded['entries'];
    if (entries is! List) return const <CapabilityHistoryEntry>[];
    final out = <CapabilityHistoryEntry>[];
    for (final e in entries) {
      final entry = _entryFromJson(e);
      if (entry != null) out.add(entry);
    }
    return out.length > maxEntries ? out.sublist(out.length - maxEntries) : out;
  }

  static Map<String, dynamic> toJson(List<CapabilityHistoryEntry> entries) =>
      <String, dynamic>{
        'v': schemaVersion,
        'entries': [
          for (final e in entries)
            <String, dynamic>{
              't': e.at.millisecondsSinceEpoch,
              'i': e.sessionIndex,
              'a': {
                for (final a in e.axes.entries)
                  a.key: [a.value.best, a.value.comfort, a.value.successRate],
              },
            },
        ],
      };

  static CapabilityHistoryEntry? _entryFromJson(Object? e) {
    if (e is! Map) return null;
    final t = e['t'];
    final i = e['i'];
    final a = e['a'];
    if (t is! int || i is! int || a is! Map) return null;
    final axes = <String, CapabilityHistoryAxis>{};
    for (final entry in a.entries) {
      final v = entry.value;
      if (entry.key is! String ||
          v is! List ||
          v.length != 3 ||
          v.any((x) => x is! num)) {
        continue;
      }
      axes[entry.key as String] = CapabilityHistoryAxis(
        best: (v[0] as num).toDouble(),
        comfort: (v[1] as num).toDouble(),
        successRate: (v[2] as num).toDouble(),
      );
    }
    return CapabilityHistoryEntry(
      at: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
      sessionIndex: i,
      axes: axes,
    );
  }
}
