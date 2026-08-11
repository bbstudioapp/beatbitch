part of 'session_controller.dart';

// ─── Hooks carrière ───────────────────────────────────────────────────
//
// Points d'entrée que le `CareerScreen` (et certains chemins de
// `CustomMode`) consomment pour piloter la séance après son démarrage :
//
//   - requestUpgrade           : « Supplier » — coupe la suite et la
//                                remplace par un beg insistant + une
//                                régénération à un niveau supérieur.
//   - requestPostChallengeRegen : après un défi qui a élargi les
//                                unlocks, remplace la suite par une
//                                session qui consomme la compétence.
//   - revealBadgeUnlocks       : déclenché par le bouton MERCI de
//                                l'écran de fin, déplace les paliers
//                                pending vers `sessionBadgeUnlocks` et
//                                annonce les TTS.
//   - hasPendingBadges (getter): consommé par `_FinishedPanel`.
//
// Plus deux helpers privés très liés à `_finish` :
//   - _tapoutPhraseOrNull      : phrase « limite reconnue » Phase 4
//                                consommée par `triggerFail`.
//   - _detectCapabilityRecord  : détecte si la séance vient de battre
//                                le `best` de l'axe surchargé.
//
// Les champs d'état (`_pendingBadgeUnlocks`, `_sessionBadgeUnlocks`) et
// la fonction statique `SessionController.buildPostChallengeRegenSession`
// (utilisée par les tests via `SessionController.<name>`) restent sur la
// classe — les extensions Dart ne portent ni champs d'instance ni
// membres statiques.

extension CareerHooksOrchestrator on SessionController {
  /// True si des badges ont été détectés à la complétion mais pas encore
  /// révélés (l'utilisateur n'a pas tapé MERCI). Permet à l'UI d'afficher
  /// le bouton MERCI avant la grille de badges.
  bool get hasPendingBadges => _pendingBadgeUnlocks.isNotEmpty;

  /// Phrase « limite reconnue » Phase 4 — variante DOUCE des phrases de
  /// fail, dite par le coach quand le « je peux pas » est imputable à un
  /// axe poussé au-delà de sa zone de confort (§6, attribution non ambiguë
  /// grâce à la surcharge isolée), et que le dé ∝ niveau tombe juste.
  ///
  /// Suppose `CapabilityTracker.onFail()` déjà appelé (les `sessionCeilings`
  /// sont à jour). `null` = pas de phrase dédiée → l'appelant retombe sur le
  /// tirage de fail standard.
  String? _tapoutPhraseOrNull() {
    final tracker = _capabilityTracker;
    final profile = _capabilityProfile;
    final bank = _phraseBank;
    if (tracker == null || profile == null || bank == null) return null;
    final axis =
        CapabilityRegulator.attributeTapOut(tracker.sessionCeilings, profile);
    if (axis == null) return null;
    if (_random.nextDouble() >=
        CapabilityRegulator.progressPhraseChanceForLevel(_careerLevel)) {
      return null;
    }
    final phrase = bank.pickProgressPhrase(axis.storageKey, 'tapout', _random);
    return (phrase != null && phrase.isNotEmpty) ? phrase : null;
  }

  /// Détecte si la séance vient de battre le `best` de l'axe poussé cette
  /// séance (`_capabilityOverloadAxis`, axe pilotant `maximize`) en comparant
  /// `reached` au snapshot pré-séance. Renvoie l'axe en cas de record propre,
  /// `null` sinon — pas d'axe surchargé, pas d'amélioration, ou séance avec un
  /// « je peux pas » (on ne célèbre pas un record juste après un tap-out, §9 ;
  /// le `best` reste enregistré par `CapabilityService.commit` quoi qu'il arrive).
  CapabilityAxis? _detectCapabilityRecord(SessionCapabilityReport? report) {
    if (report == null || _hadFailThisSession) return null;
    final axis = _capabilityOverloadAxis;
    final profile = _capabilityProfile;
    if (axis == null || profile == null) return null;
    if (!axis.pilotant || axis.recordKind != CapabilityRecordKind.maximize) {
      return null;
    }
    final reached = report.reached[axis];
    if (reached == null) return null;
    final before = profile.bestOf(axis);
    return (before == null || reached > before) ? axis : null;
  }

  /// Révèle les paliers de badges atteints pendant la séance : déplace la
  /// liste pending vers `sessionBadgeUnlocks`, lance les annonces TTS, et
  /// notifie l'UI. À appeler depuis le bouton MERCI de l'écran de fin.
  /// La phrase TTS est localisée via `_appLocalizations` (poussé depuis
  /// l'UI par [SessionController.setAppLocalizations]) ; si la locale n'a
  /// pas encore été poussée (cas anormal — l'UI le fait au start de la
  /// séance), on révèle les badges côté UI mais on n'annonce pas TTS.
  Future<void> revealBadgeUnlocks() async {
    if (_pendingBadgeUnlocks.isEmpty) return;
    final unlocks = _pendingBadgeUnlocks;
    _pendingBadgeUnlocks = const [];
    _sessionBadgeUnlocks = unlocks;
    _notify();
    final l10n = _appLocalizations;
    if (l10n == null) return;
    for (final u in unlocks) {
      if (_released) break;
      await _tts.speak(u.announcement(l10n));
    }
  }

  /// Coupe la timeline restante et la remplace par : un beg insistant
  /// immédiat (à `elapsedSeconds`), suivi des [upcomingSession.steps] rebased
  /// pour démarrer juste après le beg. Utilisé par le bouton « SUPPLIER »
  /// du mode Carrière, qui régénère une suite à un niveau supérieur
  /// pendant que l'utilisateur supplie.
  ///
  /// Les `upcomingSession.steps` doivent avoir leur `time` exprimé relativement
  /// à zéro (le générateur produit toujours un `time` croissant à partir
  /// de 0) — la méthode rebase elle-même.
  Future<void> requestUpgrade({
    required SessionStep insistentBeg,
    required Session upcomingSession,
  }) async {
    if (_state != SessionState.running) return;

    final start = elapsedSeconds;

    // Délégué à `buildUpgradedSession` (helper statique pur, testable) :
    // propage les body milestones de l'ancienne session dont la fenêtre
    // est déjà terminée (sinon Supplier les coupe et `_finish` ne doit pas
    // les acquitter), ajoute celles de `upcomingSession` décalées de
    // `start + begDuration` (cas retry milestone), prend le final
    // milestone de `upcomingSession` (Supplier remplace le final).
    _session = SessionController.buildUpgradedSession(
      previous: _session,
      upcoming: upcomingSession,
      insistentBeg: insistentBeg,
      start: start,
    );

    // Coupe le TTS en cours pour ne pas garder une phrase orpheline
    // de l'ancien step. Le beg insistant va parler tout de suite.
    //
    // Borné : ici le ticker n'est pas arrêté, donc un canal muet ne gèle pas
    // la timeline — il laisse `_onTick` tourner sur la nouvelle `_session`
    // avec l'ancien `_nextStepIndex` jamais remis à 0 (steps consommés
    // désynchronisés du texte attendu), et l'écran garde `_upgradeInFlight`
    // à `true`, donc le bouton « Utilise-moi » durablement désactivé.
    await _stopTtsBounded();

    _nextStepIndex = 0;
    _lastConfigStep = null;
    // Reset de l'état break (issue #77) : la session régénérée n'a pas de
    // break (`scriptedBreaks` non propagé aux régens mi-séance). Si un break
    // était actif au moment du Supplier, on le clôt ici — sinon `_breakActive`
    // resterait coincé à true (la nouvelle `breaks` vide fait sortir
    // `_updateBreakPhase` tôt) et l'effort serait gelé. `_currentPose` est
    // préservée (continuité de pose à travers l'upgrade).
    _breakActive = false;
    _activeBreak = null;
    _nextBreakIndex = 0;
    // Le gate de posture posé à la sortie de ce break tombe avec lui : sans
    // ça il survit à la régénération et fige la nouvelle suite (`_checkSteps`
    // ne consomme plus rien, `_onTick` gèle l'horloge). No-op hors gate.
    confirmPostureReady();
    // Reset du flag chime : la régen apporte son propre step final +
    // apothéose. Si l'ancienne session avait déjà tiré son chime (cas
    // rare où Supplier est cliqué pile entre final et fin), on doit
    // pouvoir rejouer le chime de la nouvelle.
    _finalChimePlayed = false;
    _finaleChimeStarted = false;

    // Force le déclenchement immédiat du beg (time = start ≤ elapsedSeconds).
    _checkSteps();
    _notify();
  }

  /// Remplace la suite de la séance par les [upcomingSession.steps] rebased
  /// à `elapsedSeconds` (= position d'avant le défi, vu que le défi a été
  /// excisé de la timeline par `_excisChallengeFromSession`). Appelée
  /// par le caller depuis `onPostChallengeRegen` quand un défi vient
  /// d'élargir le set d'unlocks — le générateur produit une suite qui
  /// **consomme** la compétence fraîchement débloquée. Pas de phrase de
  /// transition : le breath de 10s du défi sert lui-même de transition.
  ///
  /// Différences avec [requestUpgrade] :
  /// - pas de beg insistant en tête ;
  /// - pas d'appel à `_checkSteps()` immédiat (le breath est encore en
  ///   cours, on n'a rien à consommer maintenant — la nouvelle timeline
  ///   prend la main quand le breath expire) ;
  /// - pas de `_tts.stop()` (la phrase de fin de défi vient juste d'être
  ///   speakée, on la laisse aller au bout).
  ///
  /// `upcomingSession.steps[*].time` doivent être croissants depuis 0 ;
  /// la méthode les rebase elle-même sur `breathEnd`.
  Future<void> requestPostChallengeRegen({
    required Session upcomingSession,
  }) async {
    if (_state != SessionState.running) return;
    // Avec l'excision du défi par `_excisChallengeFromSession`, la
    // séance est déjà alignée sur `elapsedSeconds` (= position d'avant
    // le défi) — la nouvelle suite est rebasée sur cet instant et sera
    // consommée dès la fin du breath post-défi (qui est freezé, donc
    // ne décale pas elapsedSeconds).
    final breathEnd = elapsedSeconds;
    _session = SessionController.buildPostChallengeRegenSession(
      previous: _session,
      upcoming: upcomingSession,
      breathEnd: breathEnd,
    );

    _nextStepIndex = 0;
    _lastConfigStep = null;
    // `_checkSteps` sort tôt pendant tout le défi (`atSeuil` puis
    // `_inPostChallengeBreath`) : sans ce reset, le compteur de report reste
    // gelé à sa valeur d'avant le défi et la marge du premier step de la
    // suite régénérée serait plus courte que prévu.
    _ttsDeferredTicks = 0;
    // Reset de l'état break (issue #77), même raison que `requestUpgrade` :
    // la suite régénérée n'a pas de break, on évite un `_breakActive` coincé
    // et un gate de posture qui figerait la nouvelle suite.
    _breakActive = false;
    _activeBreak = null;
    _nextBreakIndex = 0;
    confirmPostureReady();
    // Reset du flag chime : la régen apporte son propre step final + apothéose.
    _finalChimePlayed = false;
    _finaleChimeStarted = false;

    _notify();
  }
}
