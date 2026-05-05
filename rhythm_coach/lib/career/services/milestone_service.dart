import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/session.dart';
import '../../services/humiliation_engine.dart';
import '../../services/locale_service.dart';
import '../models/level_milestone.dart';
import '../models/milestone_text_override.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';
import 'milestone_loader.dart';

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
          _retries = decoded
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
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

  /// Retourne la milestone **body** à insérer dans la prochaine session
  /// de [level]. Les milestones de placement `finalApotheose` sont
  /// exclues — elles ont leur propre canal via [pendingFinalForLevel].
  /// Critères : `m.level <= level` (on rattrape les milestones non acquittées
  /// d'anciens niveaux), `requires` tous acquittés, non encore acquittée.
  ///
  /// **Tri** :
  /// 1. Points investis dans la branche du milestone, **descendant** —
  ///    on priorise ce qui aligne avec la spé du joueur. Milestone sans
  ///    branche (transverse) = score 0.
  /// 2. À égalité : humiliation maximale requise par la séquence,
  ///    **ascendante** — on prend le palier accessible le moins coûteux
  ///    pour ne pas sauter de marche.
  /// 3. Tie-break final : numéro de niveau croissant.
  ///
  /// Si [allocation] est null, on retombe sur l'ancien comportement
  /// (tri par niveau croissant uniquement) — utile pour les tests / les
  /// appels qui n'ont pas accès aux points.
  LevelMilestone? pendingForLevel(
    int level, {
    SpecializationAllocation? allocation,
  }) {
    final all = allPendingForLevel(level, allocation: allocation);
    return all.isEmpty ? null : all.first;
  }

  /// Variante de [pendingForLevel] dédiée aux milestones de placement
  /// `finalApotheose`. Une session peut donc en jouer **une body + une
  /// final** sur la même séance. Critères et tri identiques. Retourne
  /// `null` si aucun candidat.
  LevelMilestone? pendingFinalForLevel(
    int level, {
    SpecializationAllocation? allocation,
  }) {
    final all = allPendingForLevel(
      level,
      allocation: allocation,
      placement: MilestonePlacement.finalApotheose,
    );
    return all.isEmpty ? null : all.first;
  }

  /// Toutes les milestones pending pour [level], triées selon les mêmes
  /// critères que `pendingForLevel`. La première de la liste est celle
  /// qui sera effectivement insérée dans la prochaine session générée.
  /// Liste vide si aucune candidate. [placement] filtre par placement
  /// (default `body` pour préserver la sémantique historique : les
  /// appelants existants ne voient que les milestones de corps).
  List<LevelMilestone> allPendingForLevel(
    int level, {
    SpecializationAllocation? allocation,
    MilestonePlacement placement = MilestonePlacement.body,
  }) {
    final candidates = _catalog
        .where((m) => m.placement == placement)
        .where((m) => m.level <= level)
        .where((m) => !_completed.contains(m.id))
        .where((m) => m.requires.every(hasUnlock))
        .toList();
    if (candidates.isEmpty) return const [];
    if (allocation == null) {
      candidates.sort((a, b) => a.level.compareTo(b.level));
      return candidates;
    }
    int branchPoints(LevelMilestone m) {
      if (m.branches.isEmpty) return 0;
      var best = 0;
      for (final b in m.branches) {
        final pts = allocation.pointsIn(b);
        if (pts > best) best = pts;
      }
      return best;
    }
    candidates.sort((a, b) {
      final byBranch = branchPoints(b).compareTo(branchPoints(a));
      if (byBranch != 0) return byBranch;
      final byHumil = _humilFor(a).compareTo(_humilFor(b));
      if (byHumil != 0) return byHumil;
      return a.level.compareTo(b.level);
    });
    return candidates;
  }

  /// Humiliation max requise par un step de la séquence — sert à ranger
  /// les milestones de difficulté équivalente (mêmes points spé) du moins
  /// au plus exigeant. Cache trivial par id pour ne pas recalculer.
  final Map<String, double> _humilCache = <String, double>{};
  double _humilFor(LevelMilestone m) {
    final cached = _humilCache[m.id];
    if (cached != null) return cached;
    var maxReq = 0.0;
    for (final s in m.sequence) {
      final mode = s.mode ?? SessionMode.rhythm;
      final r = HumiliationScale.requiredFor(
        mode: mode,
        from: s.from,
        to: s.to,
        bpm: s.bpm,
        duration: s.duration,
      );
      if (r > maxReq) maxReq = r;
    }
    _humilCache[m.id] = maxReq;
    return maxReq;
  }

  /// Vrai si au moins une milestone de niveau exactement [level] a été
  /// acquittée. Utilisé par `CareerProgressService.canLevelUp` pour
  /// exiger qu'au moins une des milestones du niveau courant soit
  /// validée avant de passer au suivant.
  bool hasAnyCompletedAtLevel(int level) {
    for (final m in _catalog) {
      if (m.level == level && _completed.contains(m.id)) return true;
    }
    return false;
  }

  /// Vrai si le catalogue contient au moins une milestone de niveau
  /// exactement [level]. Si `false`, `canLevelUp` ne bloque pas (rien
  /// à acquitter à ce niveau).
  bool hasAnyAtLevel(int level) {
    for (final m in _catalog) {
      if (m.level == level) return true;
    }
    return false;
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
  /// vient d'être acquittée. `null` si pas de surcharge ou de phrase.
  String? getUnlockAnnouncement(String id) =>
      _overrides[id]?.unlockAnnouncement;

  /// Texte localisé pour le step à offset [time] dans la milestone [id].
  /// `null` si pas de surcharge → l'appelant garde le texte d'origine.
  String? getStepText(String id, int time) =>
      _overrides[id]?.textForTime(time);

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
  /// du tri de `pendingForLevel`.
  @visibleForTesting
  void seedForTest({
    required List<LevelMilestone> catalog,
    Set<String> completed = const <String>{},
  }) {
    _catalog = List<LevelMilestone>.unmodifiable(catalog);
    _completed = Set<String>.from(completed);
    _humilCache.clear();
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
