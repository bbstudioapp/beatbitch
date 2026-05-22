import 'coach.dart';
import 'specialization.dart';

/// Catalogue figé des coachs livrés avec l'app. Ajouter un coach = ajouter
/// une entrée à `defaults` ; aucun autre code à toucher pour qu'il
/// apparaisse dans la liste de sélection.
///
/// Le contenu (bio + phrases) est volontairement minimal ici. Les phrases
/// sont chargées depuis `assets/career/coaches.json` par
/// `CoachPhrasesLoader`. Les bios peuvent être étoffées dans le même JSON
/// (clé `bio`) si besoin de les modifier sans recompilation.
class CoachCatalog {
  /// Dossier des portraits des coachs (ratio source 2:3). Co-localisé avec
  /// les JSON des coachs. Un coach peut surcharger ce chemin via la clé
  /// `portrait` de son `coach_<id>.json`.
  static const String _portraitDir = 'assets/career/coaches/portraits';

  static const List<Coach> defaults = [
    Coach(
      id: 'coach_01_lina',
      name: 'Lina',
      title: 'Coach découverte',
      archetype: CoachArchetype.bienveillant,
      publicBio:
          'Guide douce et patiente. Accompagne la mise en bouche, valide chaque progrès. '
          'Aucune insulte, aucune brusquerie : on prend le temps.',
      specialties: [
        SpecializationBranch.endurance,
        SpecializationBranch.profondeur,
      ],
      tier: 1,
      isPrincipal: true,
      portraitAsset: '$_portraitDir/coach_01_lina.png',
    ),
    Coach(
      id: 'coach_02_helene',
      name: 'Hélène',
      title: 'Coach exigeante',
      archetype: CoachArchetype.strict,
      publicBio:
          'Cadre net, posture droite, technique avant tout. Ne crie pas, '
          'mais ne laisse rien passer non plus.',
      specialties: [
        SpecializationBranch.profondeur,
        SpecializationBranch.obeissance,
      ],
      tier: 2,
      isPrincipal: true,
      // Phase 19.10 : 1h cumulée — ~2-3 séances.
      requirements: CoachRequirement(minPlayerSeconds: 3600),
      portraitAsset: '$_portraitDir/coach_02_helene.png',
    ),
    Coach(
      id: 'coach_03_jade',
      name: 'Jade',
      title: 'Coach taquine',
      archetype: CoachArchetype.taquinSadique,
      publicBio:
          'Joueuse, ironique, aime tester. Spécialiste des coups de queue '
          'et du sloppy. Mains obligatoires.',
      specialties: [
        SpecializationBranch.rythmeBiffle,
        SpecializationBranch.sloppy,
      ],
      tier: 3,
      isPrincipal: true,
      // Phase 19.10 : 3h cumulées. (Refonte 0.5.0 : `requiresHands` retiré
      // du coach — le hand obligatoire est désormais piloté par la milestone
      // planifiée, pas par le coach choisi.)
      requirements: CoachRequirement(minPlayerSeconds: 10800),
      portraitAsset: '$_portraitDir/coach_03_jade.png',
    ),
    Coach(
      id: 'coach_04_morgan',
      name: 'Morgan',
      title: 'Coach implacable',
      archetype: CoachArchetype.brutal,
      publicBio: 'Direct, frontal, sans détour. Travaille les pics longs '
          'et la profondeur sans concession.',
      specialties: [
        SpecializationBranch.profondeur,
        SpecializationBranch.endurance,
      ],
      tier: 4,
      isPrincipal: true,
      // Phase 19.10 : 7h cumulées.
      requirements: CoachRequirement(minPlayerSeconds: 25200),
      portraitAsset: '$_portraitDir/coach_04_morgan.png',
    ),
    Coach(
      id: 'coach_05_victoria',
      name: 'Victoria',
      title: 'Coach hautaine',
      archetype: CoachArchetype.hautain,
      publicBio: 'Distante, regard froid. Fait travailler la posture mentale '
          'autant que la technique.',
      specialties: [
        SpecializationBranch.obeissance,
        SpecializationBranch.endurance,
      ],
      tier: 5,
      isPrincipal: true,
      // Phase 19.10 : 15h cumulées.
      requirements: CoachRequirement(minPlayerSeconds: 54000),
      portraitAsset: '$_portraitDir/coach_05_victoria.png',
    ),
    Coach(
      id: 'coach_06_nyx',
      name: 'Nyx',
      title: 'Coach sans pitié',
      archetype: CoachArchetype.sansPitie,
      publicBio: 'Le palier final. N\'arrête pas, ne félicite pas. Pour celles '
          'qui ont déjà tout encaissé.',
      specialties: SpecializationBranch.values,
      tier: 6,
      isPrincipal: true,
      // Phase 19.10 : 25h cumulées — palier terminal.
      requirements: CoachRequirement(minPlayerSeconds: 90000),
      portraitAsset: '$_portraitDir/coach_06_nyx.png',
    ),
  ];
}

/// Validation de cohérence du catalogue de coachs. Appelée au boot par
/// `CoachService.attachPhrases` (ou à la main pour les tests).
///
/// Vérifie deux règles structurelles :
/// 1. Pour chaque palier observé (de 1 à max), il existe **exactement un
///    Principal**. Pas de trou (palier 2 absent), pas de doublon (deux
///    Principals pour le palier 3).
/// 2. Les `requirements.minPlayerSeconds` des Principals sont **strictement
///    croissants** dans l'ordre des paliers (le Principal du palier N+1
///    se débloque plus tard que celui du palier N).
///
/// Renvoie une liste de messages d'erreur lisibles. Vide = catalogue OK.
class CoachCatalogValidator {
  static List<String> validate(List<Coach> coaches) {
    final issues = <String>[];

    // 1. Recense les Principals par tier.
    final principalsByTier = <int, List<Coach>>{};
    for (final c in coaches) {
      if (!c.isPrincipal) continue;
      principalsByTier.putIfAbsent(c.tier, () => []).add(c);
    }

    if (principalsByTier.isEmpty) {
      issues.add('Aucun coach Principal défini.');
      return issues;
    }

    final maxTier = principalsByTier.keys.reduce((a, b) => a > b ? a : b);

    for (var t = 1; t <= maxTier; t++) {
      final list = principalsByTier[t];
      if (list == null || list.isEmpty) {
        issues.add('Palier $t : aucun Principal (séquence incomplète).');
      } else if (list.length > 1) {
        final ids = list.map((c) => c.id).join(', ');
        issues.add(
            'Palier $t : ${list.length} Principals ($ids) — un seul attendu.');
      }
    }

    // 2. Vérifie la croissance stricte des minPlayerSeconds sur les
    //    Principals des tiers consécutifs présents.
    int? previousMin;
    int? previousTier;
    for (var t = 1; t <= maxTier; t++) {
      final list = principalsByTier[t];
      if (list == null || list.length != 1) continue; // déjà flaggé
      final min = list.first.requirements.minPlayerSeconds;
      if (previousMin != null && min <= previousMin) {
        issues.add(
          'Palier $t (${list.first.id}) : minPlayerSeconds=$min ≤ '
          'palier $previousTier=$previousMin — doit être strictement supérieur.',
        );
      }
      previousMin = min;
      previousTier = t;
    }

    return issues;
  }
}
