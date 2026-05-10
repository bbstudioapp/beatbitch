import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';
import 'locale_service.dart';

/// Persiste les sessions sauvegardées par l'utilisateur (en général issues
/// de séances Carrière qu'on rejoue ensuite comme scénario) dans le
/// répertoire Documents de l'app, sous-dossier `saved_sessions/`.
///
/// Ces fichiers respectent exactement le même schéma que ceux d'`assets/sessions/`
/// → relus par `Session.fromJson` sans branche spéciale.
///
/// Sur le web, `path_provider` n'a pas d'implémentation : on bascule sur
/// `shared_preferences` (= localStorage côté navigateur). Index des ids
/// dans `_webIndexKey`, payload JSON dans `_webEntryKeyPrefix + id`. Web
/// reste hors scope de prod, mais on garde la feature fonctionnelle pour
/// les tests UI au lieu d'afficher l'erreur `MissingPluginException`.
class SavedSessionsRepository {
  static const String _subdir = 'saved_sessions';
  static const String _webIndexKey = 'saved_sessions.index';
  static const String _webEntryKeyPrefix = 'saved_sessions.entry.';

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
      noStats: source.noStats,
    );
    final payload = json.encode(saved.toJson());
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(_webIndexKey) ?? const <String>[]).toList();
      if (!ids.contains(id)) ids.add(id);
      await prefs.setStringList(_webIndexKey, ids);
      await prefs.setString('$_webEntryKeyPrefix$id', payload);
      return saved;
    }
    final dir = await _ensureDir();
    final file = File('${dir.path}/${_filename(id)}');
    await file.writeAsString(payload);
    return saved;
  }

  /// Si `locale` est fourni, on filtre les sessions sauvegardées sur ce code
  /// langue. Par défaut, on retourne tout (l'utilisateur peut avoir des
  /// sessions sauvegardées dans plusieurs langues).
  Future<List<Session>> loadAll({Locale? locale}) async {
    final sessions = <Session>[];
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_webIndexKey) ?? const <String>[];
      for (final id in ids) {
        final raw = prefs.getString('$_webEntryKeyPrefix$id');
        if (raw == null) continue;
        try {
          sessions
              .add(Session.fromJson(json.decode(raw) as Map<String, dynamic>));
        } catch (_) {
          // Entrée corrompue : on ignore silencieusement.
        }
      }
    } else {
      final dir = await _ensureDir();
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();
      for (final f in files) {
        try {
          final raw = await f.readAsString();
          sessions
              .add(Session.fromJson(json.decode(raw) as Map<String, dynamic>));
        } catch (_) {
          // Fichier corrompu : on ignore silencieusement.
        }
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
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final ids =
          (prefs.getStringList(_webIndexKey) ?? const <String>[]).toList();
      ids.remove(id);
      await prefs.setStringList(_webIndexKey, ids);
      await prefs.remove('$_webEntryKeyPrefix$id');
      return;
    }
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
