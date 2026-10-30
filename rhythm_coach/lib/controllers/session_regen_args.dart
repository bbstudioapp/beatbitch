import '../models/posture.dart';
import 'session_controller.dart';

typedef RegenArgs = ({int durationSeconds, PostureScript carry});

extension SessionRegenArgs on SessionController {
  int upgradeRegenDuration(int begDuration) =>
      effortSecondsLeftFrom(elapsedSeconds) - begDuration;

  RegenArgs milestoneRetryRegenArgs({
    required int begDuration,
    required int milestoneSeconds,
  }) =>
      (
        durationSeconds:
            effortSecondsLeftFrom(elapsedSeconds) + milestoneSeconds,
        carry: postureCarryFrom(elapsedSeconds + begDuration),
      );

  RegenArgs postChallengeRegenArgs() {
    final breathEnd = postChallengeBreathUntilSec ?? elapsedSeconds;
    return (
      durationSeconds: effortSecondsLeftFrom(breathEnd),
      carry: postureCarryFrom(breathEnd),
    );
  }
}
