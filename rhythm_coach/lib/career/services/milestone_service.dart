import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/capability_service.dart';
import '../../services/locale_service.dart';
import '../models/level_milestone.dart';
import '../models/milestone_text_override.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';
import 'milestone_loader.dart';
import 'unlock_announcements.dart';

/// Source de vérité pour les milestones de carrière. Persiste les
/// complétions (avec ou sans fail) dans `SharedPreferences`. Cf. E3 du plan.
///
/// Singleton : instancié dans `main.dart` après le chargement du catalogue.
class MilestoneService extends ChangeNotifier {
  static const String _kCompletions = 'career.milestones_completed';
  static const String _kRetries = 'career.milestone_retries';

  final MilestoneLoader _loader = MilestoneLoader();

  List<LevelMilestone> _catalog = const [];
  Set<String> _completed = <String>{};
  Map<String, int> _retries = <String, int>{};
  Map<String, MilestoneTextOverride> _overrides =
      <String, MilestoneTextOverride>{};
  bool _loaded = false;

  /// Unlocks « provisoires » valables uniquement pour la session en cours :
  /// ils permettent à l'UI (bouton Supplier) d'apparaître dès qu'une
  /// milestone qui débloque la compétence est insérée dans la séance,
  /// sans attendre le `markCompleted` qui n'arrive qu'à la fin. Reset à
  /// chaque démarrage de session via [setSessionUnlocks].
  Set<UnlockKey> _sessionUnlocks = <UnlockKey>{};

  /// Charge le catalogue + restaure les complétions persistées.
  /// Idempotent.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _catalog = await _loader.load();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCompletions);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          _completed = decoded.whereType<String>().toSet();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MilestoneService] parse error : $e');
        }
      }
    }
    final rawRetries = prefs.getString(_kRetries);
    if (rawRetries != null && rawRetries.isNotEmpty) {
      try {
        final decoded = json.decode(rawRetries);
        if (decoded is Map) {
          _retries =
              decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MilestoneService] retries parse error : $e');
        }
      }
    }
    await _loadOverrides();
    _loaded = true;
  }

  Future<void> _loadOverrides() async {
    final lang = LocaleService.instance.languageCode;
    final loaded = <String, MilestoneTextOverride>{};
    for (final m in _catalog) {
      final override = await _loader.loadOverride(m.id, lang);
      if (override != null) loaded[m.id] = override;
    }
    _overrides = loaded;
  }

  /// Recharge les overrides texte pour la locale active. À appeler après
  /// un changement de locale (cf. listener dans `main.dart`). No-op si le
  /// service n'a pas encore chargé son catalogue.
  Future<void> reloadLocaleOverrides() async {
    if (!_loaded) return;
    await _loadOverrides();
    notifyListeners();
  }

  /// Vrai si la milestone d'id [id] a été acquittée (sans fail).
  bool isCompleted(String id) => _completed.contains(id);

  /// Vrai si la compétence [key] a été débloquée par une milestone
  /// acquittée (et donc utilisable librement par le générateur), OU si
  /// la session courante contient une milestone qui la débloque (cf.
  /// [setSessionUnlocks]). Le second cas sert uniquement à l'UI : le
  /// générateur, lui, ne reçoit que les unlocks acquittés via
  /// [acquiredUnlockKeys].
  bool hasUnlock(UnlockKey key) {
    if (_sessionUnlocks.contains(key)) return true;
    for (final m in _catalog) {
      if (!_completed.contains(m.id)) continue;
      if (m.unlocks.contains(key)) return true;
    }
    return false;
  }

  /// Positionne les unlocks « provisoires » valables pendant la session
  /// courante (à appeler au démarrage de chaque session carrière, en
  /// passant les unlocks de la milestone insérée). À la fin de la
  /// session, appeler avec un set vide pour reset. NotifyListeners pour
  /// que l'UI (bouton Supplier) se mette à jour immédiatement.
  void setSessionUnlocks(Set<UnlockKey> keys) {
    final next = Set<UnlockKey>.of(keys);
    if (next.length == _sessionUnlocks.length &&
        next.containsAll(_sessionUnlocks)) {
      return;
    }
    _sessionUnlocks = next;
    notifyListeners();
  }

  /// Tolérance d'humiliation appliquée au seuil de candidature d'une
  /// milestone : `1 + obedience/50`. Plus l'utilisatrice obéit, plus on
  /// peut lui imposer une milestone légèrement au-dessus de son
  /// thermomètre courant. Plancher +1 garanti pour que les milestones à
  /// `humilRequired ≤ 1` (ex. `intro_basics`) soient jouables dès humil 0.
  static double humilTolerance(double obedience) {
    final ob = obedience < 0 ? 0.0 : obedience;
    return 1.0 + ob / 50.0;
  }

  /// Retourne la milestone **body** à insérer dans la prochaine session,
  /// éligible à l'humiliation [humiliationScore] modulée par l'obédiance
  /// [obedience]. Les milestones de placement `finalApotheose` sont
  /// exclues — elles ont leur propre canal via [pendingFinalFor].
  ///
  /// **Critères** :
  /// - `m.humilRequired ≤ humiliationScore + humilTolerance(obedience)`
  /// - `requires` tous acquittés
  /// - `requiresCapability` satisfait quand [capabilityProfile] est fourni
  ///   (sinon la couche télémétrie est neutralisée — mode hérité)
  /// - non encore acquittée
  ///
  /// **Tri** :
  /// 1. **Score de match spé** : somme des points investis dans
  ///    *chacune* des branches listées par le milestone, **descendant**.
  ///    Une milestone qui touche plusieurs branches investies passe donc
  ///    avant celle qui n'en touche qu'une.
  /// 2. **Équilibrage par branche basse** : à égalité de match,
  ///    favoriser les milestones dont la branche la moins investie chez
  ///    la joueuse est plus basse (variété, on n'empile pas dans le même
  ///    couloir). Pas appliqué si [allocation] est nul.
  /// 3. `humilRequired` **ascendant** (le palier le moins coûteux
  ///    d'abord, pour ne pas sauter de marche).
  /// 4. Tie-break final : id alphabétique (déterministe).
  LevelMilestone? pendingFor({
    required double humiliationScore,
    required double obedience,
    int playerLevel = 1,
    SpecializationAllocation? allocation,
    CapabilityProfile? capabilityProfile,
  }) {
    final all = allPendingFor(
      humiliationScore: humiliationScore,
      obedience: obedience,
      playerLevel: playerLevel,
      allocation: allocation,
      capabilityProfile: capabilityProfile,
    );
    return all.isEmpty ? null : all.first;
  }

  /// Sélectionne jusqu'à [count] milestones **body** distinctes pour la
  /// même séance. Pour chaque pick, retire la candidate du pool et marque
  /// ses `unlocks` comme acquis simulés afin d'exclure :
  ///
  /// - les doublons (une milestone ne peut être insérée deux fois),
  /// - les milestones dont `requires` inclut un unlock d'une milestone
  ///   déjà pickée dans la même session (sinon on triche sur l'ordre
  ///   pédagogique : la 2ᵉ ne pourrait être jouée qu'APRÈS l'acquittement
  ///   de la 1ʳᵉ, ce qui n'arrive qu'à la fin de la séance).
  ///
  /// Retombe gracieusement à moins de [count] (voire `[]`) si le pool
  /// est insuffisant — le générateur saura adapter l'insertion.
  List<LevelMilestone> pendingForList({
    required int count,
    required double humiliationScore,
    required double obedience,
    int playerLevel = 1,
    SpecializationAllocation? allocation,
    CapabilityProfile? capabilityProfile,
  }) {
    if (count <= 0) return const [];
    final picked = <LevelMilestone>[];
    final simulatedUnlocks = <UnlockKey>{};
    final pickedIds = <String>{};
    for (var i = 0; i < count; i++) {
      final candidates = allPendingFor(
        humiliationScore: humiliationScore,
        obedience: obedience,
        playerLevel: playerLevel,
        allocation: allocation,
        capabilityProfile: capabilityProfile,
      );
      LevelMilestone? next;
      for (final m in candidates) {
        if (pickedIds.contains(m.id)) continue;
        // Exclusion mutuelle : m dépend d'un unlock que la milestone
        // précédemment pickée vient d'apporter → forcerait un ordre
        // pédagogique strict dans la même séance.
        if (m.requires.any(simulatedUnlocks.contains)) continue;
        next = m;
        break;
      }
      if (next == null) break;
      picked.add(next);
      pickedIds.add(next.id);
      simulatedUnlocks.addAll(next.unlocks);
    }
    return picked;
  }

  /// Variante de [pendingFor] pour les milestones de placement
  /// `finalApotheose`. Une session peut donc jouer **une body + une
  /// final** sur la même séance. Retourne `null` si aucun candidat.
  LevelMilestone? pendingFinalFor({
    required double humiliationScore,
    required double obedience,
    int playerLevel = 1,
    SpecializationAllocation? allocation,
    CapabilityProfile? capabilityProfile,
  }) {
    final all = allPendingFor(
      humiliationScore: humiliationScore,
      obedience: obedience,
      playerLevel: playerLevel,
      allocation: allocation,
      capabilityProfile: capabilityProfile,
      placement: MilestonePlacement.finalApotheose,
    );
    return all.isEmpty ? null : all.first;
  }

  /// Toutes les milestones pending éligibles à `humiliationScore` +
  /// tolérance d'obédiance, gated par `playerLevel ≥ minLevel` et par
  /// `requiresCapability` (si [capabilityProfile] est fourni). Triées
  /// selon les mêmes critères que `pendingFor`. La première de la liste
  /// est celle qui sera effectivement insérée dans la prochaine session
  /// générée. Liste vide si aucune candidate.
  List<LevelMilestone> allPendingFor({
    required double humiliationScore,
    required double obedience,
    int playerLevel = 1,
    SpecializationAllocation? allocation,
    CapabilityProfile? capabilityProfile,
    MilestonePlacement placement = MilestonePlacement.body,
  }) {
    final cap = humiliationScore + humilTolerance(obedience);

    /// Score de tri : **somme** des points investis dans toutes les
    /// branches listées par le milestone. Permet de prioriser une
    /// milestone qui couvre plusieurs spés choisies par rapport à une
    /// qui n'en couvre qu'une (ex: profondeur=2 + endurance=2 →
    /// `intro_hold_throat_short` (branches=[endurance, profondeur],
    /// score=4) passe avant `intro_hold_mid` (branches=[endurance],
    /// score=2)).
    int branchScore(LevelMilestone m) {
      if (allocation == null || m.branches.isEmpty) return 0;
      var sum = 0;
      for (final b in m.branches) {
        sum += allocation.pointsIn(b);
      }
      return sum;
    }

    /// Niveau d'avance accordé par la spé : 1 niveau par point investi
    /// dans la **branche la plus investie** parmi celles du milestone,
    /// capé à 3. Permet à une joueuse spé profondeur 3 pts d'accéder à
    /// `intro_throat_pulse` (level 10) dès le niveau 7. On garde le
    /// **max** ici (pas la somme) : c'est la maîtrise sur une branche
    /// qui débloque la compétence en avance, pas la dispersion.
    int branchAdvance(LevelMilestone m) {
      if (allocation == null || m.branches.isEmpty) return 0;
      var best = 0;
      for (final b in m.branches) {
        final pts = allocation.pointsIn(b);
        if (pts > best) best = pts;
      }
      return best.clamp(0, 3);
    }

    /// Points investis dans la **branche la moins investie** d'un
    /// milestone (ou 0 si transverse / pas d'allocation). Sert au
    /// tie-break « équilibrage » : à égalité de match, favoriser les
    /// milestones dont la branche la moins investie chez la joueuse est
    /// la plus basse — un coup de pouce vers la variété, pas un
    /// raz-de-marée. Pour `intro_hold_throat_short` (`endurance` +
    /// `profondeur`) avec profondeur=0, endurance=2 → renvoie 0, donc
    /// passe avant une milestone mono-branche endurance=2.
    int lowestBranchPoints(LevelMilestone m) {
      if (allocation == null || m.branches.isEmpty) return 0;
      var lo = 1 << 30;
      for (final b in m.branches) {
        final pts = allocation.pointsIn(b);
        if (pts < lo) lo = pts;
      }
      return lo == (1 << 30) ? 0 : lo;
    }

    bool capabilityOk(LevelMilestone m) {
      if (m.requiresCapability.isEmpty) return true;
      // Pas de profil fourni : mode hérité (tests, sessions hors carrière).
      // On neutralise le gating capacité — humil/level prennent le relais.
      if (capabilityProfile == null) return true;
      for (final req in m.requiresCapability) {
        if (!req.isSatisfiedBy(capabilityProfile)) return false;
      }
      return true;
    }

    final candidates = _catalog
        .where((m) => m.placement == placement)
        .where((m) => (m.minLevel - branchAdvance(m)) <= playerLevel)
        .where((m) => m.humilRequired <= cap)
        .where((m) => !_completed.contains(m.id))
        .where((m) => m.requires.every(hasUnlock))
        .where(capabilityOk)
        .toList();
    if (candidates.isEmpty) return const [];
    candidates.sort((a, b) {
      final byBranch = branchScore(b).compareTo(branchScore(a));
      if (byBranch != 0) return byBranch;
      // À match spé égal : favoriser la branche la moins investie chez la
      // joueuse (variété). N'a d'effet que si une allocation est fournie.
      final byLow = lowestBranchPoints(a).compareTo(lowestBranchPoints(b));
      if (byLow != 0) return byLow;
      final byHumil = a.humilRequired.compareTo(b.humilRequired);
      if (byHumil != 0) return byHumil;
      return a.id.compareTo(b.id);
    });
    return candidates;
  }

  /// Set des `UnlockKey` accordés par TOUTES les milestones complétées.
  /// Utilisé par le générateur pour gater les actions.
  Set<UnlockKey> acquiredUnlockKeys() {
    final out = <UnlockKey>{};
    for (final m in _catalog) {
      if (_completed.contains(m.id)) {
        out.addAll(m.unlocks);
      }
    }
    return out;
  }

  /// Phrase d'unlock à jouer en TTS après le finale_chime, si la milestone
  /// vient d'être acquittée. Priorité : override texte de la milestone, puis
  /// annonce par défaut basée sur le 1er unlock (cf. [defaultAnnouncementFor])
  /// quand [l10n] est fourni. `null` si rien à dire (milestone sans override
  /// dont l'unlock principal n'a pas d'effet « invisible » à annoncer).
  String? getUnlockAnnouncement(String id, {AppLocalizations? l10n}) {
    final override = _overrides[id]?.unlockAnnouncement;
    if (override != null && override.isNotEmpty) return override;
    if (l10n == null) return null;
    final m = findById(id);
    if (m == null || m.unlocks.isEmpty) return null;
    return defaultAnnouncementFor(m.unlocks.first, l10n);
  }

  /// Texte localisé pour le step à offset [time] dans la milestone [id].
  /// `null` si pas de surcharge → l'appelant garde le texte d'origine.
  String? getStepText(String id, int time) => _overrides[id]?.textForTime(time);

  /// Libellé court localisé pour la milestone [id]. Retourne le
  /// `displayLabel` du catalogue principal (FR) si l'override de la
  /// locale active n'en fournit pas un.
  String getDisplayLabel(String id) {
    final override = _overrides[id]?.displayLabel;
    if (override != null && override.isNotEmpty) return override;
    return findById(id)?.displayLabel ?? id;
  }

  /// Compteur de retries cumulés pour la milestone [id].
  int getRetryCount(String id) => _retries[id] ?? 0;

  /// Incrémente le compteur de retries de [id]. Persiste.
  Future<void> incrementRetryCount(String id) async {
    _retries[id] = (_retries[id] ?? 0) + 1;
    await _persistRetries();
  }

  /// Remet à zéro le compteur de retries de [id]. Persiste.
  Future<void> resetRetryCount(String id) async {
    if (_retries.remove(id) != null) {
      await _persistRetries();
    }
  }

  /// Marque la milestone comme acquittée si pas de fail. Persiste.
  /// Notifie les listeners (utile pour rafraîchir UI).
  Future<void> markCompleted(String id, {required bool hadFail}) async {
    if (hadFail) return; // pas de markCompleted si fail
    if (_completed.add(id)) {
      await _persist();
      await resetRetryCount(id);
      notifyListeners();
    }
  }

  /// Cherche dans le catalogue la milestone d'id [id].
  LevelMilestone? findById(String id) {
    for (final m in _catalog) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Injecte un catalogue + un set de complétions sans passer par le
  /// loader d'assets ni `SharedPreferences`. Réservé aux tests unitaires
  /// du tri de `pendingFor`.
  @visibleForTesting
  void seedForTest({
    required List<LevelMilestone> catalog,
    Set<String> completed = const <String>{},
  }) {
    _catalog = List<LevelMilestone>.unmodifiable(catalog);
    _completed = Set<String>.from(completed);
    _loaded = true;
  }

  /// Efface toutes les complétions persistées. Appelé par le bouton
  /// « tout remettre à zéro » du ProfileScreen.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCompletions);
    await prefs.remove(_kRetries);
    _completed = <String>{};
    _retries = <String, int>{};
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCompletions, json.encode(_completed.toList()));
  }

  Future<void> _persistRetries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRetries, json.encode(_retries));
  }
}
