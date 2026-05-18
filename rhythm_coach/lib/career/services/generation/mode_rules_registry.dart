// Library autonome — registry par défaut des règles par mode (9 modes
// du jeu). Sortie de `career_session_generator.dart` en C.PR7 du plan
// de refacto : le fichier principal n'importe plus les 9
// implémentations concrètes (`RhythmRules`, `LickRules`, …), il consomme
// uniquement la const map exposée ici.
//
// La carrière (`CareerSessionGenerator`) ré-importe cette library et
// re-exporte `defaultModeRulesRegistry` pour préserver la rétrocompat
// des call sites externes (tests notamment).

import '../../../models/session.dart';
import 'mode_rules.dart';
import 'rules/career_session_generator_rules_beg.dart';
import 'rules/career_session_generator_rules_biffle.dart';
import 'rules/career_session_generator_rules_breath.dart';
import 'rules/career_session_generator_rules_freestyle.dart';
import 'rules/career_session_generator_rules_hand.dart';
import 'rules/career_session_generator_rules_hold.dart';
import 'rules/career_session_generator_rules_lick.dart';
import 'rules/career_session_generator_rules_rhythm.dart';
import 'rules/career_session_generator_rules_suckle.dart';

/// Registry par défaut des règles par mode — couvre les 9 modes du jeu.
/// Injecté au `CareerSessionGenerator` quand aucun `rules` n'est passé au
/// constructeur (cas standard). Un test ou un module externe peut passer
/// un registry de sa fabrication (par exemple pour mocker une rule).
///
/// Const map : les rules sont stateless avec des const constructors, donc
/// la map est const-évaluable et thread-safe.
///
/// L'ordre d'insertion est **déterministe** (Dart `const Map` conserve
/// l'ordre du literal) et consommé par plusieurs sites du générateur
/// (`FinalPicker.pickFinal` concatène les variantes dans l'ordre du
/// registry, `_resolveModeForRole` itère en ordre d'insertion pour
/// trouver le mode qui déclare un rôle, etc.). Ne pas réordonner sans
/// vérifier les tests des sites concernés.
///
/// ─── Audit `SessionMode.*` literal résiduels du registry ──────────
/// Les 9 clés ci-dessous sont les seuls `SessionMode.*` literals
/// **de logique** subsistants après les phases B + C du plan de
/// refacto (`~/beatbitch_refacto_career_gen.md`). Elles sont
/// inhérentes au pattern « map d'enum vers handler » — chaque clé est
/// l'identité technique du mode, pas un choix dramaturgique. Toutes
/// les autres références mode-aware passent par les rôles sémantiques
/// (cf. [ModeSemanticRole]) ou par les contrats `ModeRules`
/// (`classify`, `isFlow`, `isRhythmic`, `difficultyRange`,
/// `baseWeight`…).
///
/// Les literals dans les **part files** (`_punishment.dart` palette de
/// compos, `_mode_picker.dart` switch exhaustifs sur `StepType`,
/// `_rhythmic_pattern_buffer.dart` filtre des modes rythmiques) sont
/// également légitimes : ce sont soit du contenu (palette punition),
/// soit des switches exhaustifs sur l'enum — pas des choix
/// dramaturgiques portables sur un rôle.
const Map<SessionMode, ModeRules> defaultModeRulesRegistry = {
  SessionMode.rhythm: RhythmRules(),
  SessionMode.lick: LickRules(),
  SessionMode.hold: HoldRules(),
  SessionMode.biffle: BiffleRules(),
  SessionMode.beg: BegRules(),
  SessionMode.hand: HandRules(),
  SessionMode.breath: BreathRules(),
  SessionMode.freestyle: FreestyleRules(),
  SessionMode.suckle: SuckleRules(),
};
