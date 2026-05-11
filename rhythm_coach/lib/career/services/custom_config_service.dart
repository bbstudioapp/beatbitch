import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_session_config.dart';

/// Persiste les configurations du mode « Custom » : une config = un fichier
/// JSON dans le répertoire Documents de l'app, sous-dossier `custom_configs/`
/// (même schéma que `CustomSessionConfig.toJson`). Sur le web, bascule sur
/// `shared_preferences` (= localStorage) comme `SavedSessionsRepository` —
/// le web reste hors scope de prod mais on garde la feature testable.
///
/// La clé `custom.last_config_id` (shared_preferences) mémorise la dernière
/// config lancée pour la proposer au prochain démarrage.
class CustomConfigService {
  static const String _subdir = 'custom_configs';
  static const String _webIndexKey = 'custom_configs.index';
  static const String _webEntryKeyPrefix = 'custom_configs.entry.';
  static const String _kLastConfigId = 'custom.last_config_id';

  Future<Directory> _ensureDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_subdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _filename(String id) => '$id.json';

  String newId() => CustomSessionConfig.newId();

  /// Sauve (ou écrase) la config sous son id. Retourne la config telle quelle.
  Future<CustomSessionConfig> save(CustomSessionConfig config) async {
    final payload = json.encode(config.toJson());
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final ids =
          (prefs.getStringList(_webIndexKey) ?? const <String>[]).toList();
      if (!ids.contains(config.id)) ids.add(config.id);
      await prefs.setStringList(_webIndexKey, ids);
      await prefs.setString('$_webEntryKeyPrefix${config.id}', payload);
      return config;
    }
    final dir = await _ensureDir();
    final file = File('${dir.path}/${_filename(config.id)}');
    await file.writeAsString(payload);
    return config;
  }

  /// Toutes les configs sauvegardées, triées par nom (insensible à la casse,
  /// les sans-nom en fin de liste).
  Future<List<CustomSessionConfig>> loadAll() async {
    final configs = <CustomSessionConfig>[];
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_webIndexKey) ?? const <String>[];
      for (final id in ids) {
        final raw = prefs.getString('$_webEntryKeyPrefix$id');
        if (raw == null) continue;
        try {
          configs.add(
            CustomSessionConfig.fromJson(
                json.decode(raw) as Map<String, dynamic>),
          );
        } catch (_) {
          // Entrée corrompue : ignorée silencieusement.
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
          configs.add(
            CustomSessionConfig.fromJson(
                json.decode(raw) as Map<String, dynamic>),
          );
        } catch (_) {
          // Fichier corrompu : ignoré silencieusement.
        }
      }
    }
    configs.sort((a, b) {
      final an = a.name.trim();
      final bn = b.name.trim();
      if (an.isEmpty && bn.isEmpty) return a.id.compareTo(b.id);
      if (an.isEmpty) return 1;
      if (bn.isEmpty) return -1;
      return an.toLowerCase().compareTo(bn.toLowerCase());
    });
    return configs;
  }

  Future<CustomSessionConfig?> loadById(String id) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_webEntryKeyPrefix$id');
      if (raw == null) return null;
      try {
        return CustomSessionConfig.fromJson(
            json.decode(raw) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }
    final dir = await _ensureDir();
    final file = File('${dir.path}/${_filename(id)}');
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return CustomSessionConfig.fromJson(
          json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final ids =
          (prefs.getStringList(_webIndexKey) ?? const <String>[]).toList();
      ids.remove(id);
      await prefs.setStringList(_webIndexKey, ids);
      await prefs.remove('$_webEntryKeyPrefix$id');
    } else {
      final dir = await _ensureDir();
      final file = File('${dir.path}/${_filename(id)}');
      if (await file.exists()) await file.delete();
    }
    // Si on supprime la dernière config utilisée, on nettoie aussi le pointeur.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kLastConfigId) == id) {
      await prefs.remove(_kLastConfigId);
    }
  }

  Future<void> setLastUsed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastConfigId, id);
  }

  Future<String?> getLastUsedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastConfigId);
  }

  /// Charge la dernière config utilisée si elle existe encore, sinon null.
  Future<CustomSessionConfig?> loadLastUsed() async {
    final id = await getLastUsedId();
    if (id == null) return null;
    return loadById(id);
  }

  /// Efface toutes les configs + le pointeur de dernière utilisée. Appelé par
  /// le bouton « tout remettre à zéro » du ProfileScreen.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastConfigId);
    if (kIsWeb) {
      final ids = prefs.getStringList(_webIndexKey) ?? const <String>[];
      for (final id in ids) {
        await prefs.remove('$_webEntryKeyPrefix$id');
      }
      await prefs.remove(_webIndexKey);
      return;
    }
    final dir = await _ensureDir();
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.json')) {
          await e.delete();
        }
      }
    }
  }
}
