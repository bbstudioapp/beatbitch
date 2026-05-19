import 'dart:math';

import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/random_comments_loader.dart';
import 'phrase_bank.dart';
import 'phrase_entry.dart';
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

  /// Niveau global minimum du joueur (CareerLevel) pour autoriser ce
  /// coach. Permet d'ajouter des coachs annexes débloqués à un niveau
  /// précis sans toucher au système de palier principal.
  final int minPlayerLevel;

  const CoachRequirement({
    this.requiresHands = false,
    this.minPlayerLevel = 1,
  });

  static const CoachRequirement none = CoachRequirement();

  /// Désérialise un objet JSON :
  /// ```jsonc
  /// {
  ///   "requiresHands": false,
  ///   "minPlayerLevel": 1
  /// }
  /// ```
  /// Toute clé absente garde sa valeur par défaut.
  factory CoachRequirement.fromJson(Map<String, dynamic> json) {
    return CoachRequirement(
      requiresHands: json['requiresHands'] == true,
      minPlayerLevel: (json['minPlayerLevel'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Préférences vocales TTS d'un coach. Tout champ null = on garde le
/// réglage par défaut (auto-sélection voix locale + rate/pitch globaux).
/// Sert à donner une « couleur vocale » distincte à chaque coach.
class CoachVoicePreset {
  /// Nom système de la voix (ex: `fr-fr-x-fra-local`). Null = pas de
  /// changement. Si la voix demandée n'existe pas sur l'appareil, on
  /// retombe sur l'auto-sélection (cf. `TtsService.applyCoachVoicePreset`).
  final String? voiceName;

  /// Locale BCP-47 associée à la voix (ex: `fr-FR`). Null = on prend
  /// celle de la voix résolue, ou la locale courante du moteur.
  final String? voiceLocale;

  /// Vitesse de parole. Plage usuelle 0.3..0.8. Null = `TtsService.defaultRate`.
  final double? rate;

  /// Hauteur de voix. Plage usuelle 0.5..2.0. Null = `TtsService.defaultPitch`.
  final double? pitch;

  const CoachVoicePreset({
    this.voiceName,
    this.voiceLocale,
    this.rate,
    this.pitch,
  });

  static const CoachVoicePreset empty = CoachVoicePreset();

  bool get isEmpty =>
      voiceName == null && voiceLocale == null && rate == null && pitch == null;

  /// Désérialise depuis un objet JSON :
  /// ```jsonc
  /// "tts": { "voice": "fr-fr-x-fra-local", "rate": 0.55, "pitch": 1.30 }
  /// ```
  factory CoachVoicePreset.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) => (v is num) ? v.toDouble() : null;
    String? asString(dynamic v) {
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    return CoachVoicePreset(
      voiceName: asString(json['voice'] ?? json['voiceName']),
      voiceLocale: asString(json['voiceLocale'] ?? json['locale']),
      rate: asDouble(json['rate']),
      pitch: asDouble(json['pitch']),
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

  /// Chemin de l'asset portrait (ex: `assets/career/coaches/portraits/coach_01_lina.png`).
  /// Null = pas d'override, on garde le chemin codé dans `CoachCatalog.defaults`
  /// (qui peut lui-même être null pour un coach sans portrait — l'UI affiche
  /// alors un repli stylisé).
  final String? portraitAsset;

  /// Préférences gameplay du coach : multiplicateur appliqué au poids
  /// de tirage de chaque mode (cf. `_modeWeight` dans le générateur).
  /// Valeurs entre 0.0 (« jamais ») et 2.0 (« doublé »). 1.0 = neutre.
  /// Mode absent = 1.0. Combiné multiplicativement avec les bonus de
  /// spécialisation. Null = aucun override.
  final Map<SessionMode, double>? modeWeights;

  /// Preset vocal (voix nommée + rate + pitch). Null = pas d'override,
  /// le coach parle avec la voix auto-sélectionnée par `TtsService`.
  final CoachVoicePreset? voicePreset;

  const CoachMeta({
    this.name,
    this.archetype,
    this.specialties,
    this.tier,
    this.isPrincipal,
    this.requirements,
    this.portraitAsset,
    this.modeWeights,
    this.voicePreset,
  });

  static const CoachMeta empty = CoachMeta();

  bool get isEmpty =>
      name == null &&
      archetype == null &&
      specialties == null &&
      tier == null &&
      isPrincipal == null &&
      requirements == null &&
      portraitAsset == null &&
      modeWeights == null &&
      voicePreset == null;

  /// Désérialise depuis un JSON top-level :
  /// ```jsonc
  /// {
  ///   "id": "coach_xx",          // ignoré ici (résolu par nom de fichier)
  ///   "name": "...",
  ///   "archetype": "bienveillant",
  ///   "specialties": ["endurance", "profondeur"],
  ///   "tier": 1,
  ///   "isPrincipal": true,
  ///   "requirements": { "requiresHands": false, "minPlayerLevel": 1 },
  ///   "portrait": "assets/career/coaches/portraits/coach_01_lina.png"
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

    final rawPortrait =
        (json['portrait'] ?? json['portraitAsset'])?.toString().trim();

    final ttsNode = json['tts'];
    final voicePreset = ttsNode is Map<String, dynamic>
        ? CoachVoicePreset.fromJson(ttsNode)
        : null;

    return CoachMeta(
      name: (rawName != null && rawName.isNotEmpty) ? rawName : null,
      archetype: archetype,
      specialties: specialties,
      tier: (json['tier'] as num?)?.toInt(),
      isPrincipal:
          json['isPrincipal'] is bool ? json['isPrincipal'] as bool : null,
      requirements: requirements,
      portraitAsset:
          (rawPortrait != null && rawPortrait.isNotEmpty) ? rawPortrait : null,
      modeWeights: modeWeights,
      voicePreset:
          (voicePreset != null && !voicePreset.isEmpty) ? voicePreset : null,
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

  bool get isEmpty => pool.isEmpty && !useUserPrenom && !useUserNicknames;

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
  /// puis par tier (chaîne libre, voir doc plus haut). Chaque entrée peut
  /// porter des contraintes de profondeur/BPM/unlock — cf. [PhraseEntry].
  final Map<SessionMode, Map<String, List<PhraseEntry>>> byMode;

  final List<PhraseEntry> intros;
  final List<PhraseEntry> congrats;
  final List<PhraseEntry> encore;

  /// Phrases déclenchées au franchissement d'un seuil de progression de la
  /// séance (ratio elapsed/duration), indexé par seuil en pourcent
  /// (25/50/75/90).
  final Map<int, List<PhraseEntry>> progress;

  /// Phrases colorées par branche de spécialisation. Pour chaque branche,
  /// pool indexé par tier (`soft` / `medium` / `hard` typiquement). Quand
  /// l'utilisatrice a une branche dominante (≥ 3 pts), `_pickFor` peut
  /// piocher dans ces phrases au lieu du pool standard pour donner une
  /// **couleur audible** à la session (« rentre-le dans ta gorge abyssale »
  /// pour profondeur, « tu ne faiblis jamais » pour endurance, etc.).
  ///
  /// Vide / absent = pas de coloration, comportement historique.
  final Map<SpecializationBranch, Map<String, List<PhraseEntry>>> branchPhrases;

  /// Phrases de progression du **profil de capacités** (Phase 4 — coach
  /// audible parcimonieux). Pour chaque axe — clé = `CapabilityAxis.storageKey`
  /// (ex. `"gorge.apnee_streak"`, `"rhythm.depth_max"`) — trois tiers :
  ///
  /// - `attempt` : annonce avant une surcharge (« aujourd'hui on bat ton
  ///   record de gorge »), injectée comme texte du step #0 par le générateur.
  /// - `record` : record battu sur l'axe poussé — phrase de reconnaissance,
  ///   prononcée en fin de séance par `SessionController`.
  /// - `tapout` : « je peux pas » reconnu comme limite légitime — variante
  ///   DOUCE des phrases de fail, prononcée à la place de la phrase de fail
  ///   standard quand le tap-out est imputable à un axe vraiment surchargé.
  ///
  /// Déclenchement RARE (∝ niveau, quasi-muet aux premiers paliers). Clé brute
  /// (String) : une clé inconnue n'est juste jamais consultée. Vide / absent =
  /// silence — comportement de tous les coachs sauf Lina + Victoria.
  final Map<String, Map<String, List<PhraseEntry>>> progressPhrases;

  /// Phrases du système de défis intra-séance (Phase 1). Pour chaque axe —
  /// clé = `CapabilityAxis.storageKey` (ex. `"hold.throat.streak"`) — sept
  /// tiers :
  ///
  /// - `attempt` : annonce du défi pendant le breath de countdown.
  /// - `extension` : « tu peux rester là si tu veux » à `seuil - 3 s`.
  /// - `success` : succès net (seuil atteint puis `JE M'ARRÊTE` ou timeout).
  /// - `stop` : variante de `success` quand la joueuse a explicitement
  ///   appuyé sur `JE M'ARRÊTE` (vs timeout — taquinerie possible).
  /// - `fail` : tap-out avant le seuil (« tu pouvais rester si tu avais tenu »).
  /// - `timeout` : timeout 8 s au seuil → succès auto, coach taquine.
  /// - `skip` : commentaire neutre quand la joueuse appuie `PASSE`
  ///   pendant le breath de countdown.
  ///
  /// Clé brute (String), tolérante : une clé inconnue n'est jamais
  /// consultée. Vide / absent = fallback sur la PhraseBank globale (qui
  /// n'a rien non plus → silence côté coach, l'UI affiche un texte localisé).
  final Map<String, Map<String, List<PhraseEntry>>> challengePhrases;

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
    this.progress = const {},
    this.branchPhrases = const {},
    this.progressPhrases = const {},
    this.challengePhrases = const {},
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
      progress.isEmpty &&
      branchPhrases.isEmpty &&
      progressPhrases.isEmpty &&
      challengePhrases.isEmpty &&
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
  ///   "progress":   { "25": [...], "50": [...], "75": [...], "90": [...] }
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
    final byMode = <SessionMode, Map<String, List<PhraseEntry>>>{};
    if (phrasesNode is Map<String, dynamic>) {
      for (final mode in SessionMode.values) {
        final modeNode = phrasesNode[mode.name];
        if (modeNode is! Map<String, dynamic>) continue;
        final tiers = <String, List<PhraseEntry>>{};
        modeNode.forEach((tier, raw) {
          final list = PhraseEntry.listFromJson(raw);
          if (list.isNotEmpty) tiers[tier] = list;
        });
        if (tiers.isNotEmpty) byMode[mode] = tiers;
      }
    }

    final progress = <int, List<PhraseEntry>>{};
    final progressNode = root['progress'];
    if (progressNode is Map<String, dynamic>) {
      progressNode.forEach((key, raw) {
        final threshold = int.tryParse(key);
        if (threshold == null) return;
        final list = PhraseEntry.listFromJson(raw);
        if (list.isNotEmpty) progress[threshold] = list;
      });
    }

    // branchPhrases : map branche → tier → liste. Tolère les clés inconnues
    // (branche serializée non reconnue → ignorée silencieusement).
    final branchPhrases =
        <SpecializationBranch, Map<String, List<PhraseEntry>>>{};
    final branchNode = root['branchPhrases'];
    if (branchNode is Map<String, dynamic>) {
      branchNode.forEach((branchKey, tiersRaw) {
        if (tiersRaw is! Map<String, dynamic>) return;
        final branch = _parseBranch(branchKey);
        if (branch == null) return;
        final tiers = <String, List<PhraseEntry>>{};
        tiersRaw.forEach((tier, raw) {
          final list = PhraseEntry.listFromJson(raw);
          if (list.isNotEmpty) tiers[tier] = list;
        });
        if (tiers.isNotEmpty) branchPhrases[branch] = tiers;
      });
    }

    // progressPhrases : map storageKey-d'axe → tier → liste. Clé brute (String),
    // pas de validation contre l'enum `CapabilityAxis` — une clé inconnue n'est
    // simplement jamais consultée (cf. CoachPhrasePack.progressPhrases).
    final progressPhrases = <String, Map<String, List<PhraseEntry>>>{};
    final progressPhrasesNode = root['progressPhrases'];
    if (progressPhrasesNode is Map<String, dynamic>) {
      progressPhrasesNode.forEach((axisKey, tiersRaw) {
        if (axisKey.trim().isEmpty || tiersRaw is! Map<String, dynamic>) return;
        final tiers = <String, List<PhraseEntry>>{};
        tiersRaw.forEach((tier, raw) {
          final list = PhraseEntry.listFromJson(raw);
          if (list.isNotEmpty) tiers[tier] = list;
        });
        if (tiers.isNotEmpty) progressPhrases[axisKey] = tiers;
      });
    }

    // challengePhrases : même forme que progressPhrases, tiers
    // attempt|extension|success|stop|fail|timeout|skip (cf. spec §7).
    final challengePhrases = <String, Map<String, List<PhraseEntry>>>{};
    final challengePhrasesNode = root['challengePhrases'];
    if (challengePhrasesNode is Map<String, dynamic>) {
      challengePhrasesNode.forEach((axisKey, tiersRaw) {
        if (axisKey.trim().isEmpty || tiersRaw is! Map<String, dynamic>) return;
        final tiers = <String, List<PhraseEntry>>{};
        tiersRaw.forEach((tier, raw) {
          final list = PhraseEntry.listFromJson(raw);
          if (list.isNotEmpty) tiers[tier] = list;
        });
        if (tiers.isNotEmpty) challengePhrases[axisKey] = tiers;
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
      intros: PhraseEntry.listFromJson(root['intros']),
      congrats: PhraseEntry.listFromJson(root['congrats']),
      encore: PhraseEntry.listFromJson(root['encore']),
      progress: progress,
      branchPhrases: branchPhrases,
      progressPhrases: progressPhrases,
      challengePhrases: challengePhrases,
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

  /// Slug court extrait de l'`id` (`coach_NN_<slug>` → `<slug>`). Sert au
  /// tagging des fonds (cf. `BackgroundTagVocabulary` côté
  /// `backgrounds_loader.dart`) : un fichier `clip_lina.png` sera proposé
  /// en priorité quand `slug == "lina"`.
  String get slug {
    final parts = id.split('_');
    return parts.isEmpty ? id : parts.last;
  }

  /// Nom affiché.
  final String name;

  /// Titre / accroche affichée sous le nom.
  final String title;

  final CoachArchetype archetype;

  /// Bio courte affichée dans l'UI de sélection. Ne contient pas de
  /// phrases prêtes à parler.
  final String publicBio;

  /// Chemin de l'asset portrait du coach (ex:
  /// `assets/career/coaches/portraits/coach_01_lina.png`), ratio source 2:3.
  /// `null` = pas de portrait → l'UI affiche un repli stylisé (initiale).
  /// Surchargeable via la clé `portrait` du JSON `coach_<id>.json`.
  final String? portraitAsset;

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

  /// Preset vocal TTS (voix + rate + pitch). `empty` = auto-sélection
  /// + valeurs par défaut. Cf. [CoachVoicePreset] et la doc de
  /// `TtsService.applyCoachVoicePreset`.
  final CoachVoicePreset voicePreset;

  const Coach({
    required this.id,
    required this.name,
    required this.title,
    required this.archetype,
    required this.publicBio,
    required this.specialties,
    required this.tier,
    required this.isPrincipal,
    this.portraitAsset,
    this.requirements = CoachRequirement.none,
    this.phrases = CoachPhrasePack.empty,
    this.modeWeights = const {},
    this.voicePreset = CoachVoicePreset.empty,
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
      portraitAsset: portraitAsset,
      requirements: requirements,
      phrases: pack,
      modeWeights: modeWeights,
      voicePreset: voicePreset,
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
      portraitAsset: meta.portraitAsset ?? portraitAsset,
      requirements: meta.requirements ?? requirements,
      phrases: phrases,
      modeWeights: meta.modeWeights ?? modeWeights,
      voicePreset: meta.voicePreset ?? voicePreset,
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
      comments:
          phrases.randomComments.map((s) => RandomComment(text: s)).toList(),
      minIntervalSeconds: fallback.minIntervalSeconds,
      maxIntervalSeconds: fallback.maxIntervalSeconds,
      scriptedCooldownSeconds: fallback.scriptedCooldownSeconds,
    );
  }

  /// Boost virtuel par branche listée dans [specialties]. La sémantique est
  /// « le coach principal t'introduit ses spés sans dominer ce que tu as
  /// déjà investi » (cf. [effectiveAllocation]). À 2 pts, l'effet est lisible
  /// dans les biais Phase B (durée +10 %, ampScore +0.10, poids rhythm +0.40)
  /// sans écraser une joueuse débutante.
  static const int _specialtyBoost = 2;

  /// Renvoie une allocation effective qui combine la spé persistée de la
  /// joueuse [player] et un boost coach par branche listée dans
  /// [specialties]. Sémantique « boost déclinant » :
  ///
  ///   `effective(branch) = max(player(branch), _specialtyBoost)`
  ///       si `branch ∈ specialties`, sinon `player(branch)`
  ///
  /// Cas concrets :
  /// - Joueuse 0 pt sur la branche coach → effective = 2 (le coach amène).
  /// - Joueuse 5 pts sur la branche coach → effective = 5 (rien à apporter).
  /// - Branche hors `specialties` → inchangée (le coach ne touche pas).
  ///
  /// Le résultat est consommé par le générateur (`Phase B` — pondérations
  /// de durée, BPM, amplitude, poids de mode). N'affecte ni la coloration
  /// de phrases (qui reste sur la spé joueuse pure pour ne pas créer de
  /// branche dominante artificielle) ni le gating de milestones.
  ///
  /// `lastRespecMs` est passé tel quel.
  SpecializationAllocation effectiveAllocation(
      SpecializationAllocation player) {
    if (specialties.isEmpty) return player;
    final boosted = <SpecializationBranch, int>{};
    for (final b in SpecializationBranch.values) {
      final pts = player.pointsIn(b);
      boosted[b] = specialties.contains(b) && pts < _specialtyBoost
          ? _specialtyBoost
          : pts;
    }
    return SpecializationAllocation(
      points: boosted,
      lastRespecMs: player.lastRespecMs,
    );
  }

  /// Construit une [PhraseBank] propre à ce coach, en composant son pack
  /// avec [fallback] (la banque globale du jeu). Règles :
  ///
  /// - Pour `byMode[mode][tier]` : si le coach a la liste, on la retourne ;
  ///   sinon on retombe sur le `pickFor` du fallback. La résolution se fait
  ///   donc au moment du tirage, pas à la composition (pour pouvoir refléter
  ///   un éventuel rechargement à chaud).
  /// - Pour `intros / congrats / encore / progress` : même logique —
  ///   la liste coach prime, vide → fallback.
  ///
  /// Le résultat est une [PhraseBank] consommable telle quelle par
  /// `CareerSessionGenerator` et `SessionController`.
  PhraseBank toPhraseBank({
    required PhraseBank fallback,
    SpecializationAllocation? specialization,
  }) {
    final dominant =
        specialization == null ? null : _dominantBranch(specialization);
    return _CoachComposedPhraseBank(
      coachPhrases: phrases,
      fallback: fallback,
      dominantBranch: dominant,
    );
  }

  /// Probabilité par minute qu'une mini-punition inopinée se déclenche en
  /// cours de séance, dérivée de l'archétype du coach (sa « personnalité »).
  /// Un coach bienveillant n'en glisse presque jamais ; une coach brutale /
  /// sans pitié les multiplie. Consommée par `SessionController` via
  /// `SessionScreen` (sessions carrière uniquement — hors carrière, le
  /// caller ne le passe pas → 0). À 0.20, ~20 %/min de mini-punition.
  double get miniPunishmentRate => switch (archetype) {
        CoachArchetype.bienveillant => 0.04,
        CoachArchetype.strict => 0.10,
        CoachArchetype.hautain => 0.11,
        CoachArchetype.taquinSadique => 0.14,
        CoachArchetype.brutal => 0.18,
        CoachArchetype.sansPitie => 0.22,
      };

  /// Branche dominante d'une allocation : celle avec le plus de points
  /// investis, **à condition** d'avoir au moins 3 pts (sinon trop diffuse
  /// pour justifier une coloration). Renvoie null si aucune branche
  /// n'atteint le seuil ou en cas d'égalité parfaite (2 branches au même
  /// nombre de pts ≥ 3 → pas de couleur claire). Cf. `_pickFor` dans
  /// `_CoachComposedPhraseBank` pour l'usage.
  static SpecializationBranch? _dominantBranch(SpecializationAllocation alloc) {
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
  String pickFor(
    SessionMode mode,
    String tier,
    Random rng, {
    PhraseContext? context,
  }) {
    // Coloration branche dominante : avant le pool standard, on tente le
    // pool branchPhrases[dominantBranch][tier]. Pas de coloration sur les
    // tiers `boost`/`finale` (dramaturgie propre, déjà spécifique).
    final branch = dominantBranch;
    if (branch != null && tier != 'boost' && tier != 'finale') {
      if (rng.nextDouble() < _branchPickProbability) {
        final pool = coachPhrases.branchPhrases[branch]?[tier];
        if (pool != null && pool.isNotEmpty) {
          final picked = pickPhraseEntry(pool, rng, context: context);
          if (picked != null) return picked;
        }
      }
    }
    final tiers = coachPhrases.byMode[mode];
    if (tiers != null) {
      final candidates = tiers[tier];
      if (candidates != null && candidates.isNotEmpty) {
        final picked = pickPhraseEntry(candidates, rng, context: context);
        if (picked != null) return picked;
      }
    }
    return fallback.pickFor(mode, tier, rng, context: context);
  }

  @override
  String pickCongrats(Random rng) {
    final picked = pickPhraseEntry(coachPhrases.congrats, rng);
    if (picked != null) return picked;
    return fallback.pickCongrats(rng);
  }

  @override
  String? pickIntro(Random rng) {
    final picked = pickPhraseEntry(coachPhrases.intros, rng);
    if (picked != null) return picked;
    return fallback.pickIntro(rng);
  }

  @override
  String? pickProgress(int threshold, Random rng) {
    final list = coachPhrases.progress[threshold];
    if (list != null && list.isNotEmpty) {
      final picked = pickPhraseEntry(list, rng);
      if (picked != null) return picked;
    }
    return fallback.pickProgress(threshold, rng);
  }

  @override
  String? pickEncore(Random rng) {
    final picked = pickPhraseEntry(coachPhrases.encore, rng);
    if (picked != null) return picked;
    return fallback.pickEncore(rng);
  }

  @override
  String? pickProgressPhrase(String axisStorageKey, String tier, Random rng) {
    final pool = coachPhrases.progressPhrases[axisStorageKey]?[tier];
    if (pool != null && pool.isNotEmpty) {
      final picked = pickPhraseEntry(pool, rng);
      if (picked != null) return picked;
    }
    return fallback.pickProgressPhrase(axisStorageKey, tier, rng);
  }

  @override
  String? pickChallengePhrase(String axisStorageKey, String tier, Random rng) {
    final pool = coachPhrases.challengePhrases[axisStorageKey]?[tier];
    if (pool != null && pool.isNotEmpty) {
      final picked = pickPhraseEntry(pool, rng);
      if (picked != null) return picked;
    }
    return fallback.pickChallengePhrase(axisStorageKey, tier, rng);
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

  @override
  String? pickPostFinalLick(Random rng) {
    // Délégation au pool global : consignes lick post-final non encore
    // déclinées par coach.
    return fallback.pickPostFinalLick(rng);
  }

  @override
  String? pickSwallowOrder(Random rng) {
    // Délégation au pool global : ordres de déglutition non encore
    // déclinés par coach.
    return fallback.pickSwallowOrder(rng);
  }
}
