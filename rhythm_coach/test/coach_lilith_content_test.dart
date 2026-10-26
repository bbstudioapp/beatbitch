import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/coach_loader.dart';

const _langs = ['fr', 'en', 'de', 'es'];

Map<String, dynamic> _pack(String lang) =>
    jsonDecode(File('assets/career/coaches/${CoachCatalog.lilithId}_$lang.json')
        .readAsStringSync()) as Map<String, dynamic>;

/// Toutes les chaînes d'un nœud JSON, avec leur chemin.
Iterable<(String, String)> _texts(Object? node, String path) sync* {
  if (node is String) {
    yield (path, node);
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      yield* _texts(node[i], '$path[$i]');
    }
  } else if (node is Map) {
    for (final e in node.entries) {
      if (e.key == 'min_depth' || e.key == 'max_depth') continue;
      yield* _texts(e.value, '$path.${e.key}');
    }
  }
}

/// Le shape d'un nœud : clés et longueurs de listes, sans le texte.
Object? _shape(Object? node) => switch (node) {
      final Map<dynamic, dynamic> m => {
          for (final e in m.entries)
            if (e.key != 'lang' && e.key != 'title' && e.key != 'publicBio')
              e.key: _shape(e.value)
        },
      final List<dynamic> l => l.map(_shape).toList(),
      _ => null,
    };

final _holdVerbs = <String, RegExp>{
  'fr': RegExp(
      r"\b(tiens|tenir|tenez|maintiens|maintenir)\b(?! (le rythme|la cadence|le tempo))",
      caseSensitive: false,
      unicode: true),
  'en': RegExp(r'\bhold\b(?! the (rhythm|tempo|pace))', caseSensitive: false),
  'de': RegExp(r'\b(halt|halte|halten)\b(?! (den Takt|den Rhythmus|das Tempo))',
      caseSensitive: false, unicode: true),
  'es': RegExp(r'(?<![\p{L}])(mant[eé]n\w*|mantener)',
      caseSensitive: false, unicode: true),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les quatre langues ont exactement la même forme que le français', () {
    final reference = _shape(_pack('fr'));
    for (final lang in _langs.skip(1)) {
      expect(_shape(_pack(lang)), reference, reason: lang);
    }
  });

  test('une phrase de branche pour chacune des cinq spécialisations', () {
    for (final lang in _langs) {
      final branches = (_pack(lang)['branchPhrases'] as Map).keys.toSet();
      expect(branches, SpecializationBranch.values.map((b) => b.name).toSet(),
          reason: lang);
    }
  });

  test('« tiens / hold / halten / mantén » n\'apparaît que dans les tenues',
      () {
    for (final lang in _langs) {
      final pack = _pack(lang);
      final verb = _holdVerbs[lang]!;
      final outside = [
        for (final (path, text) in _texts(pack, lang))
          if (!path.startsWith('$lang.phrases.hold.') && verb.hasMatch(text))
            '$path : $text'
      ];
      expect(outside, isEmpty);
      final inside = [
        for (final (path, text) in _texts(pack, lang))
          if (path.startsWith('$lang.phrases.hold.') && verb.hasMatch(text))
            text
      ];
      expect(inside, isNotEmpty, reason: '$lang : la règle doit mordre');
    }
  });

  for (final lang in _langs) {
    test('chargée en $lang avec son contenu et sa fenêtre', () async {
      final loaded = await CoachLoader().load(locale: Locale(lang));
      final lilith = loaded.singleWhere((c) => c.id == CoachCatalog.lilithId);
      expect(lilith.title, _pack(lang)['title']);
      expect(lilith.isPrincipal, isFalse);
      expect(lilith.availability, isNotNull);
      expect(lilith.phrases.intros, isNotEmpty);
      expect(lilith.phrases.byMode, isNotEmpty);
      expect(lilith.voicePreset.voiceName, 'fr-fr-x-vlf-local');
    });
  }
}
