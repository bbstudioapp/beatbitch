import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart' show rootBundle;

import '../../models/session.dart';
import '../../services/locale_service.dart';
import '../models/phrase_bank.dart';

/// Charge la banque de phrases procédurales depuis `assets/career/phrases.json`
/// (FR par défaut) ou `assets/career/phrases_<lang>.json` pour les autres
/// langues.
///
/// Chaque liste de phrases (par mode/tier, ou pool transverse comme
/// `congrats`, `transitions`, etc.) accepte des entrées sous deux formes :
/// une string simple, ou un objet `{text, min_depth?, max_depth?, min_bpm?,
/// max_bpm?, requires_unlock?}` pour réserver la phrase à un contexte. Cf.
/// [PhraseEntry] pour le détail des contraintes.
class PhraseBankLoader {
  static const String _assetPathDefault = 'assets/career/phrases.json';

  Future<PhraseBank> load({Locale? locale}) async {
    final lang = (locale ?? LocaleService.instance.current).languageCode;
    final path = lang == 'fr'
        ? _assetPathDefault
        : 'assets/career/phrases_$lang.json';
    final raw = await rootBundle.loadString(path);
    final data = json.decode(raw) as Map<String, dynamic>;

    final byMode = <SessionMode, Map<String, List<PhraseEntry>>>{};
    for (final mode in SessionMode.values) {
      final node = data[mode.name];
      if (node is! Map<String, dynamic>) continue;
      final tiers = <String, List<PhraseEntry>>{};
      node.forEach((tier, phrases) {
        final list = PhraseEntry.listFromJson(phrases);
        if (list.isNotEmpty) tiers[tier] = list;
      });
      byMode[mode] = tiers;
    }

    final progress = <int, List<PhraseEntry>>{};
    final progressNode = data['progress'];
    if (progressNode is Map<String, dynamic>) {
      progressNode.forEach((key, phrases) {
        final threshold = int.tryParse(key);
        if (threshold == null) return;
        final list = PhraseEntry.listFromJson(phrases);
        if (list.isNotEmpty) progress[threshold] = list;
      });
    }

    final transitions = <TransitionKind, List<PhraseEntry>>{};
    final transNode = data['transitions'];
    if (transNode is Map<String, dynamic>) {
      for (final kind in TransitionKind.values) {
        final list = PhraseEntry.listFromJson(transNode[kind.serialized]);
        if (list.isNotEmpty) transitions[kind] = list;
      }
    }

    final finalAnnouncements = <String, List<PhraseEntry>>{};
    final announceNode = data['final_announce'];
    if (announceNode is Map<String, dynamic>) {
      announceNode.forEach((key, phrases) {
        final list = PhraseEntry.listFromJson(phrases);
        if (list.isNotEmpty) finalAnnouncements[key] = list;
      });
    }

    final finalActions = <String, List<PhraseEntry>>{};
    final finalActionNode = data['final_action'];
    if (finalActionNode is Map<String, dynamic>) {
      finalActionNode.forEach((key, phrases) {
        final list = PhraseEntry.listFromJson(phrases);
        if (list.isNotEmpty) finalActions[key] = list;
      });
    }

    return PhraseBank(
      byMode: byMode,
      congrats: PhraseEntry.listFromJson(data['congrats']),
      intros: PhraseEntry.listFromJson(data['intros']),
      progress: progress,
      encore: PhraseEntry.listFromJson(data['encore']),
      transitions: transitions,
      finishOrgasm: PhraseEntry.listFromJson(data['finish_orgasm']),
      finalAnnouncements: finalAnnouncements,
      finalActions: finalActions,
      postFinal: PhraseEntry.listFromJson(data['post_final']),
      postFinalBeg: PhraseEntry.listFromJson(data['post_final_beg']),
      postFinalLick: PhraseEntry.listFromJson(data['post_final_lick']),
      swallowOrders: PhraseEntry.listFromJson(data['swallow_order']),
    );
  }
}
