import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/session.dart';
import '../services/ambience_engine.dart';
import '../services/beep_engine.dart';
import '../services/camera_motion_service.dart';
import '../services/platform_capabilities.dart';
import '../services/punishment_loader.dart';
import '../services/random_comments_loader.dart';
import '../services/saved_sessions_repository.dart';
import '../services/session_loader.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_card.dart';
import 'camera_test_screen.dart';
import 'session_screen.dart';

/// Écran "Scénario" : liste des sessions JSON statiques. Les services
/// partagés (TTS, beep, ambiance) sont fournis par `ModeSelectionScreen`
/// pour rester en vie quand on navigue entre les modes.
class HomeScreen extends StatefulWidget {
  final TtsService tts;
  final BeepEngine beep;
  final AmbienceEngine ambience;

  const HomeScreen({
    super.key,
    required this.tts,
    required this.beep,
    required this.ambience,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_SessionsBundle> _sessionsFuture;
  late final Future<PunishmentBundle> _punishmentsFuture;
  late final Future<RandomCommentsBundle> _randomCommentsFuture;
  final SavedSessionsRepository _savedRepo = SavedSessionsRepository();

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _loadSessions();
    _punishmentsFuture = PunishmentLoader().load();
    _randomCommentsFuture = RandomCommentsLoader().load();
  }

  Future<_SessionsBundle> _loadSessions() async {
    final results = await Future.wait([
      SessionLoader().loadAll(),
      _savedRepo.loadAll(),
    ]);
    return _SessionsBundle(
      bundled: results[0],
      saved: results[1],
    );
  }

  void _refreshSessions() {
    setState(() {
      _sessionsFuture = _loadSessions();
    });
  }

  Future<void> _openSession(Session session) async {
    final results = await Future.wait([
      _punishmentsFuture,
      _randomCommentsFuture,
    ]);
    final bundle = results[0] as PunishmentBundle;
    final comments = results[1] as RandomCommentsBundle;
    final camService = CameraMotionService();
    final verifier = await camService.buildVerifierIfEnabled(widget.tts);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          session: session,
          tts: widget.tts,
          beep: widget.beep,
          ambience: widget.ambience,
          punishmentBundle: bundle,
          randomComments: comments,
          introText: session.intro.isNotEmpty ? session.intro : null,
          holdVerifier: verifier,
        ),
      ),
    );
    // Au retour : remet le détecteur en idle pour ne pas garder ML Kit
    // qui tourne entre deux sessions. La caméra reste allumée tant que
    // l'écran de test caméra est dans l'arborescence ; sinon le service
    // peut être release explicitement plus tard.
    if (verifier != null) camService.stopSessionDetection();
    // Rafraîchit la liste — l'utilisateur a pu enregistrer la session
    // qu'il vient de jouer (mode Carrière).
    if (mounted) _refreshSessions();
  }

  void _openCameraTest() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraTestScreen(
          tts: widget.tts,
          beep: widget.beep,
          ambience: widget.ambience,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSaved(Session session) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.homeDeleteSessionTitle),
        content: Text(t.homeDeleteSessionContent(session.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _savedRepo.delete(session.id);
      if (!mounted) return;
      _refreshSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.homeAppBarTitle),
        actions: [
          if (PlatformCapabilities.supportsCameraHoldCheck)
            IconButton(
              tooltip: t.homeCameraTestTooltip,
              icon: const Icon(Icons.videocam_outlined),
              onPressed: _openCameraTest,
            ),
        ],
      ),
      body: FutureBuilder<_SessionsBundle>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.homeLoadError(snapshot.error.toString()),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }
          final bundle = snapshot.data!;
          final bundled = bundle.bundled;
          final saved = bundle.saved;
          if (bundled.isEmpty && saved.isEmpty) {
            return Center(child: Text(t.homeEmpty));
          }

          return RefreshIndicator(
            onRefresh: () async => _refreshSessions(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _buildHeader(t),
                const SizedBox(height: 12),
                if (saved.isNotEmpty) ...[
                  _SectionLabel(title: t.homeMySessions),
                  const SizedBox(height: 8),
                  for (final s in saved) ...[
                    _SwipeToDeleteCard(
                      key: ValueKey(s.id),
                      session: s,
                      onTap: () => _openSession(s),
                      onDelete: () => _confirmDeleteSaved(s),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                ],
                if (bundled.isNotEmpty) ...[
                  _SectionLabel(title: t.homeBuiltinSessions),
                  const SizedBox(height: 8),
                  for (final s in bundled) ...[
                    SessionCard(
                      session: s,
                      onTap: () => _openSession(s),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.homeHeaderTitle,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.homeHeaderSubtitle,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionsBundle {
  final List<Session> bundled;
  final List<Session> saved;
  const _SessionsBundle({required this.bundled, required this.saved});
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppTheme.accent,
      ),
    );
  }
}

/// Carte de séance enveloppée dans un `Dismissible` pour permettre la
/// suppression par swipe horizontal. Confirmation gérée par `onDelete`
/// (qui peut afficher un dialog avant de retourner).
class _SwipeToDeleteCard extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  const _SwipeToDeleteCard({
    super.key,
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Dismissible(
      key: ValueKey('dismiss_${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        // On gère la suppression côté parent (qui rafraîchit la liste).
        // Retourner false ici pour ne pas retirer le widget tant que
        // le rebuild via setState n'a pas eu lieu.
        await onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFEF5350).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, color: Color(0xFFEF5350)),
            const SizedBox(width: 8),
            Text(
              t.commonDelete,
              style: const TextStyle(
                color: Color(0xFFEF5350),
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
      child: SessionCard(
        session: session,
        onTap: onTap,
      ),
    );
  }
}
