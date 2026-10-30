import 'dart:io';

import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final readmeFiles =
      RegExp(r'^\|[^|]+\|\s*`(finish_coach_[^`]+\.mp3)`\s*\|', multiLine: true)
          .allMatches(File('assets/audio/music/README.md').readAsStringSync())
          .map((m) => 'audio/music/${m.group(1)}')
          .toSet();
  final slugs = CoachCatalog.defaults.map((c) => c.slug).toSet();

  test('le tableau du README est lu', () {
    expect(readmeFiles, hasLength(CoachCatalog.defaults.length));
  });

  test('chaque coach du catalogue a son morceau de fin', () {
    expect(AmbienceEngine.coachFinishTracks.keys.toSet(), slugs);
  });

  for (final MapEntry(key: slug, value: track)
      in AmbienceEngine.coachFinishTracks.entries) {
    test('$slug : coach réelle et fichier du tableau du README', () {
      expect(slugs, contains(slug));
      expect(readmeFiles, contains(track.asset));
      final coach = CoachCatalog.defaults.firstWhere((c) => c.slug == slug);
      expect(track.asset, 'audio/music/finish_${coach.id}.mp3');
    });
  }
}
