import 'dart:convert';
import 'dart:io';

/// Parse tous les fichiers `.json` sous `assets/` pour s'assurer qu'aucun
/// n'est syntaxiquement corrompu. Sortie code 1 si une parse échoue,
/// avec la liste détaillée des fichiers fautifs.
///
/// Usage : `dart run tools/validate_assets.dart` depuis `rhythm_coach/`.
void main() {
  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) {
    stderr.writeln('assets/ directory not found — run from rhythm_coach/.');
    exit(2);
  }

  final errors = <String>[];
  var checked = 0;

  for (final entity in assetsDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    checked++;
    try {
      jsonDecode(entity.readAsStringSync());
    } catch (e) {
      errors.add('${entity.path}: $e');
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('JSON parse errors (${errors.length} / $checked) :');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exit(1);
  }

  stdout.writeln('All $checked JSON asset files parsed OK.');
}
