import 'package:beat_bitch/services/music_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration wall;
  late MusicClock clock;

  Duration ms(int v) => Duration(milliseconds: v);
  void advance(int v) => wall += ms(v);

  setUp(() {
    wall = Duration.zero;
    clock = MusicClock(now: () => wall);
  });

  test('la position reste à zéro tant que le lecteur n\'a rien rapporté', () {
    clock.start();
    advance(1300);
    expect(clock.position, Duration.zero);
    expect(clock.isSynced, isFalse);
  });

  test('le premier rapport pose la position, l\'horloge l\'extrapole ensuite',
      () {
    clock.start();
    advance(1300);
    clock.report(ms(40));
    expect(clock.isSynced, isTrue);
    expect(clock.position, ms(40));

    advance(100);
    expect(clock.position, ms(140));
  });

  test('chaque rapport ré-ancre : l\'écart ne s\'accumule pas', () {
    clock.start();
    clock.report(ms(10000));
    advance(100);
    expect(clock.position, ms(10100));

    clock.report(ms(10080));
    expect(clock.position, ms(10080));
    advance(50);
    expect(clock.position, ms(10130));
  });

  test('la pause fige la position, les rapports tardifs sont ignorés', () {
    clock.start();
    clock.report(ms(5000));
    advance(200);
    clock.pause();
    expect(clock.position, ms(5200));

    advance(3000);
    clock.report(ms(9999));
    expect(clock.position, ms(5200));
  });

  test('la reprise repart de la position figée', () {
    clock.start();
    clock.report(ms(5000));
    advance(200);
    clock.pause();
    advance(3000);
    clock.resume();
    expect(clock.position, ms(5200));
    advance(100);
    expect(clock.position, ms(5300));
  });

  test('une pause avant le premier rapport reprend en attente', () {
    clock.start();
    clock.pause();
    advance(500);
    clock.resume();
    expect(clock.position, Duration.zero);
    clock.report(ms(30));
    expect(clock.position, ms(30));
  });

  test('freeRun : l\'horloge court seule à partir de zéro', () {
    clock.start();
    advance(3000);
    clock.freeRun();
    expect(clock.position, Duration.zero);
    advance(1000);
    expect(clock.position, ms(1000));
    expect(clock.isSynced, isFalse);
  });

  test('la position dépasse la fin du morceau au lieu de se figer', () {
    clock.start();
    clock.report(ms(178800));
    advance(1000);
    expect(clock.position, ms(179800),
        reason: 'la séance dure un peu plus que le morceau : sans '
            'extrapolation elle ne se terminerait jamais');
  });

  test('stop fige la position pour l\'écran de fin', () {
    clock.start();
    clock.report(ms(1000));
    advance(500);
    clock.stop();
    advance(5000);
    expect(clock.position, ms(1500));
  });
}
