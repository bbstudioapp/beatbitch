import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les seuls `from == to` que le contenu écrit à la main garde encore : le
/// moteur y relève `from` par un tirage à plusieurs candidats, et figer ce
/// tirage changerait ce que la joueuse entend (décision de Manu, 21/08 : A).
const _assumes = {
  'assets/punishments.json » punishments/5/steps/0',
  'assets/punishments_en.json » punishments/5/steps/0',
  'assets/punishments_de.json » punishments/5/steps/0',
  'assets/punishments_es.json » punishments/5/steps/0',
  'assets/sessions/session_advanced_demo_ps1.json » steps/8',
};

void _walk(
  Object? node,
  String path,
  void Function(Map<String, dynamic> step, String path) onStep,
) {
  if (node is Map<String, dynamic>) {
    if (node.containsKey('from') || node.containsKey('to')) onStep(node, path);
    for (final entry in node.entries) {
      _walk(
          entry.value, path.isEmpty ? entry.key : '$path/${entry.key}', onStep);
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      _walk(node[i], '$path/$i', onStep);
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

    final found = <String>{};
    for (final path in files) {
      final content = jsonDecode(File(path).readAsStringSync());
      // Un step sans `mode` hérite de celui du document qui le porte.
      final defaultMode =
          content is Map<String, dynamic> ? content['mode'] : null;
      _walk(content, '', (step, at) {
        final from = step['from'];
        if (from == null || from != step['to']) return;
        final mode = step['mode'] ?? defaultMode;
        if (mode != 'rhythm' && mode != 'lick') return;
        found.add('$path » $at');
      });
    }

    expect(found, _assumes);
  });
}
