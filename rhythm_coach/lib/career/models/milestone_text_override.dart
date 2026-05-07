/// Surcharge i18n des textes d'une milestone (cf. `assets/career/milestones/<id>_<lang>.json`).
///
/// `stepTexts` est indexé par offset temporel `time` du step dans la
/// `sequence` du milestone principal. Une clé manquante = le `text` du
/// JSON principal est conservé. `displayLabel` localise le titre court
/// affiché dans l'UI ; `null` → on garde le `displayLabel` du catalogue
/// principal (FR).
class MilestoneTextOverride {
  final Map<int, String> stepTexts;
  final String? unlockAnnouncement;
  final String? displayLabel;

  const MilestoneTextOverride({
    this.stepTexts = const {},
    this.unlockAnnouncement,
    this.displayLabel,
  });

  String? textForTime(int time) => stepTexts[time];
}
