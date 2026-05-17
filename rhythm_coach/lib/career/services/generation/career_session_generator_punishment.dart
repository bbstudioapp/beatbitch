// Fichier part de `career_session_generator.dart` — palette de punitions
// générées (Phase 5 de la spec).
//
// Décision projet : la sélection est strictement « max humil qui passe »
// (parité dramaturgique avec `FinalPicker.pickFinal`), pas de biais
// d'axe surchargé. L'axe surchargé influence indirectement via le `comfort`
// élargi côté `_clampToCapability`, mais la palette elle-même reste
// universelle.
//
// La méthode publique `generatePunishment(...)` reste sur la classe
// `CareerSessionGenerator` — c'est une entrée d'API consommée par
// `SessionController` et les tests. Son body se limite au reset d'état
// (mêmes invariants que `generate`) puis un delegate vers `_PunishmentBuilder`
// qui héberge la palette, la sélection et la matérialisation.

part of 'career_session_generator.dart';

/// Composition de punition carrière (Phase 5). Tuple
/// `(id, drafts, reqHumil, handRequired)` qui mime la palette de
/// `FinalPicker.pickFinal` — drafts non-clampés (le clamp se fait au
/// moment de la matérialisation via [_PunishmentBuilder._materialize]).
class _PunishmentCompo {
  final String id;
  final List<StepDraft> drafts;
  final double reqHumil;

  /// Si vrai, la compo est exclue quand `includeHand == false` (compo qui
  /// implique la main, comme `biffle_burst`).
  final bool handRequired;

  const _PunishmentCompo({
    required this.id,
    required this.drafts,
    required this.reqHumil,
    this.handRequired = false,
  });
}

/// Constructeur de punition contextuelle. Toutes les méthodes sont
/// statiques — elles consultent l'état du `CareerSessionGenerator` via
/// les champs library-private de l'instance passée. Le caller
/// (`generatePunishment`) garantit que les fields ont été (re)posés et
/// que `_capClamps` est construit avant l'appel.
class _PunishmentBuilder {
  /// Palette V1 : 5 compos triées par humil croissante. Parité
  /// dramaturgique avec `FinalPicker.pickFinal`.
  static const List<_PunishmentCompo> palette = [
    // Biffle rapide court — le moins humiliant qui reste punitif. Gaté
    // `includeHand` (biffle implique la main, comme dans `FinalPicker`).
    _PunishmentCompo(
      id: 'biffle_burst',
      drafts: [
        StepDraft(
          mode: SessionMode.biffle,
          bpm: 135,
          from: null,
          to: null,
          duration: 25,
        ),
      ],
      reqHumil: 13.0,
      handRequired: true,
    ),
    // Franchissement `head→throat` rapide — axe « crossings BPM throat ».
    _PunishmentCompo(
      id: 'crossings_burst',
      drafts: [
        StepDraft(
          mode: SessionMode.rhythm,
          bpm: 110,
          from: Position.head,
          to: Position.throat,
          duration: 25,
        ),
      ],
      reqHumil: 14.0,
    ),
    // Torture lente profonde — rhythm `throat→full` BPM bas (= airless,
    // pas de fenêtre de respiration) + hold full final.
    _PunishmentCompo(
      id: 'slow_torture',
      drafts: [
        StepDraft(
          mode: SessionMode.rhythm,
          bpm: 35,
          from: Position.throat,
          to: Position.full,
          duration: 30,
        ),
        StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.full,
          duration: 8,
        ),
      ],
      reqHumil: 16.0,
    ),
    // Throat sans pitié — rhythm `throat→full` rapide + hold final.
    _PunishmentCompo(
      id: 'throat_relentless',
      drafts: [
        StepDraft(
          mode: SessionMode.rhythm,
          bpm: 100,
          from: Position.throat,
          to: Position.full,
          duration: 28,
        ),
        StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.full,
          duration: 8,
        ),
      ],
      reqHumil: 18.0,
    ),
    // Chaîne de holds profonds avec courte fenêtre breath au milieu — la
    // plus humiliante de la palette V1.
    _PunishmentCompo(
      id: 'deep_hold_chain',
      drafts: [
        StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.throat,
          duration: 10,
        ),
        StepDraft(
          mode: SessionMode.breath,
          bpm: null,
          from: null,
          to: null,
          duration: 4,
        ),
        StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.full,
          duration: 12,
        ),
      ],
      reqHumil: 20.0,
    ),
  ];

  /// Étape 1 du fallback : rythme `head→mid` rapide (req≈5). Reste une
  /// vraie punition (BPM élevé) tant qu'on a un peu d'humil derrière.
  /// À niv. 2-3 c'est ici qu'on tombe en pratique pour une séance fragile.
  static const _PunishmentCompo lastResort = _PunishmentCompo(
    id: 'last_resort_rhythm',
    drafts: [
      StepDraft(
        mode: SessionMode.rhythm,
        bpm: 120,
        from: Position.head,
        to: Position.mid,
        duration: 22,
      ),
    ],
    reqHumil: 5.0,
  );

  /// Filet ultime hand `head→mid` 50 BPM. req=0, toujours jouable.
  /// N'arrive qu'à humilCap≈0 + tous les autres bloqués — pas en pratique
  /// sur une joueuse carrière (mais évite tout crash).
  static const _PunishmentCompo handFallback = _PunishmentCompo(
    id: 'hand_fallback',
    drafts: [
      StepDraft(
        mode: SessionMode.hand,
        bpm: 50,
        from: Position.head,
        to: Position.mid,
        duration: 15,
      ),
    ],
    reqHumil: 0.0,
  );

  /// Construit la punition contextuelle. Le caller a déjà posé l'état
  /// d'instance via `generatePunishment` (humiliation, unlocks, capacité,
  /// `_capClamps`…).
  ///
  /// Algo : on filtre [palette] par humilCap + unlocks composants + gating
  /// hand ; sélection = max humiliant valide (parité `FinalPicker.pickFinal`).
  /// Si rien ne passe, escalier `lastResort` → `handFallback`.
  static Punishment buildFor(
    CareerSessionGenerator gen,
    PhraseBank bank,
    bool includeHand,
  ) {
    final humilCap =
        gen._config.humiliationCareer + gen._config.humiliationSession;

    // Filtre humilCap + unlocks composants + gating hand. Sélection = max
    // humiliant valide (parité `FinalPicker.pickFinal` : tri par `req`
    // croissante, `valid.last`).
    final valid = palette.where((c) {
      if (c.handRequired && !includeHand) return false;
      if (c.reqHumil > humilCap) return false;
      return c.drafts.every(gen._isUnlocked);
    }).toList()
      ..sort((a, b) => a.reqHumil.compareTo(b.reqHumil));
    if (valid.isNotEmpty) {
      return _materialize(gen, valid.last, bank);
    }

    // Escalier fallback — ordre du plus exigeant au plus doux.
    if (lastResort.reqHumil <= humilCap &&
        lastResort.drafts.every(gen._isUnlocked)) {
      return _materialize(gen, lastResort, bank);
    }
    return _materialize(gen, handFallback, bank);
  }

  /// Convertit une composition (drafts non-clampés) en [Punishment] runtime :
  /// passe chaque draft par `_clampToCapability` (ceilings + comfort),
  /// injecte un texte coach tiré dans le tier `hard` du mode (silencieux
  /// pour `breath`, qui est une transition), et pose les `time` cumulés.
  static Punishment _materialize(
    CareerSessionGenerator gen,
    _PunishmentCompo compo,
    PhraseBank bank,
  ) {
    final steps = <SessionStep>[];
    var time = 0;
    for (final raw in compo.drafts) {
      final clamped = gen._clampToCapability(raw);
      final dur = clamped.duration ?? 0;
      String text = '';
      if (clamped.mode != SessionMode.breath) {
        text = gen._pickPhraseForDraft(bank, clamped, 'hard');
      }
      steps.add(SessionStep(
        time: time,
        text: text,
        mode: clamped.mode,
        bpm: clamped.bpm,
        bpmEnd: clamped.bpmEnd,
        from: clamped.from,
        to: clamped.to,
        duration: dur,
      ));
      time += dur;
    }
    return Punishment(
      id: compo.id,
      name: compo.id,
      durationSeconds: time,
      steps: steps,
    );
  }
}
