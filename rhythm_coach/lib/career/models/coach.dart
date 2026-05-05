import 'dart:math';

import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/random_comments_loader.dart';
import 'phrase_bank.dart';
import 'specialization.dart';

/// Archétypes de coachs. Chaque archétype incarne un ton et une posture
/// distincts. Ajouter un nouvel archétype ici n'impacte pas la logique
/// de progression : le `CoachService` raisonne sur `tier` + `isPrincipal`,
/// pas sur l'archétype.
enum CoachArchetype {
  bienveillant,
  strict,
  taquinSadique,
  brutal,
  hautain,
  sansPitie,
}

/// Contraintes optionnelles pour autoriser la sélection d'un coach.
/// Évaluées par `CoachService.evaluate` à chaque demande.
class CoachRequirement {
  /// Si true, le coach n'est sélectionnable que si le toggle « inclure la
  /// stimulation main » est actif côté `CareerProgressService`.
  /// Cas typique : coach axé biffle.
  final bool requiresHands;

  /// Branches de spécialisation devant avoir au moins 1 point investi.
  /// Vide = pas de prérequis. Check binaire (présence) : pour exiger un
  /// nombre de points spécifique, utiliser [requiredBranchPoints].
  final List<SpecializationBranch> mustHaveUnlockedBranches;

  /// Seuils de points requis par branche. Ex: `{ profondeur: 3 }` =
  /// "au moins 3 points investis dans profondeur". Permet de débloquer
  /// un coach uniquement quand le joueur a réellement investi dans une
  /// spécialité (et pas juste effleuré 1 point).
  ///
  /// Sémantique : **toutes** les branches listées doivent atteindre leur
  /// seuil (AND, pas OR). Si une branche apparaît à la fois ici et dans
  /// `mustHaveUnlockedBranches`, le seuil le plus strict (= celui d'ici)
  /// fait foi.
  final Map<SpecializationBranch, int> requiredBranchPoints;

  /// Niveau global minimum du joueur (CareerLevel) pour autoriser ce
  /// coach. Permet d'ajouter des coachs annexes débloqués à un niveau
  /// précis sans toucher au système de palier principal.
  final int minPlayerLevel;

  const CoachRequirement({
    this.requiresHands = false,
    this.mustHaveUnlockedBranches = const [],
    this.requiredBranchPoints = const {},
    this.minPlayerLevel = 1,
  });

  static const CoachRequirement none = CoachRequirement();

  /// Désérialise un objet JSON :
  /// ```jsonc
  /// {
  ///   "requiresHands": false,
  ///   "minPlayerLevel": 1,
  ///   "mustHaveUnlockedBranches": ["profondeur"],
  ///   "requiredBranchPoints": { "resilience": 3, "profondeur": 2 }
  /// }
  /// ```
  /// Toute clé absente garde sa valeur par défaut. Les noms de branches
  /// inconnus sont ignorés silencieusement.
  factory CoachRequirement.fromJson(Map<String, dynamic> json) {
    SpecializationBranch? parseBranch(String name) {
      for (final b in SpecializationBranch.values) {
        if (b.name == name) return b;
      }
      return null;
    }

    final branchesNode = json['mustHaveUnlockedBranches'];
    final branches = <SpecializationBranch>[];
    if (branchesNode is List) {
      for (final raw in branchesNode) {
        final b = parseBranch(raw?.toString() ?? '');
        if (b != null) branches.add(b);
      }
    }

    final pointsNode = json['requiredBranchPoints'];
    final points = <SpecializationBranch, int>{};
    if (pointsNode is Map<String, dynamic>) {
      pointsNode.forEach((key, value) {
        final b = parseBranch(key);
        final n = (value as num?)?.toInt();
        if (b != null && n != null && n > 0) points[b] = n;
      });
    }

    return CoachRequirement(
      requiresHands: json['requiresHands'] == true,
      minPlayerLevel: (json['minPlayerLevel'] as num?)?.toInt() ?? 1,
      mustHaveUnlockedBranches: branches,
      requiredBranchPoints: points,
    );
  }
}

/// Préférences gameplay d'un coach, **indépendantes de la langue**.
/// Sérialisées dans `assets/career/coaches/<id>.json` (sans suffixe lang).
///
/// Tous les champs sont **optionnels** : null = garde la valeur par défaut
/// codée dans `CoachCatalog.defaults`. Ça permet de n'overrider qu'un sous-
/// ensemble (ex: changer juste le tier d'un coach) sans tout redéclarer.
class CoachMeta {
  final String? name;
  final CoachArchetype? archetype;
  final List<SpecializationBranch>? specialties;
  final int? tier;
  final bool? isPrincipal;
  final CoachRequirement? requirements;

  /// Préférences gameplay du coach : multiplicateur appliqué au poids
  /// de tirage de chaque mode (cf. `_modeWeight` dans le générateur).
  /// Valeurs entre 0.0 (« jamais ») et 2.0 (« doublé »). 1.0 = neutre.
  /// Mode absent = 1.0. Combiné multiplicativement avec les bonus de
  /// spécialisation. Null = aucun override.
  final Map<SessionMode, double>? modeWeights;

  const CoachMeta({
    this.name,
    this.archetype,
    this.specialties,
    this.tier,
    this.isPrincipal,
    this.requirements,
    this.modeWeights,
  });

  static const CoachMeta empty = CoachMeta();

  bool get isEmpty =>
      name == null &&
      archetype == null &&
      specialties == null &&
      tier == null &&
      isPrincipal == null &&
      requirements == null &&
      modeWeights == null;

  /// Désérialise depuis un JSON top-level :
  /// ```jsonc
  /// {
  ///   "id": "coach_xx",          // ignoré ici (résolu par nom de fichier)
  ///   "name": "...",
  ///   "archetype": "bienveillant",
  ///   "specialties": ["endurance", "profondeur"],
  ///   "tier": 1,
  ///   "isPrincipal": true,
  ///   "requirements": { "requiresHands": false, "minPlayerLevel": 1 }
  /// }
  /// ```
  /// Tout champ absent est laissé null.
  factory CoachMeta.fromJson(Map<String, dynamic> json) {
    CoachArchetype? archetype;
    final archetypeName = json['archetype']?.toString();
    if (archetypeName != null) {
      for (final a in CoachArchetype.values) {
        if (a.name == archetypeName) {
          archetype = a;
          break;
        }
      }
    }

    List<SpecializationBranch>? specialties;
    final spNode = json['specialties'];
    if (spNode is List) {
      specialties = [];
      for (final raw in spNode) {
        final name = raw?.toString();
        if (name == null) continue;
        for (final b in SpecializationBranch.values) {
          if (b.name == name) {
            specialties.add(b);
            break;
          }
        }
      }
    }

    final reqNode = json['requirements'];
    final requirements = reqNode is Map<String, dynamic>
        ? CoachRequirement.fromJson(reqNode)
        : null;

    Map<SessionMode, double>? modeWeights;
    final mwNode = json['modeWeights'];
    if (mwNode is Map<String, dynamic>) {
      // SessionMode.fromString fallback est `rhythm` — on ne veut pas
      // qu'une clé inconnue écrase silencieusement le poids de rhythm.
      // On filtre donc sur les noms d'enum exacts.
      final validNames = {
        for (final m in SessionMode.values) m.name: m,
      };
      modeWeights = <SessionMode, double>{};
      mwNode.forEach((key, value) {
        final mode = validNames[key.toLowerCase()];
        final weight = (value as num?)?.toDouble();
        if (mode != null && weight != null && weight >= 0) {
          modeWeights![mode] = weight;
        }
      });
      if (modeWeights.isEmpty) modeWeights = null;
    }

    final rawName = json['name']?.toString().trim();

    return CoachMeta(
      name: (rawName != null && rawName.isNotEmpty) ? rawName : null,
      archetype: archetype,
      specialties: specialties,
      tier: (json['tier'] as num?)?.toInt(),
      isPrincipal: json['isPrincipal'] is bool
          ? json['isPrincipal'] as bool
          : null,
      requirements: requirements,
      modeWeights: modeWeights,
    );
  }
}

/// Pool de surnoms qu'un coach utilise pour substituer `{name}` dans
/// ses phrases. Trois leviers :
///
/// - [pool] : surnoms propres au coach (toujours utilisés s'ils existent).
/// - [useUserPrenom] : si true, le prénom user (`UserProfileService.prenom`)
///   est ajouté au pool. Pratique pour les coachs gentils qui appellent
///   l'utilisatrice par son prénom.
/// - [useUserNicknames] : si true, fusionne aussi les surnoms user (defaults
///   activés + customs). Utile quand on veut de la variété en complément
///   du pool coach.
///
/// Si rien n'est défini (pool vide + flags false), [Coach.pickName] retombe
/// sur le pool user complet — comportement historique préservé.
class CoachNicknamePool {
  final List<String> pool;
  final bool useUserPrenom;
  final bool useUserNicknames;

  const CoachNicknamePool({
    this.pool = const [],
    this.useUserPrenom = false,
    this.useUserNicknames = false,
  });

  static const CoachNicknamePool empty = CoachNicknamePool();

  bool get isEmpty =>
      pool.isEmpty && !useUserPrenom && !useUserNicknames;

  factory CoachNicknamePool.fromJson(Map<String, dynamic> json) {
    final raw = json['pool'];
    final pool = raw is List
        ? raw
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return CoachNicknamePool(
      pool: pool,
      useUserPrenom: json['use_user_prenom'] == true,
      useUserNicknames: json['use_user_nicknames'] == true,
    );
  }
}

/// Pack de phrases d'un coach, structuré en miroir de [PhraseBank] :
/// par mode × tier d'intensité ('soft' / 'medium' / 'hard' / 'any' /
/// 'finale' / 'insistent') + transverses (intros, congrats, encore,
/// excitation par seuil).
///
/// Toute case vide est destinée à fallback sur la `PhraseBank` globale
/// via [Coach.toPhraseBank]. Cela permet de ne rédiger que la voix
/// distinctive d'un coach (ex: ses lignes biffle / hold) sans avoir à
/// dupliquer les phrases neutres communes.
///
/// Le contenu est rédigé manuellement dans `assets/career/coaches/<id>_<lang>.json`,
/// JAMAIS généré automatiquement.
class CoachPhrasePack {
  /// Phrases par mode (rhythm/lick/biffle/hold/breath/beg/freestyle/hand)
  /// puis par tier (chaîne libre, voir doc plus haut).
  final Map<SessionMode, Map<String, List<String>>> byMode;

  final List<String> intros;
  final List<String> congrats;
  final List<String> encore;

  /// Phrases déclenchées au franchissement d'un seuil de la jauge
  /// d'excitation, indexé par seuil (25/50/75/90).
  final Map<int, List<String>> excitation;

  /// Phrases colorées par branche de spécialisation. Pour chaque branche,
  /// pool indexé par tier (`soft` / `medium` / `hard` typiquement). Quand
  /// l'utilisatrice a une branche dominante (≥ 3 pts), `_pickFor` peut
  /// piocher dans ces phrases au lieu du pool standard pour donner une
  /// **couleur audible** à la session (« rentre-le dans ta gorge abyssale »
  /// pour profondeur, « tu ne faiblis jamais » pour endurance, etc.).
  ///
  /// Vide / absent = pas de coloration, comportement historique.
  final Map<SpecializationBranch, Map<String, List<String>>> branchPhrases;

  /// Commentaires aléatoires propres à ce coach. Si non vide, **remplacent**
  /// la liste globale de `random_comments.json` pendant la séance. Vide =
  /// fallback sur la liste globale (comportement historique). Sert à éviter
  /// qu'un coach doux (ex : Lina) sorte des phrases crues du pool partagé.
  final List<String> randomComments;

  /// Surnoms utilisés par ce coach pour substituer `{name}`.
  final CoachNicknamePool nicknames;

  /// Surnoms du coach lui-même, utilisés pour substituer `{coach}`
  /// dans les phrases (ex : « madame », « maîtresse », « coach »).
  /// Si vide, `{coach}` est purement effacé (avec son espace) côté
  /// resolver — pas d'erreur visible si une phrase l'utilise sans pool.
  final List<String> coachNicknames;

  /// Override **localisé** du titre affiché. `null` = garde le défaut codé.
  /// Vit ici (et pas dans `CoachMeta`) parce qu'un titre comme « Coach
  /// découverte » se traduit selon la langue.
  final String? title;

  /// Override **localisé** de la bio affichée dans le picker. Même règle
  /// que `title` : null = défaut codé.
  final String? publicBio;

  const CoachPhrasePack({
    this.byMode = const {},
    this.intros = const [],
    this.congrats = const [],
    this.encore = const [],
    this.excitation = const {},
    this.branchPhrases = const {},
    this.randomComments = const [],
    this.nicknames = CoachNicknamePool.empty,
    this.coachNicknames = const [],
    this.title,
    this.publicBio,
  });

  static const CoachPhrasePack empty = CoachPhrasePack();

  bool get isEmpty =>
      byMode.isEmpty &&
      intros.isEmpty &&
      congrats.isEmpty &&
      encore.isEmpty &&
      excitation.isEmpty &&
      branchPhrases.isEmpty &&
      randomComments.isEmpty &&
      nicknames.isEmpty &&
      coachNicknames.isEmpty &&
      title == null &&
      publicBio == null;

  /// Désérialise un fichier coach. Format attendu :
  ///
  /// ```json
  /// {
  ///   "phrases": {
  ///     "rhythm": { "soft": [...], "medium": [...], "hard": [...] },
  ///     "hold":   { ... },
  ///     ...
  ///   },
  ///   "intros":   [...],
  ///   "congrats": [...],
  ///   "encore":   [...],
  ///   "excitation": { "25": [...], "50": [...], "75": [...], "90": [...] }
  /// }
  /// ```
  ///
  /// Toute clé absente / liste vide est tolérée — le fallback se fait
  /// au niveau de [Coach.toPhraseBank].
  factory CoachPhrasePack.fromJson(Map<String, dynamic> root) {
    List<String> stringList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList(growable: false);
    }

    final phrasesNode = root['phrases'];
    final byMode = <SessionMode, Map<String, List<String>>>{};
    if (phrasesNode is Map<String, dynamic>) {
      for (final mode in SessionMode.values) {
        final modeNode = phrasesNode[mode.name];
        if (modeNode is! Map<String, dynamic>) continue;
        final tiers = <String, List<String>>{};
        modeNode.forEach((tier, raw) {
          final list = stringList(raw);
          if (list.isNotEmpty) tiers[tier] = list;
        });
        if (tiers.isNotEmpty) byMode[mode] = tiers;
      }
    }

    final excitation = <int, List<String>>{};
    final excitNode = root['excitation'];
    if (excitNode is Map<String, dynamic>) {
      excitNode.forEach((key, raw) {
        final threshold = int.tryParse(key);
        if (threshold == null) return;
        final list = stringList(raw);
        if (list.isNotEmpty) excitation[threshold] = list;
      });
    }

    // branchPhrases : map branche → tier → liste. Tolère les clés inconnues
    // (branche serializée non reconnue → ignorée silencieusement).
    final branchPhrases = <SpecializationBranch, Map<String, List<String>>>{};
    final branchNode = root['branchPhrases'];
    if (branchNode is Map<String, dynamic>) {
      branchNode.forEach((branchKey, tiersRaw) {
        if (tiersRaw is! Map<String, dynamic>) return;
        final branch = _parseBranch(branchKey);
        if (branch == null) return;
        final tiers = <String, List<String>>{};
        tiersRaw.forEach((tier, raw) {
          final list = stringList(raw);
          if (list.isNotEmpty) tiers[tier] = list;
        });
        if (tiers.isNotEmpty) branchPhrases[branch] = tiers;
      });
    }

    final nicknamesNode = root['nicknames'];
    final nicknames = nicknamesNode is Map<String, dynamic>
        ? CoachNicknamePool.fromJson(nicknamesNode)
        : CoachNicknamePool.empty;

    String? cleanedString(dynamic raw) {
      if (raw is! String) return null;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return CoachPhrasePack(
      byMode: byMode,
      intros: stringList(root['intros']),
      congrats: stringList(root['congrats']),
      encore: stringList(root['encore']),
      excitation: excitation,
      branchPhrases: branchPhrases,
      randomComments: stringList(root['randomComments']),
      nicknames: nicknames,
      coachNicknames: stringList(root['coachNicknames']),
      title: cleanedString(root['title']),
      publicBio: cleanedString(root['publicBio']),
    );
  }

  /// Désérialise une clé serializée de `SpecializationBranch`. Tolère les
  /// inconnus en retournant null (l'appelant skippe silencieusement).
  static SpecializationBranch? _parseBranch(String raw) {
    for (final b in SpecializationBranch.values) {
      if (b.name == raw) return b;
    }
    // Tolère aussi les variantes serializées (au cas où on ajoute un
    // serializer "rythme_biffle" avec underscore).
    final lower = raw.toLowerCase();
    if (lower == 'rythme_biffle' || lower == 'rythme-biffle') {
      return SpecializationBranch.rythmeBiffle;
    }
    return null;
  }
}

/// Définition d'un coach. Immuable. Les phrases sont fournies à part par
/// `CoachLoader` pour découpler code (catalogue figé) et contenu
/// éditorial (JSON éditable sans recompilation).
class Coach {
  /// Identifiant stable, utilisé en persistance ET en nom de fichier
  /// d'asset (`assets/career/coaches/<id>_<lang>.json`). Ne pas renommer
  /// après release sous peine d'effacer la sélection des joueurs existants
  /// et de déconnecter les phrases.
  final String id;

  /// Nom affiché.
  final String name;

  /// Titre / accroche affichée sous le nom.
  final String title;

  final CoachArchetype archetype;

  /// Bio courte affichée dans l'UI de sélection. Ne contient pas de
  /// phrases prêtes à parler.
  final String publicBio;

  /// Branches de spécialisation que ce coach met en avant. Sert de hint
  /// éventuel pour le générateur (ex: pondérer la spé du coach principal).
  final List<SpecializationBranch> specialties;

  /// Palier auquel ce coach appartient (1..N).
  final int tier;

  /// Si true, ce coach est le **Coach Principal** de son palier : seules
  /// les sessions menées avec lui font progresser le palier.
  final bool isPrincipal;

  final CoachRequirement requirements;

  /// Pack de phrases, chargé depuis le JSON par coach. Vide par défaut.
  final CoachPhrasePack phrases;

  /// Préférences gameplay (cf. [CoachMeta.modeWeights]). Vide = pas
  /// d'override (le générateur applique uniquement la pondération spé).
  final Map<SessionMode, double> modeWeights;

  const Coach({
    required this.id,
    required this.name,
    required this.title,
    required this.archetype,
    required this.publicBio,
    required this.specialties,
    required this.tier,
    required this.isPrincipal,
    this.requirements = CoachRequirement.none,
    this.phrases = CoachPhrasePack.empty,
    this.modeWeights = const {},
  });

  /// Renvoie une copie avec un autre pack de phrases. Si le pack porte
  /// un `title` ou `publicBio` non-null, ils overrident les valeurs codées
  /// par défaut (overrides **localisés** : title/bio sont affichés à l'UI
  /// donc se traduisent par langue).
  Coach withPhrases(CoachPhrasePack pack) {
    return Coach(
      id: id,
      name: name,
      title: pack.title ?? title,
      archetype: archetype,
      publicBio: pack.publicBio ?? publicBio,
      specialties: specialties,
      tier: tier,
      isPrincipal: isPrincipal,
      requirements: requirements,
      phrases: pack,
      modeWeights: modeWeights,
    );
  }

  /// Renvoie une copie avec les **préférences gameplay** overridées par
  /// [meta]. Tout champ null de [meta] est ignoré (la valeur par défaut
  /// codée est conservée). Sert au loader pour appliquer le contenu d'un
  /// fichier `assets/career/coaches/<id>.json` (langue-indépendant).
  Coach withMeta(CoachMeta meta) {
    return Coach(
      id: id,
      name: meta.name ?? name,
      title: title,
      archetype: meta.archetype ?? archetype,
      publicBio: publicBio,
      specialties: meta.specialties ?? specialties,
      tier: meta.tier ?? tier,
      isPrincipal: meta.isPrincipal ?? isPrincipal,
      requirements: meta.requirements ?? requirements,
      phrases: phrases,
      modeWeights: meta.modeWeights ?? modeWeights,
    );
  }

  /// Tire un nom à utiliser pour substituer `{name}` dans une phrase TTS.
  ///
  /// Compose en respectant les flags du `CoachNicknamePool` :
  /// - pool propre du coach (toujours)
  /// - + `userPrenom` si `useUserPrenom`
  /// - + `userNicknames` si `useUserNicknames`
  ///
  /// Si l'union résultante est vide, retombe sur `userFallback` (le pool
  /// user complet, déjà calculé par `UserProfileService.activePool`).
  /// Si même ce fallback est vide, renvoie `'salope'` — alignement sur
  /// le `_emptyFallback` historique d'`UserProfileService`.
  String pickName({
    required String? userPrenom,
    required List<String> userNicknames,
    required List<String> userFallback,
    required Random rng,
  }) {
    final pool = phrases.nicknames;
    final composed = <String>[];
    composed.addAll(pool.pool);
    if (pool.useUserPrenom &&
        userPrenom != null &&
        userPrenom.trim().isNotEmpty) {
      composed.add(userPrenom);
    }
    if (pool.useUserNicknames) composed.addAll(userNicknames);

    if (composed.isNotEmpty) return composed[rng.nextInt(composed.length)];
    if (userFallback.isNotEmpty) {
      return userFallback[rng.nextInt(userFallback.length)];
    }
    return 'salope';
  }

  /// Construit une fonction de résolution `{name}` / `{coach}` → string,
  /// prête à être posée dans `TtsService.setNameResolver`. Tire un nom
  /// différent à chaque occurrence du placeholder dans la même phrase
  /// (variété).
  ///
  /// Règles :
  /// - `{name}` : 1 fois sur 2 le placeholder est purement effacé (avec
  ///   son espace de tête). L'autre fois : tirage dans le pool composé
  ///   (`pickName`). Évite le martelage du surnom.
  /// - `{coach}` : tirage dans `phrases.coachNicknames` ; si vide, la
  ///   balise est effacée (avec son espace de tête).
  String Function(String text) buildTextResolver({
    required String? userPrenom,
    required List<String> userNicknames,
    required List<String> userFallback,
    Random? rng,
  }) {
    final r = rng ?? Random();
    final coachPool = phrases.coachNicknames;
    return (text) {
      if (!text.contains('{')) return text;
      var result = text.replaceAllMapped(
        RegExp(r'\s?\{\s*name\s*\}', caseSensitive: false),
        (m) {
          if (r.nextBool()) return '';
          final hadSpace = m.group(0)?.startsWith(' ') ?? false;
          final picked = pickName(
            userPrenom: userPrenom,
            userNicknames: userNicknames,
            userFallback: userFallback,
            rng: r,
          );
          return hadSpace ? ' $picked' : picked;
        },
      );
      result = result.replaceAllMapped(
        RegExp(r'\s?\{\s*coach\s*\}', caseSensitive: false),
        (m) {
          if (coachPool.isEmpty) return '';
          final hadSpace = m.group(0)?.startsWith(' ') ?? false;
          final picked = coachPool[r.nextInt(coachPool.length)];
          return hadSpace ? ' $picked' : picked;
        },
      );
      return result;
    };
  }

  /// Construit le bundle de commentaires aléatoires à utiliser pendant
  /// une séance avec ce coach :
  /// - si le coach déclare ses propres `randomComments`, on les utilise et
  ///   on garde la cadence (`min/max/cooldown`) du bundle global ;
  /// - sinon on retourne le [fallback] tel quel.
  ///
  /// Évite qu'un coach doux (Lina) sorte des phrases crues du pool partagé.
  RandomCommentsBundle composeRandomComments(RandomCommentsBundle fallback) {
    if (phrases.randomComments.isEmpty) return fallback;
    // Phrases coach : pas de filtres contextuels (tirées brut), enveloppées
    // en RandomComment sans contraintes pour matcher le typage du bundle.
    return RandomCommentsBundle(
      comments: phrases.randomComments
          .map((s) => RandomComment(text: s))
          .toList(),
      minIntervalSeconds: fallback.minIntervalSeconds,
      maxIntervalSeconds: fallback.maxIntervalSeconds,
      scriptedCooldownSeconds: fallback.scriptedCooldownSeconds,
    );
  }

  /// Construit une [PhraseBank] propre à ce coach, en composant son pack
  /// avec [fallback] (la banque globale du jeu). Règles :
  ///
  /// - Pour `byMode[mode][tier]` : si le coach a la liste, on la retourne ;
  ///   sinon on retombe sur le `pickFor` du fallback. La résolution se fait
  ///   donc au moment du tirage, pas à la composition (pour pouvoir refléter
  ///   un éventuel rechargement à chaud).
  /// - Pour `intros / congrats / encore / excitation` : même logique —
  ///   la liste coach prime, vide → fallback.
  ///
  /// Le résultat est une [PhraseBank] consommable telle quelle par
  /// `CareerSessionGenerator` et `SessionController`.
  PhraseBank toPhraseBank({
    required PhraseBank fallback,
    SpecializationAllocation? specialization,
  }) {
    final dominant = specialization == null
        ? null
        : _dominantBranch(specialization);
    return _CoachComposedPhraseBank(
      coachPhrases: phrases,
      fallback: fallback,
      dominantBranch: dominant,
    );
  }

  /// Branche dominante d'une allocation : celle avec le plus de points
  /// investis, **à condition** d'avoir au moins 3 pts (sinon trop diffuse
  /// pour justifier une coloration). Renvoie null si aucune branche
  /// n'atteint le seuil ou en cas d'égalité parfaite (2 branches au même
  /// nombre de pts ≥ 3 → pas de couleur claire). Cf. `_pickFor` dans
  /// `_CoachComposedPhraseBank` pour l'usage.
  static SpecializationBranch? _dominantBranch(
      SpecializationAllocation alloc) {
    SpecializationBranch? best;
    var bestPts = 2; // seuil exclusif (≥ 3 pour être dominante)
    var tied = false;
    for (final b in SpecializationBranch.values) {
      final pts = alloc.pointsIn(b);
      if (pts > bestPts) {
        best = b;
        bestPts = pts;
        tied = false;
      } else if (pts == bestPts && best != null) {
        tied = true;
      }
    }
    return tied ? null : best;
  }
}

/// Sous-classe interne qui surcharge les `pick*` de `PhraseBank` pour
/// servir d'abord les phrases du coach, puis fallback sur la globale.
///
/// On hérite de `PhraseBank` pour rester drop-in compatible : tout code
/// qui prend un `PhraseBank` (générateur, controller…) fonctionne tel
/// quel. Les champs internes `_byMode/_congrats/...` ne sont pas
/// utilisés ici puisqu'on surcharge tous les `pick*`.
class _CoachComposedPhraseBank extends PhraseBank {
  final CoachPhrasePack coachPhrases;
  final PhraseBank fallback;

  /// Branche dominante de l'allocation joueur (≥ 3 pts, pas d'égalité).
  /// `null` si aucune branche dominante claire — tirage standard sans
  /// coloration. Cf. `Coach._dominantBranch`.
  final SpecializationBranch? dominantBranch;

  /// Probabilité, à chaque pickFor, de tenter d'abord le pool « branche
  /// dominante » avant de retomber sur le pool standard. 0.30 = 30 % des
  /// phrases peignent la branche, 70 % restent neutres → variété
  /// préservée, mais la couleur est audible sur 1 phrase/3.
  static const double _branchPickProbability = 0.30;

  _CoachComposedPhraseBank({
    required this.coachPhrases,
    required this.fallback,
    this.dominantBranch,
  }) : super(
          byMode: const {},
          congrats: const [],
          intros: const [],
        );

  @override
  String pickFor(SessionMode mode, String tier, Random rng) {
    // Coloration branche dominante : avant le pool standard, on tente le
    // pool branchPhrases[dominantBranch][tier]. Pas de coloration sur les
    // tiers `boost`/`finale` (dramaturgie propre, déjà spécifique).
    final branch = dominantBranch;
    if (branch != null && tier != 'boost' && tier != 'finale') {
      if (rng.nextDouble() < _branchPickProbability) {
        final pool = coachPhrases.branchPhrases[branch]?[tier];
        if (pool != null && pool.isNotEmpty) {
          return pool[rng.nextInt(pool.length)];
        }
      }
    }
    final tiers = coachPhrases.byMode[mode];
    if (tiers != null) {
      final candidates = tiers[tier];
      if (candidates != null && candidates.isNotEmpty) {
        return candidates[rng.nextInt(candidates.length)];
      }
    }
    return fallback.pickFor(mode, tier, rng);
  }

  @override
  String pickCongrats(Random rng) {
    if (coachPhrases.congrats.isNotEmpty) {
      return coachPhrases
          .congrats[rng.nextInt(coachPhrases.congrats.length)];
    }
    return fallback.pickCongrats(rng);
  }

  @override
  String? pickIntro(Random rng) {
    if (coachPhrases.intros.isNotEmpty) {
      return coachPhrases.intros[rng.nextInt(coachPhrases.intros.length)];
    }
    return fallback.pickIntro(rng);
  }

  @override
  String? pickExcitation(int threshold, Random rng) {
    final list = coachPhrases.excitation[threshold];
    if (list != null && list.isNotEmpty) {
      return list[rng.nextInt(list.length)];
    }
    return fallback.pickExcitation(threshold, rng);
  }

  @override
  String? pickEncore(Random rng) {
    if (coachPhrases.encore.isNotEmpty) {
      return coachPhrases.encore[rng.nextInt(coachPhrases.encore.length)];
    }
    return fallback.pickEncore(rng);
  }

  @override
  String? pickTransition(TransitionKind kind, Random rng) {
    // Les coachs n'ont pas (encore) leurs propres phrases de transition.
    // Délégation directe au fallback global.
    return fallback.pickTransition(kind, rng);
  }

  @override
  String? pickFinishOrgasm(Random rng) {
    // Pareil : pas encore d'override par coach pour les phrases de clôture.
    return fallback.pickFinishOrgasm(rng);
  }

  @override
  String? pickFinalAnnouncement({
    required SessionMode preMode,
    required SessionMode finalMode,
    required Random rng,
  }) {
    // Pas (encore) d'annonces de final par coach — délégation transparente
    // au pool global pour rester compatible avec tous les coachs existants.
    return fallback.pickFinalAnnouncement(
      preMode: preMode,
      finalMode: finalMode,
      rng: rng,
    );
  }

  @override
  String? pickFinalAction({
    required SessionMode mode,
    Position? holdPosition,
    required Random rng,
  }) {
    // Délégation au pool global : les phrases impératives du step final
    // (« ouvre ta bouche », « avale tout ») sont communes à tous les coachs.
    return fallback.pickFinalAction(
      mode: mode,
      holdPosition: holdPosition,
      rng: rng,
    );
  }

  @override
  String? pickPostFinal(Random rng) {
    // Délégation au pool global : compliments de post-final non encore
    // déclinés par coach.
    return fallback.pickPostFinal(rng);
  }

  @override
  String? pickPostFinalBeg(Random rng) {
    // Délégation au pool global : suppliques post-final non encore
    // déclinées par coach.
    return fallback.pickPostFinalBeg(rng);
  }
}
