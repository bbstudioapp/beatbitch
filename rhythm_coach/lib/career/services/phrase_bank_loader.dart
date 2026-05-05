import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart' show rootBundle;

import '../../models/session.dart';
import '../../services/locale_service.dart';
import '../models/phrase_bank.dart';

/// Charge la banque de phrases procédurales depuis `assets/career/phrases.json`
/// (FR par défaut) ou `assets/career/phrases_<lang>.json` pour les autres
/// langues.
class PhraseBankLoader {
  static const String _assetPathDefault = 'assets/career/phrases.json';

  Future<PhraseBank> load({Locale? locale}) async {
    final lang = (locale ?? LocaleService.instance.current).languageCode;
    final path = lang == 'fr'
        ? _assetPathDefault
        : 'assets/career/phrases_$lang.json';
    final raw = await rootBundle.loadString(path);
    final data = json.decode(raw) as Map<String, dynamic>;

    final byMode = <SessionMode, Map<String, List<String>>>{};
    for (final mode in SessionMode.values) {
      final node = data[mode.name];
      if (node is! Map<String, dynamic>) continue;
      final tiers = <String, List<String>>{};
      node.forEach((tier, phrases) {
        if (phrases is List) {
          tiers[tier] = phrases
              .map((p) => p.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList();
        }
      });
      byMode[mode] = tiers;
    }

    final congrats = (data['congrats'] as List<dynamic>? ?? const [])
        .map((p) => p.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final intros = (data['intros'] as List<dynamic>? ?? const [])
        .map((p) => p.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final excitation = <int, List<String>>{};
    final excitNode = data['excitation'];
    if (excitNode is Map<String, dynamic>) {
      excitNode.forEach((key, phrases) {
        final threshold = int.tryParse(key);
        if (threshold == null || phrases is! List) return;
        excitation[threshold] = phrases
            .map((p) => p.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      });
    }

    final encore = (data['encore'] as List<dynamic>? ?? const [])
        .map((p) => p.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final transitions = <TransitionKind, List<String>>{};
    final transNode = data['transitions'];
    if (transNode is Map<String, dynamic>) {
      for (final kind in TransitionKind.values) {
        final list = transNode[kind.serialized];
        if (list is! List) continue;
        transitions[kind] = list
            .map((p) => p.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
    }

    final finishOrgasm = (data['finish_orgasm'] as List<dynamic>? ?? const [])
        .map((p) => p.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final finalAnnouncements = <String, List<String>>{};
    final announceNode = data['final_announce'];
    if (announceNode is Map<String, dynamic>) {
      announceNode.forEach((key, phrases) {
        if (phrases is! List) return;
        finalAnnouncements[key] = phrases
            .map((p) => p.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      });
    }

    return PhraseBank(
      byMode: byMode,
      congrats: congrats,
      intros: intros,
      excitation: excitation,
      encore: encore,
      transitions: transitions,
      finishOrgasm: finishOrgasm,
      finalAnnouncements: finalAnnouncements,
    );
  }
}
