import 'package:beat_bitch/career/services/debug_settings_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `getShowTrajectoryDots` est le seul toggle de `DebugSettingsService` dont
/// le défaut n'est pas un littéral fixe mais `?? kDebugMode` — rien ne
/// verrouillait ce comportement, à la différence des autres toggles du
/// service (cf. `scripted_breaks_enabled_test.dart`).
void main() {
  group('Défaut « afficher les mini-points de trajectoire »', () {
    test('profil vierge → suit kDebugMode', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DebugSettingsService().getShowTrajectoryDots(), kDebugMode);
    });

    test('une valeur explicite prime sur kDebugMode', () async {
      SharedPreferences.setMockInitialValues(
          {'debug.show_trajectory_dots': !kDebugMode});
      expect(await DebugSettingsService().getShowTrajectoryDots(), !kDebugMode);
    });

    test('setter écrit bien sous la clé `debug.`', () async {
      SharedPreferences.setMockInitialValues({});
      await DebugSettingsService().setShowTrajectoryDots(!kDebugMode);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('debug.show_trajectory_dots'), !kDebugMode);
    });
  });
}
