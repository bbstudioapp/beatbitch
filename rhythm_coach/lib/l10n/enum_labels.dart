import 'package:flutter/widgets.dart';

import '../career/models/specialization.dart';
import '../models/badge.dart';
import '../models/session.dart';
import '../models/session_step.dart';
import 'app_localizations.dart';

extension SessionModeL10n on SessionMode {
  String shortLabel(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (this) {
      SessionMode.rhythm => t.modeShortRhythm,
      SessionMode.hold => t.modeShortHold,
      SessionMode.lick => t.modeShortLick,
      SessionMode.biffle => t.modeShortBiffle,
      SessionMode.breath => t.modeShortBreath,
      SessionMode.beg => t.modeShortBeg,
      SessionMode.freestyle => t.modeShortFreestyle,
      SessionMode.hand => t.modeShortHand,
    };
  }
}

extension PositionL10n on Position {
  String localizedLabel(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (this) {
      Position.tip => t.positionTip,
      Position.head => t.positionHead,
      Position.mid => t.positionMid,
      Position.throat => t.positionThroat,
      Position.full => t.positionFull,
    };
  }
}

extension BadgeTierL10n on BadgeTier {
  String localizedLabel(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (this) {
      BadgeTier.none => '—',
      BadgeTier.bronze => t.badgeTierBronze,
      BadgeTier.silver => t.badgeTierSilver,
      BadgeTier.gold => t.badgeTierGold,
      BadgeTier.platinium => t.badgeTierPlatinium,
    };
  }
}

extension BadgeFamilyL10n on BadgeFamily {
  String localizedDisplayName(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (this) {
      BadgeFamily.marathonien => t.badgeNameMarathonien,
      BadgeFamily.throatQueen => t.badgeNameThroatQueen,
      BadgeFamily.ironLungs => t.badgeNameIronLungs,
      BadgeFamily.toutTerrain => t.badgeNameToutTerrain,
      BadgeFamily.sansBroncher => t.badgeNameSansBroncher,
      BadgeFamily.reguliere => t.badgeNameReguliere,
      BadgeFamily.jamaisRassasiee => t.badgeNameJamaisRassasiee,
      BadgeFamily.videCouilles => t.badgeNameVideCouilles,
    };
  }

  String localizedUnitLabel(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (this) {
      BadgeFamily.marathonien => t.badgeUnitMarathonien,
      BadgeFamily.throatQueen => t.badgeUnitThroatQueen,
      BadgeFamily.ironLungs => t.badgeUnitIronLungs,
      BadgeFamily.toutTerrain => t.badgeUnitToutTerrain,
      BadgeFamily.sansBroncher => t.badgeUnitSansBroncher,
      BadgeFamily.reguliere => t.badgeUnitReguliere,
      BadgeFamily.jamaisRassasiee => t.badgeUnitJamaisRassasiee,
      BadgeFamily.videCouilles => t.badgeUnitVideCouilles,
    };
  }
}

extension SpecializationBranchL10n on SpecializationBranch {
  String localizedLabel(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (this) {
      SpecializationBranch.endurance => t.specBranchEnduranceLabel,
      SpecializationBranch.profondeur => t.specBranchProfondeurLabel,
      SpecializationBranch.rythmeBiffle => t.specBranchRythmeBiffleLabel,
      SpecializationBranch.obeissance => t.specBranchObeissanceLabel,
      SpecializationBranch.sloppy => t.specBranchSloppyLabel,
      SpecializationBranch.resilience => t.specBranchResilienceLabel,
    };
  }

  String localizedDescription(BuildContext context) {
    final t = AppLocalizations.of(context);
    return switch (this) {
      SpecializationBranch.endurance => t.specBranchEnduranceDesc,
      SpecializationBranch.profondeur => t.specBranchProfondeurDesc,
      SpecializationBranch.rythmeBiffle => t.specBranchRythmeBiffleDesc,
      SpecializationBranch.obeissance => t.specBranchObeissanceDesc,
      SpecializationBranch.sloppy => t.specBranchSloppyDesc,
      SpecializationBranch.resilience => t.specBranchResilienceDesc,
    };
  }
}

/// Titre localisé d'un niveau de carrière. Garde la même logique de
/// paliers que `CareerLevel._titleForLevel` — la version non-localisée
/// reste disponible (TTS, persistance, etc.).
String localizedCareerLevelTitle(BuildContext context, int level) {
  final t = AppLocalizations.of(context);
  if (level <= 2) return t.careerLevelTitleDebutante;
  if (level <= 4) return t.careerLevelTitleApprentieSuceuse;
  if (level <= 6) return t.careerLevelTitlePetiteSalopeConfirmee;
  if (level <= 8) return t.careerLevelTitleBoucheAPipe;
  if (level == 9) return t.careerLevelTitleAvaleuse;
  if (level <= 12) return t.careerLevelTitleThroatQueen;
  if (level <= 14) return t.careerLevelTitleReineDuSloppy;
  if (level <= 17) return t.careerLevelTitleTrouABiteOfficiel;
  if (level <= 19) return t.careerLevelTitleVideCouillesPro;
  return t.careerLevelTitleReineDesPutes;
}
