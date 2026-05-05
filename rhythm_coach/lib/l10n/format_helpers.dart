import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

/// Format détaillé d'une durée en secondes : `42 s`, `5 min`, `5 min 12 s`,
/// `2 h`, `2 h 05`. Reproduit l'ancienne sémantique de `_formatDuration`
/// (profile_screen) en passant par les clés ARB.
String formatDurationDetailed(BuildContext context, int seconds) {
  final t = AppLocalizations.of(context);
  if (seconds < 60) return t.formatDurationSeconds(seconds);
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m < 60) {
    return s == 0
        ? t.formatDurationMinutes(m)
        : t.formatDurationMinutesSeconds(m, s);
  }
  final h = m ~/ 60;
  final mm = m % 60;
  if (mm == 0) return t.formatDurationHours(h);
  return t.formatDurationHoursMinutes(h, mm.toString().padLeft(2, '0'));
}

/// Format compact d'une durée en secondes (pas de seconds display).
/// Reproduit `_formatDurationSeconds` de career_screen.
String formatDurationCompact(BuildContext context, int seconds) {
  final t = AppLocalizations.of(context);
  final minutes = seconds ~/ 60;
  if (minutes < 60) return t.formatDurationMinutes(minutes);
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return t.formatDurationHours(h);
  return t.formatDurationHoursMinutes(h, m.toString());
}

/// Nombre formaté selon la locale active (séparateur de milliers natif).
String formatLocalizedNumber(BuildContext context, int n) {
  final locale = Localizations.localeOf(context).toString();
  return intl.NumberFormat.decimalPattern(locale).format(n);
}
