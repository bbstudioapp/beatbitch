import 'package:beat_bitch/career/services/career_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `CareerProgressService.canLevelUp(...)` : règle level-up gaté par
/// milestone. La fonction est pure, on la teste sans persistence.
void main() {
  final svc = CareerProgressService();

  test('clean + milestone acquittée → level-up', () {
    expect(
      svc.canLevelUp(
        cleanSession: true,
        isQuickie: false,
        milestoneAcquittedThisSession: true,
        hasPendingAtCurrentLevel: true,
      ),
      isTrue,
    );
  });

  test('clean + milestone candidate non acquittée → pas de level-up', () {
    expect(
      svc.canLevelUp(
        cleanSession: true,
        isQuickie: false,
        milestoneAcquittedThisSession: false,
        hasPendingAtCurrentLevel: true,
      ),
      isFalse,
    );
  });

  test('clean + catalogue épuisé au level courant → level-up libre', () {
    expect(
      svc.canLevelUp(
        cleanSession: true,
        isQuickie: false,
        milestoneAcquittedThisSession: false,
        hasPendingAtCurrentLevel: false,
      ),
      isTrue,
    );
  });

  test('quickie → pas de level-up même clean + milestone acquittée', () {
    expect(
      svc.canLevelUp(
        cleanSession: true,
        isQuickie: true,
        milestoneAcquittedThisSession: true,
        hasPendingAtCurrentLevel: false,
      ),
      isFalse,
    );
  });

  test('fail → pas de level-up, peu importe le reste', () {
    expect(
      svc.canLevelUp(
        cleanSession: false,
        isQuickie: false,
        milestoneAcquittedThisSession: true,
        hasPendingAtCurrentLevel: false,
      ),
      isFalse,
    );
  });
}
