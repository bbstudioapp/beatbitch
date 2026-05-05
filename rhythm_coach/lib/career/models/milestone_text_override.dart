/// Surcharge i18n des textes d'une milestone (cf. `assets/career/milestones/<id>_<lang>.json`).
///
/// `stepTexts` est indexé par offset temporel `time` du step dans la
/// `sequence` du milestone principal. Une clé manquante = le `text` du
/// JSON principal est conservé.
class MilestoneTextOverride {
  final Map<int, String> stepTexts;
  final String? unlockAnnouncement;

  const MilestoneTextOverride({
    this.stepTexts = const {},
    this.unlockAnnouncement,
  });

  String? textForTime(int time) => stepTexts[time];
}
