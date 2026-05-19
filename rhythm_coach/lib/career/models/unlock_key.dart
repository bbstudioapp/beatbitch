/// Identifiants typés des compétences/actions débloquées via les milestones.
///
/// **Invariant** : une milestone du catalogue accorde **exactement une**
/// `UnlockKey`, et cette clé est consommée quelque part — gate de step dans
/// le générateur, comportement runtime dans `SessionController`, filtre de
/// contenu `requires_unlock`, ou prérequis `requires` d'une autre milestone.
/// Vérifié par `test/milestone_unlock_invariants_test.dart`.
///
/// Une action sans `UnlockKey` est ouverte par défaut : hand, lick tip→head,
/// rythme superficiel tip→head, holds tip/head, breath. Le final de repli
/// (hand/head/mid) est lui aussi libre (aucune clé).
enum UnlockKey {
  /// Socle de base — accordé par la milestone tuto (`intro_basics`). Ne
  /// gate **aucune** action de step ; c'est la clé « exception » : elle
  /// sert de prérequis (`requires`) aux milestones racines de chaque
  /// piste, pour qu'aucune ne tombe avant le tutoriel.
  basics,
  // Bases « profondeur en bouche »
  rhythmMidBasic,
  lickFull,
  // Holds simples
  //
  // `holdHead` : clé pédagogique « savoir poser et tenir la bouche sur le
  // gland sans bouger ». Ne gate pas les steps `hold to=head` du générateur
  // (ils restent du socle de base, comme tip), c'est une clé prérequis-only
  // — au même titre que `basics` — consommée par `intro_suckle_head` qui
  // exige d'avoir prouvé la tenue de bouche avant d'apprendre l'aspiration.
  holdHead,
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
  rhythmHeadMidSustained,
  biffleBasic,
  biffleFast,
  // Modes spéciaux
  freestyle,
  begLibre,
  // begThroat renommé en begHeadMid (Phase 5 défis) : les begs avec
  // position tenue sont désormais cappés à `mid` côté pickBegPosition,
  // parce que parler en gorge tenue est irréaliste. begFull retiré
  // pour la même raison. Les joueuses existantes ont un mapping legacy
  // (cf. `UnlockKey.fromString`) qui résout `beg_throat` vers
  // `begHeadMid` pour ne pas perdre l'unlock acquis.
  begHeadMid,
  // Sloppy — chacune gate un sous-pool de commentaires coach (cf.
  // `assets/random_comments.json` : filtre `requires_unlock` + contexte /
  // barre de salive `min_saliva`). Trois ont en plus un effet runtime :
  //   - sloppyDroolBasic     : production salive lick ×1.5, plafond barre 100
  //   - sloppyBiffleSlow     : production salive biffle ×3
  //   - sloppySwallowControl : autorise le toggle `SwallowMode.forbidden`
  sloppyDroolBasic,
  sloppyBiffleSlow,
  sloppyLoudSuck,
  sloppyOverflow,
  sloppySwallowControl,
  sloppySpit,
  // Finals dédiés — chaque step terminal d'apothéose a son unlock pour
  // n'apparaître qu'après la milestone d'introduction correspondante.
  finalHoldTip,
  finalLickTipHead,
  finalHoldHead,
  finalHoldMid,
  finalBiffle,
  finalHoldThroat,
  finalHoldFull,
  // Carrière — option « j'en veux encore » en fin de session. Débloquée
  // par la milestone `intro_encore` OU par une obédiance ≥ 80 (voie
  // alternative côté career_screen). Cf. doc.
  encore,
  // Réglages des notifications surprise (Android only). L'icône de
  // raccourci sur l'AppBar de ModeSelectionScreen et l'accès à l'écran
  // de configuration sont gatés par cette clé. Débloquée par la
  // milestone `intro_surprise_notifs`.
  surpriseNotifs,
  // Faux sas breath — `_maybeBuildFakeBreath` du générateur insère un
  // mini-breath 2-3s après un step intense qui mime un repos sans
  // vraiment regénérer la stamina. Désactivé tant que la milestone
  // `intro_fake_breath` n'est pas acquittée (en carrière). En mode
  // hérité — Custom / scénarios / debug, `_unlockedKeys.isEmpty` — le
  // mécanisme reste actif sans gating.
  fakeBreath,
  // Position balls — zone latérale (testicules). Gating anatomy assuré
  // séparément par `AnatomyProfile.hasBalls` dans `_isUnlocked` ; ces
  // clés gouvernent l'apprentissage pédagogique chez les joueuses qui
  // ont la zone. Trois actions distinctes : lick (toucher de langue),
  // hold (tenir en bouche), beg (supplique en tenant).
  lickBalls,
  holdBalls,
  begBalls,
  // Mode suckle (aspiration / téter) — geste actif-statique. Deux paliers
  // pédagogiques distincts : `suckleHead` (zone introductive, level 4-5)
  // et `suckleBalls` (zone humil pure, level 10-11, gating anatomy en
  // plus côté MilestoneService).
  suckleHead,
  suckleBalls;

  String get serialized => switch (this) {
        UnlockKey.basics => 'basics',
        UnlockKey.rhythmMidBasic => 'rhythm_mid_basic',
        UnlockKey.lickFull => 'lick_full',
        UnlockKey.holdHead => 'hold_head',
        UnlockKey.holdMidShort => 'hold_mid_short',
        UnlockKey.throatHoldShort => 'throat_hold_short',
        UnlockKey.throatHoldLong => 'throat_hold_long',
        UnlockKey.fullHoldShort => 'full_hold_short',
        UnlockKey.fullHoldLong => 'full_hold_long',
        UnlockKey.throatPulse => 'throat_pulse',
        UnlockKey.fullPulse => 'full_pulse',
        UnlockKey.rhythmExtreme => 'rhythm_extreme',
        UnlockKey.rhythmHeadMidSustained => 'rhythm_head_mid_sustained',
        UnlockKey.biffleBasic => 'biffle_basic',
        UnlockKey.biffleFast => 'biffle_fast',
        UnlockKey.freestyle => 'freestyle',
        UnlockKey.begLibre => 'beg_libre',
        UnlockKey.begHeadMid => 'beg_head_mid',
        UnlockKey.sloppyDroolBasic => 'sloppy_drool_basic',
        UnlockKey.sloppyBiffleSlow => 'sloppy_biffle_slow',
        UnlockKey.sloppyLoudSuck => 'sloppy_loud_suck',
        UnlockKey.sloppyOverflow => 'sloppy_overflow',
        UnlockKey.sloppySwallowControl => 'sloppy_swallow_control',
        UnlockKey.sloppySpit => 'sloppy_spit',
        UnlockKey.finalHoldTip => 'final_hold_tip',
        UnlockKey.finalLickTipHead => 'final_lick_tip_head',
        UnlockKey.finalHoldHead => 'final_hold_head',
        UnlockKey.finalHoldMid => 'final_hold_mid',
        UnlockKey.finalBiffle => 'final_biffle',
        UnlockKey.finalHoldThroat => 'final_hold_throat',
        UnlockKey.finalHoldFull => 'final_hold_full',
        UnlockKey.encore => 'encore',
        UnlockKey.surpriseNotifs => 'surprise_notifs',
        UnlockKey.fakeBreath => 'fake_breath',
        UnlockKey.lickBalls => 'lick_balls',
        UnlockKey.holdBalls => 'hold_balls',
        UnlockKey.begBalls => 'beg_balls',
        UnlockKey.suckleHead => 'suckle_head',
        UnlockKey.suckleBalls => 'suckle_balls',
      };

  static UnlockKey? fromString(String? raw) {
    if (raw == null) return null;
    // Mapping legacy Phase 5 défis : les joueuses existantes ont peut-être
    // `beg_throat` (et plus rarement `beg_full`) acquittés via l'ancien
    // catalogue. On les résout vers `begHeadMid` pour préserver l'unlock
    // sans introduire de nouvelle clé dédiée.
    if (raw == 'beg_throat' || raw == 'beg_full') return UnlockKey.begHeadMid;
    for (final k in UnlockKey.values) {
      if (k.serialized == raw) return k;
    }
    return null;
  }
}
