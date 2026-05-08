import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/coach.dart';
import '../models/coach_catalog.dart';
import '../models/specialization.dart';

/// Résultat d'une demande de sélection de coach.
enum CoachSelectionStatus {
  /// Le coach a été sélectionné, c'est le Principal du palier courant —
  /// la session avancera le palier.
  selectedAdvancing,

  /// Le coach a été sélectionné mais ce n'est pas le Principal du palier
  /// courant — la session ne fera pas progresser le palier (entraînement
  /// libre). L'UI doit avoir affiché un avertissement avant.
  selectedFreeTraining,

  /// Coach pas encore débloqué (palier supérieur au palier courant).
  lockedTier,

  /// Le coach a une contrainte de mains et le toggle « inclure la main »
  /// est désactivé.
  blockedRequiresHands,

  /// Le niveau global du joueur est en-dessous du `minPlayerLevel` requis
  /// par le coach.
  blockedMinLevel,

  /// Le coach demande une branche de spécialisation non investie
  /// (au moins 1 point requis via `mustHaveUnlockedBranches`).
  blockedMissingSpecialization,

  /// Le coach demande un seuil de points dans une branche, non atteint
  /// (via `requiredBranchPoints`).
  blockedInsufficientBranchPoints,
}

/// Source de vérité pour : palier courant, coach sélectionné, set des
/// coachs débloqués. Persiste dans `SharedPreferences`.
///
/// Le palier courant n'est PAS recalculé en boucle depuis le `maxLevel` :
/// `syncFromCareerLevel(maxLevel)` doit être appelé après chaque mise à
/// jour du niveau global. Ça évite que le service dépende directement de
/// `CareerProgressService` (boucle d'imports + couplage temporel).
class CoachService extends ChangeNotifier {
  static const String _kCurrentTier = 'coach.current_tier';
  static const String _kSelectedId = 'coach.selected_id';
  static const String _kUnlockedIds = 'coach.unlocked_ids';

  List<Coach> _coaches;

  int _currentTier = 1;
  String? _selectedCoachId;
  Set<String> _unlockedIds = <String>{};
  bool _loaded = false;

  CoachService({List<Coach>? coaches})
      : _coaches = List.unmodifiable(coaches ?? CoachCatalog.defaults);

  /// Remplace la liste interne par [coaches]. Sert au bootstrap pour
  /// injecter les coachs avec leurs phrases chargées (`CoachLoader.load()`).
  /// La liste fournie doit avoir les **mêmes ids** que le catalogue de base ;
  /// sinon les ids persistés dans `selectedCoachId` / `_unlockedIds`
  /// pourraient être désynchronisés.
  ///
  /// Valide la cohérence du catalogue final (tiers complets, minPlayerLevel
  /// strictement croissants). En debug : `assert` qui pète pour attraper les
  /// erreurs côté dev. En release : log warning et continue.
  void attachPhrases(List<Coach> coaches) {
    final issues = CoachCatalogValidator.validate(coaches);
    if (issues.isNotEmpty) {
      if (kDebugMode) {
        for (final i in issues) {
          debugPrint('[CoachService] catalogue incohérent : $i');
        }
      }
      assert(issues.isEmpty,
          'Catalogue de coachs incohérent :\n  - ${issues.join("\n  - ")}');
    }
    _coaches = List.unmodifiable(coaches);
    notifyListeners();
  }

  // ---- Lecture publique --------------------------------------------------

  /// Catalogue immuable des coachs disponibles dans cette installation.
  List<Coach> get coaches => _coaches;

  int get currentTier => _currentTier;

  String? get selectedCoachId => _selectedCoachId;

  Coach? get selectedCoach {
    if (_selectedCoachId == null) return null;
    for (final c in _coaches) {
      if (c.id == _selectedCoachId) return c;
    }
    return null;
  }

  bool isUnlocked(Coach c) => _unlockedIds.contains(c.id);

  /// Coach Principal d'un palier donné (un seul attendu par palier).
  /// Renvoie null si aucun n'est marqué Principal pour ce palier (cas
  /// pathologique : catalogue mal défini).
  Coach? principalOfTier(int tier) {
    for (final c in _coaches) {
      if (c.tier == tier && c.isPrincipal) return c;
    }
    return null;
  }

  Coach? get currentTierPrincipal => principalOfTier(_currentTier);

  /// Vrai si la session menée avec [c] fait progresser le palier.
  /// C'est-à-dire : Principal **et** palier == palier courant. Les coachs
  /// principaux des paliers inférieurs ne font plus progresser.
  bool advancesTier(Coach c) => c.isPrincipal && c.tier == _currentTier;

  // ---- Persistance / cycle de vie ---------------------------------------

  /// À appeler une fois au bootstrap. Idempotent.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _currentTier = prefs.getInt(_kCurrentTier) ?? 1;
    _selectedCoachId = prefs.getString(_kSelectedId);
    final list = prefs.getStringList(_kUnlockedIds);
    _unlockedIds = list != null ? list.toSet() : _initialUnlocked();
    // Garde-fou : on garantit que le Principal du palier courant est
    // toujours débloqué (cas d'un upgrade d'app qui aurait ajouté un
    // coach manquant au set persisté).
    _ensureCurrentTierPrincipalUnlocked();
    // Si la sélection persistée pointe sur un coach qui n'existe plus
    // (renommé, retiré), on la nettoie pour ne pas afficher du vide.
    if (_selectedCoachId != null && selectedCoach == null) {
      _selectedCoachId = null;
    }
    _loaded = true;
    notifyListeners();
  }

  Set<String> _initialUnlocked() {
    final s = <String>{};
    final p = principalOfTier(1);
    if (p != null) s.add(p.id);
    return s;
  }

  void _ensureCurrentTierPrincipalUnlocked() {
    final p = currentTierPrincipal;
    if (p != null) _unlockedIds.add(p.id);
  }

  /// Calcule le tier maximal atteint pour un `maxLevel` donné en se basant
  /// sur les `requirements.minPlayerLevel` des Principals chargés. Source
  /// de vérité unique : pas de mapping niveau→tier hardcodé ailleurs.
  int _maxReachableTier(int maxLevel) {
    var best = 0;
    for (final c in _coaches) {
      if (!c.isPrincipal) continue;
      if (c.requirements.minPlayerLevel <= maxLevel && c.tier > best) {
        best = c.tier;
      }
    }
    // Au pire (catalogue vide ou minPlayerLevel > maxLevel partout), on
    // reste au tier 1 par convention — le Principal du tier 1 doit toujours
    // être atteignable au démarrage (validé par CoachCatalogValidator).
    return best == 0 ? 1 : best;
  }

  /// À appeler après un level-up (ou au bootstrap après chargement du
  /// niveau max) avec le `maxLevel` global du joueur. Met à jour le
  /// palier courant si le seuil du palier suivant est atteint, et
  /// débloque automatiquement le Principal du nouveau palier.
  ///
  /// Renvoie la liste des coachs nouvellement débloqués lors de cet appel
  /// (utile pour afficher un toast / lire une annonce TTS).
  Future<List<Coach>> syncFromCareerLevel(int maxLevel) async {
    final reachedTier = _maxReachableTier(maxLevel);
    if (reachedTier <= _currentTier) return const [];

    final newlyUnlocked = <Coach>[];
    for (var t = _currentTier + 1; t <= reachedTier; t++) {
      final p = principalOfTier(t);
      if (p != null && _unlockedIds.add(p.id)) {
        newlyUnlocked.add(p);
      }
    }
    _currentTier = reachedTier;
    await _persist();
    notifyListeners();
    return newlyUnlocked;
  }

  /// Évalue si un coach peut être sélectionné selon les contraintes
  /// (palier débloqué + requirements). Ne tient PAS compte du fait que
  /// ce soit le Principal — c'est l'appelant qui décide d'avertir
  /// l'utilisateur avant de confirmer la sélection d'un coach
  /// non-Principal.
  ///
  /// [branchPoints] : points investis par branche. Sert aux deux checks
  /// `mustHaveUnlockedBranches` (>= 1) et `requiredBranchPoints` (seuils).
  CoachSelectionStatus evaluate(
    Coach c, {
    required int playerMaxLevel,
    required bool handsEnabled,
    required Map<SpecializationBranch, int> branchPoints,
  }) {
    if (!isUnlocked(c)) return CoachSelectionStatus.lockedTier;
    if (c.requirements.requiresHands && !handsEnabled) {
      return CoachSelectionStatus.blockedRequiresHands;
    }
    if (playerMaxLevel < c.requirements.minPlayerLevel) {
      return CoachSelectionStatus.blockedMinLevel;
    }
    for (final b in c.requirements.mustHaveUnlockedBranches) {
      if ((branchPoints[b] ?? 0) < 1) {
        return CoachSelectionStatus.blockedMissingSpecialization;
      }
    }
    for (final entry in c.requirements.requiredBranchPoints.entries) {
      if ((branchPoints[entry.key] ?? 0) < entry.value) {
        return CoachSelectionStatus.blockedInsufficientBranchPoints;
      }
    }
    return advancesTier(c)
        ? CoachSelectionStatus.selectedAdvancing
        : CoachSelectionStatus.selectedFreeTraining;
  }

  /// Persiste la sélection. À n'appeler qu'après une `evaluate` retournant
  /// un statut "selected*". Pas de re-validation ici : c'est à l'écran de
  /// décider de l'avertissement avant de confirmer.
  Future<void> selectCoach(Coach c) async {
    if (_selectedCoachId == c.id) return;
    _selectedCoachId = c.id;
    await _persist();
    notifyListeners();
  }

  /// Efface palier courant, coach sélectionné et set débloqué. Appelé par
  /// le bouton « tout remettre à zéro » du ProfileScreen.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentTier);
    await prefs.remove(_kSelectedId);
    await prefs.remove(_kUnlockedIds);
    _currentTier = 1;
    _selectedCoachId = null;
    _unlockedIds = _initialUnlocked();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCurrentTier, _currentTier);
    if (_selectedCoachId == null) {
      await prefs.remove(_kSelectedId);
    } else {
      await prefs.setString(_kSelectedId, _selectedCoachId!);
    }
    await prefs.setStringList(_kUnlockedIds, _unlockedIds.toList());
  }
}
