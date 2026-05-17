import 'dart:convert';
import 'dart:io';

import 'package:beat_bitch/services/diagnostic_export_integrity.dart';

/// Vérifie l'intégrité d'un export diagnostic BeatBitch (cf.
/// `DiagnosticExportService`).
///
/// Usage : `dart run tools/verify_export.dart <path>` depuis `rhythm_coach/`.
///
/// Affiche un résumé lisible (chemin, taille, schema/app/platform/locale,
/// algo + valeur du hash) puis le verdict. Codes de sortie :
/// - `0` : intégrité OK.
/// - `1` : intégrité KO (champ absent, algo inconnu, hash recalculé différent).
/// - `2` : erreur d'usage (arguments invalides, fichier introuvable, JSON
///   syntaxiquement cassé) — distinct du KO pour qu'un wrapper shell puisse
///   faire la différence entre « le check a tourné et il dit non » et « le
///   check n'a jamais pu tourner ».
///
/// **Anti-corruption uniquement** : un OK ne prouve pas que le fichier sort
/// de l'app — l'app étant offline, aucun secret n'est embarquable de façon
/// fiable, donc un attaquant déterminé peut modifier puis recalculer le hash.
/// Cf. le docstring de `DiagnosticExportIntegrity` pour les détails.
Future<void> main(List<String> args) async {
  if (args.length != 1 || args.first == '--help' || args.first == '-h') {
    stderr.writeln(
        'Usage: dart run tools/verify_export.dart <path-to-export.json>');
    exit(2);
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('Fichier introuvable : ${file.path}');
    exit(2);
  }

  final raw = file.readAsStringSync();
  Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('JSON invalide : racine attendue Map, reçu '
          '${decoded.runtimeType}.');
      exit(2);
    }
    payload = decoded;
  } on FormatException catch (e) {
    stderr.writeln('JSON invalide : ${e.message}');
    exit(2);
  }

  stdout
    ..writeln('File         : ${file.path}')
    ..writeln('Size         : ${file.lengthSync()} bytes')
    ..writeln('schemaVersion: ${payload['schemaVersion']}')
    ..writeln('appVersion   : ${payload['appVersion']}')
    ..writeln('platform     : ${payload['platform']}')
    ..writeln('locale       : ${payload['locale']}')
    ..writeln('exportedAt   : ${payload['exportedAt']}');

  final integrity = payload['integrity'];
  if (integrity is! Map) {
    stderr.writeln('');
    stderr.writeln('Integrity   : MISSING (no `integrity` field at root).');
    exit(1);
  }
  stdout
    ..writeln('Algorithm    : ${integrity['algorithm']}')
    ..writeln('Hash (file)  : ${integrity['value']}');

  final ok = DiagnosticExportIntegrity.verify(payload);
  stdout.writeln('');
  if (ok) {
    stdout.writeln('Integrity    : OK');
    exit(0);
  }

  final recomputed = DiagnosticExportIntegrity.compute(
    Map<String, dynamic>.from(payload)..remove('integrity'),
  );
  stderr
    ..writeln('Integrity    : FAILED')
    ..writeln('Hash (recalc): $recomputed')
    ..writeln('')
    ..writeln('Causes possibles :')
    ..writeln(' - le fichier a été modifié après l\'export ;')
    ..writeln(' - le transit (mail / messagerie) a tronqué le contenu ;')
    ..writeln(' - l\'algorithme du champ `integrity.algorithm` n\'est pas '
        '`${DiagnosticExportIntegrity.algorithm}` (export plus récent ?).');
  exit(1);
}
