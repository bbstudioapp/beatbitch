import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les seuls `from == to` que le contenu écrit à la main garde encore : le
/// moteur y relève `from` par un tirage à plusieurs candidats, et figer ce
/// tirage changerait ce que la joueuse entend (décision de Manu, 21/08 : A).
const _assumes = {
  'assets/punishments.json#0',
  'assets/punishments_en.json#0',
  'assets/punishments_de.json#0',
  'assets/punishments_es.json#0',
  'assets/sessions/session_advanced_demo_ps1.json#210',
};

void _walk(
    Object? node, String file, void Function(Map<String, dynamic>) onStep) {
  if (node is Map<String, dynamic>) {
    if (node.containsKey('from') || node.containsKey('to')) onStep(node);
    for (final v in node.values) {
      _walk(v, file, onStep);
    }
  } else if (node is List) {
    for (final v in node) {
      _walk(v, file, onStep);
    }
  }
}

void main() {
  test('le contenu écrit à la main ne pose plus de from == to ambigu', () {
    final files = [
      'assets/career/milestones.json',
      'assets/punishments.json',
      'assets/punishments_en.json',
      'assets/punishments_de.json',
      'assets/punishments_es.json',
      ...Directory('assets/sessions')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.json')),
    ];

    final found = <String>[];
    for (final path in files) {
      final content = jsonDecode(File(path).readAsStringSync());
      _walk(content, path, (step) {
        final from = step['from'];
        final to = step['to'];
        final mode = step['mode'];
        if (from == null || from != to) return;
        if (mode != null && mode != 'rhythm' && mode != 'lick') return;
        found.add('$path#${step['id'] ?? step['time']}');
      });
    }

    expect(found.toSet(), _assumes);
  });
}
