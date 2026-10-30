import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/l10n/enum_labels.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sur le fond clair de l'interface v2, les libellés de niveau (Bout… Couilles)
/// se lisaient mal : ombre portée, graisse et blanc franc pour les inactifs.
void main() {
  testWidgets('libellés de niveau : ombre portée, graisse et contraste',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MovementAnimation(
          mode: SessionMode.hold,
          from: Position.mid,
          to: Position.mid,
          bpm: 60,
          positionRowCount: 6,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));
    final context = tester.element(find.byType(MovementAnimation));

    TextStyle styleOf(Position p) =>
        tester.widget<Text>(find.text(p.localizedLabel(context))).style!;

    final inactive = styleOf(Position.tip);
    expect(inactive.shadows, isNotEmpty, reason: 'ombre portée');
    expect(inactive.fontWeight!.value, greaterThanOrEqualTo(600));
    expect(inactive.color!.a, greaterThanOrEqualTo(0.85),
        reason: 'plus le gris à 45 % de l\'ancien style');

    final active = styleOf(Position.mid);
    expect(active.shadows, isNotEmpty);
    expect(active.fontWeight!.value, greaterThan(inactive.fontWeight!.value));
    expect(active.color!.a, 1.0, reason: 'niveau actif en couleur pleine');
  });
}
