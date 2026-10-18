// Mesures A (tss2-037) : instant du FAIL balayé ; témoin normal + FAIL.
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beat_bitch/services/capability_axis.dart';

import 'capability_use_me_bench.dart';

String _c(BenchOutcome o, CapabilityAxis a) {
  final b = o.before.stateOf(a), x = o.after.stateOf(a);
  String f(double? v) => v == null ? '—' : v.toStringAsFixed(0);
  return '${f(b.comfort)}→${f(x.comfort)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mesures A : balayage du FAIL, témoin normal + FAIL', () async {
    for (final useMe in [true, false]) {
      print(
          '=== ${useMe ? "USE-ME 5 min + FAIL" : "TÉMOIN normal 5 min + FAIL"} : comfort avant→après');
      for (final frac in [0.05, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 0.98]) {
        SharedPreferences.setMockInitialValues(benchPrefsSeed());
        final o =
            await benchSession(useMe: useMe, useMeSec: 300, failFrac: frac);
        print('FAIL@${(frac * 100).round()}% '
            'motion ${_c(o, CapabilityAxis.rhythmMotionStreak)} '
            'apnée ${_c(o, CapabilityAxis.gorgeApneeStreak)} '
            'hold.throat ${_c(o, CapabilityAxis.holdThroatStreak)} '
            'bpm.throat ${_c(o, CapabilityAxis.rhythmBpmCeilThroat)} '
            'bpm.full ${_c(o, CapabilityAxis.rhythmBpmCeilFull)} '
            '| best throat ${o.after.bestOf(CapabilityAxis.rhythmBpmCeilThroat)?.toStringAsFixed(0)}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
