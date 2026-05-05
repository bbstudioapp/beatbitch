import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:path_provider/path_provider.dart';

import '../models/session.dart';
import 'locale_service.dart';

/// Persiste les sessions sauvegardées par l'utilisateur (en général issues
/// de séances Carrière qu'on rejoue ensuite comme scénario) dans le
/// répertoire Documents de l'app, sous-dossier `saved_sessions/`.
///
/// Ces fichiers respectent exactement le même schéma que ceux d'`assets/sessions/`
/// → relus par `Session.fromJson` sans branche spéciale.
class SavedSessionsRepository {
  static const String _subdir = 'saved_sessions';

  Future<Directory> _ensureDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_subdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _filename(String id) => '$id.json';

  /// Sauve la session sous l'id donné (qui doit être unique).
  /// Retourne la session telle qu'elle sera relue (l'id et le nom passés
  /// remplacent ceux de la session source).
  Future<Session> save({
    required Session source,
    required String id,
    required String name,
  }) async {
    final dir = await _ensureDir();
    final saved = Session(
      id: id,
      name: name,
      description: source.description,
      durationSeconds: source.durationSeconds,
      defaultMode: source.defaultMode,
      steps: source.steps,
      intro: source.intro,
      // On ré-affirme la lang : si la source l'a, on la garde, sinon on
      // marque la sauvegarde avec la locale active au moment du save.
      lang: source.lang.isNotEmpty
          ? source.lang
          : LocaleService.instance.languageCode,
    );
    final file = File('${dir.path}/${_filename(id)}');
    await file.writeAsString(json.encode(saved.toJson()));
    return saved;
  }

  /// Si `locale` est fourni, on filtre les sessions sauvegardées sur ce code
  /// langue. Par défaut, on retourne tout (l'utilisateur peut avoir des
  /// sessions sauvegardées dans plusieurs langues).
  Future<List<Session>> loadAll({Locale? locale}) async {
    final dir = await _ensureDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final sessions = <Session>[];
    for (final f in files) {
      try {
        final raw = await f.readAsString();
        sessions.add(Session.fromJson(json.decode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Fichier corrompu : on ignore silencieusement.
      }
    }
    final filtered = locale == null
        ? sessions
        : sessions.where((s) => s.lang == locale.languageCode).toList();
    filtered
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  Future<void> delete(String id) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/${_filename(id)}');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Génère un id unique basé sur le timestamp courant. Suffisant pour un
  /// mono-utilisateur sans risque de collision.
  String newId() => 'saved_${DateTime.now().millisecondsSinceEpoch}';
}
