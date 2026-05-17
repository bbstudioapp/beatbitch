import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Calcul + vérification du checksum d'intégrité d'un export diagnostic.
///
/// Volontairement isolé du reste de `diagnostic_export_service.dart` (qui
/// dépend de `package:flutter/`) pour qu'un script `dart run` standalone
/// (cf. `tools/verify_export.dart`) puisse l'importer sans charger Flutter.
///
/// **Anti-corruption uniquement**, pas une signature cryptographique :
/// l'app étant offline, aucun secret partagé n'est embarquable de façon
/// fiable, donc rien n'empêche un export modifié d'être re-haché. Sert à
/// détecter une troncature mail / copy-paste cassé / édition par mégarde.
class DiagnosticExportIntegrity {
  DiagnosticExportIntegrity._();

  /// Algorithme actuel. À bumper (et garder le support du précédent dans
  /// [verify]) si on en change un jour.
  static const String algorithm = 'sha256';

  /// Calcule le checksum sur le payload **sans** son champ `integrity`.
  /// Le caller a la responsabilité d'avoir retiré ce champ s'il est présent.
  static String compute(Map<String, dynamic> payload) {
    final canonical = canonicalJson(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Recalcule le checksum sur un payload importé et le compare au champ
  /// `integrity.value`. Renvoie `true` si tout colle. Renvoie `false` si le
  /// champ est manquant, mal formé, ou si le hash ne correspond plus.
  static bool verify(Map<String, dynamic> payload) {
    final integrity = payload['integrity'];
    if (integrity is! Map) return false;
    final expected = integrity['value'];
    if (expected is! String) return false;
    final algo = integrity['algorithm'];
    if (algo != algorithm) return false;
    final stripped = Map<String, dynamic>.from(payload)..remove('integrity');
    return compute(stripped) == expected;
  }

  /// Sérialisation canonique : clés triées récursivement, aucun espace.
  /// Reproductible quel que soit l'ordre d'insertion dans le `Map` source.
  /// Exposée publiquement pour qu'un test ou un outil puisse hasher
  /// indépendamment et comparer.
  static String canonicalJson(Object? data) {
    if (data == null) return 'null';
    if (data is Map) {
      final keys = data.keys.map((k) => k.toString()).toList()..sort();
      final buf = StringBuffer('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf
          ..write(json.encode(keys[i]))
          ..write(':')
          ..write(canonicalJson(data[keys[i]]));
      }
      buf.write('}');
      return buf.toString();
    }
    if (data is List) {
      final buf = StringBuffer('[');
      for (var i = 0; i < data.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(canonicalJson(data[i]));
      }
      buf.write(']');
      return buf.toString();
    }
    return json.encode(data);
  }
}
