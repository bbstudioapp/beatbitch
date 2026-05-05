/// Identifiants typés des compétences/actions débloquées via les milestones.
///
/// Une action sans `UnlockKey` est ouverte par défaut (modes basiques :
/// rythme superficiel, lick, hand). Les actions avec une `UnlockKey` ne
/// peuvent apparaître dans une session que si la milestone correspondante
/// a été acquittée avec succès (cf. `MilestoneService.hasUnlock`).
enum UnlockKey {
  // Bases (intro_basics, niveau 1)
  handBasic,
  lickTipBasic,
  rhythmTipHead,
  holdTip,
  holdHead,
  // Bases niveau 2
  rhythmMidBasic,
  lickFull,
  // Holds simples
  holdHeadShort,
  holdMidShort,
  throatHoldShort,
  throatHoldLong,
  fullHoldShort,
  fullHoldLong,
  // Pulses (rythmes profonds)
  throatPulse,
  fullPulse,
  // Tempo
  rhythmExtreme,
  biffleBasic,
  biffleFast,
  // Modes spéciaux
  freestyle,
  begLibre,
  begThroat,
  begFull,
  // Bases sloppy / résilience (tags de progression — pas de gating en
  // V1, juste pour signaler la complétion des milestones thématiques)
  sloppyDroolBasic,
  sloppyBiffleSlow,
  sloppyLoudSuck,
  sloppyOverflow,
  resilienceEndureBasic,
  resilienceRecovery,
  resilienceOneMore,
  resilienceCount,
  // Combos
  comboHoldFullChained,
  // Finals dédiés — chaque step terminal (final de séance) a son
  // unlock pour qu'il ne puisse apparaître qu'après la milestone
  // d'introduction correspondante. `finalHandHeadMid` reste libre :
  // c'est le fallback universel (req 0, hand baseline).
  finalHoldTip,
  finalLickTipHead,
  finalHoldHead,
  finalHoldMid,
  finalBiffle,
  finalHoldThroat,
  finalHoldFull,
  // Carrière — option encore (J'en veux encore) en fin de session.
  // Débloquée par la milestone intro_encore (niveau 5) OU par une
  // obédiance ≥ 80 (voie alternative côté career_screen). Cf. doc.
  encore;

  String get serialized => switch (this) {
        UnlockKey.handBasic => 'hand_basic',
        UnlockKey.lickTipBasic => 'lick_tip_basic',
        UnlockKey.rhythmTipHead => 'rhythm_tip_head',
        UnlockKey.holdTip => 'hold_tip',
        UnlockKey.holdHead => 'hold_head',
        UnlockKey.rhythmMidBasic => 'rhythm_mid_basic',
        UnlockKey.lickFull => 'lick_full',
        UnlockKey.holdHeadShort => 'hold_head_short',
        UnlockKey.holdMidShort => 'hold_mid_short',
        UnlockKey.throatHoldShort => 'throat_hold_short',
        UnlockKey.throatHoldLong => 'throat_hold_long',
        UnlockKey.fullHoldShort => 'full_hold_short',
        UnlockKey.fullHoldLong => 'full_hold_long',
        UnlockKey.throatPulse => 'throat_pulse',
        UnlockKey.fullPulse => 'full_pulse',
        UnlockKey.rhythmExtreme => 'rhythm_extreme',
        UnlockKey.biffleBasic => 'biffle_basic',
        UnlockKey.biffleFast => 'biffle_fast',
        UnlockKey.freestyle => 'freestyle',
        UnlockKey.begLibre => 'beg_libre',
        UnlockKey.begThroat => 'beg_throat',
        UnlockKey.begFull => 'beg_full',
        UnlockKey.sloppyDroolBasic => 'sloppy_drool_basic',
        UnlockKey.sloppyBiffleSlow => 'sloppy_biffle_slow',
        UnlockKey.sloppyLoudSuck => 'sloppy_loud_suck',
        UnlockKey.sloppyOverflow => 'sloppy_overflow',
        UnlockKey.resilienceEndureBasic => 'resilience_endure_basic',
        UnlockKey.resilienceRecovery => 'resilience_recovery',
        UnlockKey.resilienceOneMore => 'resilience_one_more',
        UnlockKey.resilienceCount => 'resilience_count',
        UnlockKey.comboHoldFullChained => 'combo_hold_full_chained',
        UnlockKey.finalHoldTip => 'final_hold_tip',
        UnlockKey.finalLickTipHead => 'final_lick_tip_head',
        UnlockKey.finalHoldHead => 'final_hold_head',
        UnlockKey.finalHoldMid => 'final_hold_mid',
        UnlockKey.finalBiffle => 'final_biffle',
        UnlockKey.finalHoldThroat => 'final_hold_throat',
        UnlockKey.finalHoldFull => 'final_hold_full',
        UnlockKey.encore => 'encore',
      };

  static UnlockKey? fromString(String? raw) {
    if (raw == null) return null;
    for (final k in UnlockKey.values) {
      if (k.serialized == raw) return k;
    }
    return null;
  }
}
