import '../../l10n/app_localizations.dart';
import '../models/unlock_key.dart';

/// Annonce TTS par défaut pour une milestone qui ne fournit pas d'override
/// `unlockAnnouncement`. Couvre les unlocks à effet **invisible** côté
/// gameplay (multiplicateur salive, plafond barre, autorisation d'un
/// `swallow_mode`, cap durée). Les unlocks dont la nouveauté est déjà
/// ressentie pendant la séquence pédagogique de la milestone (hold profond,
/// biffle, freestyle…) retournent `null` — pas la peine de tasser deux
/// phrases en fin de séance.
String? defaultAnnouncementFor(UnlockKey key, AppLocalizations l10n) {
  switch (key) {
    case UnlockKey.sloppyDroolBasic:
      return l10n.unlockAnnouncementSloppyDroolBasic;
    case UnlockKey.sloppyBiffleSlow:
      return l10n.unlockAnnouncementSloppyBiffleSlow;
    case UnlockKey.sloppySwallowControl:
      return l10n.unlockAnnouncementSloppySwallowControl;
    case UnlockKey.sloppySpit:
      return l10n.unlockAnnouncementSloppySpit;
    case UnlockKey.sloppyDroolDeep:
      return l10n.unlockAnnouncementSloppyDroolDeep;
    case UnlockKey.rhythmHeadMidSustained:
      return l10n.unlockAnnouncementRhythmHeadMidSustained;
    default:
      return null;
  }
}
