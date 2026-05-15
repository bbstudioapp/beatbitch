/// Profil anatomique du sujet de la session.
///
/// Permet à l'utilisatrice de désactiver des zones qui ne sont pas
/// disponibles dans son setup (ex. jouet sans testicules), pour éviter
/// que la coach demande des actions impossibles. Persisté via
/// [UserProfileService] (clés `profile.anatomy.*`).
///
/// Extensible : ajouter ici tout futur axe (canVibrate, canCum, type
/// de jouet, modèle partenaire…) au fur et à mesure. Le [copyWith]
/// permet aux call sites de modifier un seul champ sans toucher aux
/// autres.
///
/// Volontairement séparé de la progression / des stats : un toggle
/// anatomique est une préférence stable de la joueuse, pas un acquis
/// de carrière. Il n'est donc pas remis à zéro par le bouton ZONE
/// DANGER du Profil (qui wipe la progression).
class AnatomyProfile {
  /// Présence de testicules dans le setup. Si `false`, le générateur
  /// ne propose aucune action sur `Position.balls` (lick/hold/beg) et
  /// la 6ᵉ ligne du ladder visuel reste masquée même si la milestone
  /// d'unlock a été acquittée précédemment.
  final bool hasBalls;

  const AnatomyProfile({this.hasBalls = true});

  /// Profil par défaut : tout disponible. Utilisé en fallback quand
  /// aucune persistance n'est encore lue (ex. tests, mode hérité du
  /// générateur).
  static const AnatomyProfile defaults = AnatomyProfile();

  AnatomyProfile copyWith({bool? hasBalls}) =>
      AnatomyProfile(hasBalls: hasBalls ?? this.hasBalls);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnatomyProfile && other.hasBalls == hasBalls);

  @override
  int get hashCode => hasBalls.hashCode;
}
