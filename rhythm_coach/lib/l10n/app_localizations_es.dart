// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'BeatBitch';

  @override
  String get modeSelectionAppBarTitle => 'BEATBITCH';

  @override
  String get modeSelectionProfileTooltip => 'Perfil e insignias';

  @override
  String get modeSelectionSoundsTooltip => 'Aprende los sonidos';

  @override
  String get modeSelectionHeaderTitle => 'Elige tu modo';

  @override
  String get modeSelectionHeaderSubtitle =>
      'Apoya el teléfono, escucha, ejecuta.';

  @override
  String get modeSelectionScenarioTitle => 'ESCENARIO';

  @override
  String get modeSelectionScenarioSubtitle => 'Sesiones preescritas.';

  @override
  String get modeSelectionCareerTitle => 'CARRERA';

  @override
  String get modeSelectionCareerSubtitle =>
      'Sesiones generadas. Termina para desbloquear el siguiente nivel.';

  @override
  String get homeAppBarTitle => 'ESCENARIO';

  @override
  String get homeCameraTestTooltip => 'Prueba de cámara (holds)';

  @override
  String get homeDeleteSessionTitle => '¿Eliminar esta sesión?';

  @override
  String homeDeleteSessionContent(String sessionName) {
    return '«$sessionName» será eliminada de tus escenarios.';
  }

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonContinue => 'Continuar';

  @override
  String get commonAdd => 'Añadir';

  @override
  String homeLoadError(String error) {
    return 'Error al cargar las sesiones:\n$error';
  }

  @override
  String get homeEmpty => 'No hay sesión disponible.';

  @override
  String get homeMySessions => 'Mis sesiones';

  @override
  String get homeBuiltinSessions => 'Sesiones integradas';

  @override
  String get homeHeaderTitle => 'Elige tu sesión';

  @override
  String get homeHeaderSubtitle => 'Apoya el teléfono, escucha, ejecuta.';

  @override
  String get sessionStopTitle => '¿Detener la sesión?';

  @override
  String get sessionStopContent => 'Perderás tu progreso.';

  @override
  String get sessionStopConfirm => 'Detener';

  @override
  String get sessionVoiceLabel => 'Voz';

  @override
  String get sessionAmbienceLabel => 'Ambiente';

  @override
  String get sessionBegRequestLabel => 'PEDIDO';

  @override
  String get sessionBegSupplicateLabel => 'SUPLICA';

  @override
  String get sessionStateIdle => 'LISTA';

  @override
  String get sessionStateRunning => 'EN CURSO';

  @override
  String get sessionStatePaused => 'PAUSADA';

  @override
  String get sessionStateFinished => 'HECHO';

  @override
  String get sessionStateFailing => 'FALLO';

  @override
  String get sessionFailPhasePhrase => 'Frase de fallo';

  @override
  String get sessionFailPhaseBreath => 'Respiración';

  @override
  String get sessionFailPhasePunishment => 'Castigo';

  @override
  String get sessionStartPrompt =>
      'Inicia la sesión para escuchar las instrucciones.';

  @override
  String get sessionFailButton => 'NO PUEDO';

  @override
  String get sessionIntroBriefing => 'BRIEFING';

  @override
  String get sessionIntroReplay => 'Repetir';

  @override
  String get sessionIntroReady => 'ESTOY LISTA';

  @override
  String get sessionPausedIndicator => 'PAUSADA';

  @override
  String get sessionPrepInPlace => 'EN POSICIÓN';

  @override
  String get sessionPrepInstruction => 'Apoya el teléfono y ponte en posición.';

  @override
  String get sessionFinishedTitle => 'SESIÓN COMPLETADA';

  @override
  String sessionFinishedDuration(String duration) {
    return 'Duración: $duration';
  }

  @override
  String get sessionFinishedDefaultEnd => '¡Gracias!';

  @override
  String get sessionFinishedBadgesTitle => 'Nuevos niveles de insignia';

  @override
  String get sessionFinishedNoNewBadges =>
      'Ningún nivel nuevo esta vez — el próximo será.';

  @override
  String get sessionFinishedMilestonesTitle => 'Lecciones aprendidas';

  @override
  String get sessionFinishedEncore => 'QUIERO MÁS…';

  @override
  String get sessionFinishedSaved => 'GUARDADA';

  @override
  String get sessionFinishedSaving => 'GUARDANDO…';

  @override
  String get sessionFinishedSaveButton => 'GUARDAR ESTA SESIÓN';

  @override
  String sessionFinishedSavedSnack(String name) {
    return '«$name» guardada en tus escenarios.';
  }

  @override
  String sessionSaveDefaultName(int day, int month) {
    return 'Mi sesión $day/$month';
  }

  @override
  String get sessionSaveDialogTitle => 'Guardar la sesión';

  @override
  String get sessionSaveDialogContent =>
      'Dale un nombre — aparecerá en la lista ESCENARIO.';

  @override
  String get sessionSaveDialogHint => 'Nombre de la sesión';

  @override
  String get sessionSaveDialogConfirm => 'Guardar';

  @override
  String get cameraTestEndButton => 'Volver';

  @override
  String get profileAppBarTitle => 'PERFIL';

  @override
  String profileLoadError(String error) {
    return 'Error:\n$error';
  }

  @override
  String get profileAnatomySection => 'ANATOMÍA';

  @override
  String get profileAnatomyHasBalls => 'Incluir testículos';

  @override
  String get profileAnatomyHasBallsSubtitle =>
      'Desactiva si tu configuración no los tiene (juguete sin testículos, otro). El coach dejará de dirigir acciones a esa zona.';

  @override
  String get profileStatsSection => 'ESTADÍSTICAS';

  @override
  String get profileStatsEmpty =>
      'Aún sin estadísticas. Termina algunas sesiones para revelar tus contadores.';

  @override
  String get profileBadgesSection => 'INSIGNIAS';

  @override
  String get profileBadgesEmpty => 'Aún sin insignia desbloqueada.';

  @override
  String profileLevel(int level) {
    return 'Nivel $level';
  }

  @override
  String get profileReputationUnit => 'pts de reputación';

  @override
  String get reputationTierBonneEleve => 'Buena alumna';

  @override
  String get reputationTierPetiteSuceuse => 'Mamadora novata';

  @override
  String get reputationTierSuceuseConfirmee => 'Mamadora experimentada';

  @override
  String get reputationTierPuteReconnue => 'Puta reconocida';

  @override
  String get reputationTierPuteConsacree => 'Puta consagrada';

  @override
  String get reputationTierReineDesSuceuses => 'Reina de las mamadoras';

  @override
  String get reputationTierReineDesPutes => 'Reina de las putas';

  @override
  String get careerInvestmentBarTitle => 'Tiempo total';

  @override
  String careerInvestmentSessions(int count) {
    return '$count sesiones';
  }

  @override
  String careerInvestmentNextCoach(String name, String remaining) {
    return 'Próximo coach: $name ($remaining)';
  }

  @override
  String get careerInvestmentAllUnlocked => 'Todos los coaches desbloqueados.';

  @override
  String get profileStatSessionsCompleted => 'Sesiones completadas';

  @override
  String get profileStatNoFailStreak => 'Racha sin fallos';

  @override
  String get profileStatDailyStreak => 'Racha diaria';

  @override
  String get profileStatTotalTime => 'Tiempo total';

  @override
  String get profileStatThroatfucks => 'Gargantas profundas';

  @override
  String get profileStatBiffles => 'Vergazos';

  @override
  String get profileStatHoldFullMax => 'Hold profundo más largo';

  @override
  String get profileStatHoldThroatTotal => 'Hold garganta (total)';

  @override
  String get profileStatHoldFullTotal => 'Hold a fondo (total)';

  @override
  String get profileStatEncores => 'Bises pedidos';

  @override
  String get profileStatQuickies => 'Rapiditos completados';

  @override
  String get profileStatModesUsed => 'Modos usados';

  @override
  String get profileCapabilitiesSection => 'CAPACIDADES';

  @override
  String get profileCapabilitiesEmpty =>
      'Aún nada que mostrar — tus capacidades se revelan a medida que juegas.';

  @override
  String profileCapBpm(int n) {
    return '$n BPM';
  }

  @override
  String get profileCapApnea => 'Apnea';

  @override
  String get profileCapEngagement => 'Garganta comprometida';

  @override
  String get profileCapCrossingsThroat => 'Barrera de la garganta';

  @override
  String get profileCapCrossingsFull => 'Barrera de la garganta (profundo)';

  @override
  String get profileCapCrossingsLifetime => 'Cruces (total)';

  @override
  String get profileCapRhythmFastShallow => 'Ritmo boca — rápido';

  @override
  String get profileCapRhythmFastThroat => 'Ritmo garganta — rápido';

  @override
  String get profileCapRhythmFastFull => 'Ritmo profundo — rápido';

  @override
  String get profileCapRhythmSlowShallow => 'Ritmo boca — lento';

  @override
  String get profileCapRhythmSlowThroat => 'Ritmo garganta — lento';

  @override
  String get profileCapRhythmSlowFull => 'Ritmo profundo — lento';

  @override
  String get profileCapRhythmDepth => 'Profundidad del ritmo';

  @override
  String get profileCapRhythmMotion => 'Movimiento sin pausa';

  @override
  String get profileCapHoldThroat => 'Hold garganta';

  @override
  String get profileCapHoldFull => 'Hold profundo';

  @override
  String get profileCapNoSwallow => 'Sin tragar';

  @override
  String get profileCapBiffle => 'Vergazo';

  @override
  String get profileCapBiffleFast => 'Vergazo — rápido';

  @override
  String get profileCapEffortNoBreath => 'Esfuerzo sin descanso';

  @override
  String get profileCapBreathMinDose => 'Respiración más corta';

  @override
  String get profileCapLickDepth => 'Profundidad de lengua';

  @override
  String get profileCapLickStreak => 'Lengua sin pausa';

  @override
  String get profileCapHandStreak => 'Mano sin pausa';

  @override
  String get profileDiagnosticSection => 'DIAGNÓSTICO';

  @override
  String get profileDiagnosticDescription =>
      'Exporta un archivo JSON con tus datos de progreso — útil para reportar un bug. Nada se envía automáticamente, tú decides qué hacer con él.';

  @override
  String get profileDiagnosticExportButton => 'Exportar mis datos';

  @override
  String get profileDiagnosticSheetTitle => 'Exportar mis datos';

  @override
  String get profileDiagnosticSheetIntro => 'El archivo contiene:';

  @override
  String get profileDiagnosticItemCareer =>
      'Carrera: tu nivel máximo, sesiones completadas, hitos conseguidos.';

  @override
  String get profileDiagnosticItemStats =>
      'Estadísticas: contadores de sesión (tiempo total, gargantas profundas, holds, rachas…).';

  @override
  String get profileDiagnosticItemCapabilities =>
      'Capacidades: tus récords y zonas de confort por eje.';

  @override
  String get profileDiagnosticItemAnatomy =>
      'Anatomía: los toggles de tu perfil (si tienes huevos).';

  @override
  String get profileDiagnosticItemPreferences =>
      'Preferencias: idioma, voz, visualización, sorpresas, debug.';

  @override
  String get profileDiagnosticItemBadges =>
      'Insignias: los niveles que has desbloqueado.';

  @override
  String get profileDiagnosticIncludeNicknames =>
      'Incluir mis apodos personalizados';

  @override
  String get profileDiagnosticIncludeNicknamesSubtitle =>
      'Desactivado por defecto — pueden contener un nombre real.';

  @override
  String get profileDiagnosticShareButton => 'Compartir';

  @override
  String get profileDiagnosticSaveButton => 'Guardar';

  @override
  String get profileDiagnosticDownloadButton => 'Descargar';

  @override
  String get profileDiagnosticCancel => 'Cancelar';

  @override
  String get profileDiagnosticShareSubject => 'Exportación BeatBitch';

  @override
  String get profileDiagnosticShareSnackbar =>
      'Exportación lista para compartir.';

  @override
  String get profileDiagnosticSavedSnackbar => 'Archivo guardado.';

  @override
  String profileDiagnosticErrorSnackbar(String error) {
    return 'Exportación fallida: $error';
  }

  @override
  String get profileResetSection => 'ZONA DE PELIGRO';

  @override
  String get profileResetButton => 'Reiniciar todo';

  @override
  String get profileResetDialogTitle => '¿Reiniciar todo?';

  @override
  String get profileResetDialogMessage =>
      'Esto borra todas tus estadísticas, capacidades, insignias, progresión de carrera y puntos de especialización. Irreversible.';

  @override
  String get profileResetCancel => 'Cancelar';

  @override
  String get profileResetConfirm => 'Borrar todo';

  @override
  String get profileResetDoneSnackbar => 'Perfil reiniciado.';

  @override
  String get careerAppBarTitle => 'CARRERA';

  @override
  String get careerSpecializationTooltip => 'Especialización';

  @override
  String careerLoadError(String error) {
    return 'Error al cargar:\n$error';
  }

  @override
  String get careerDurationSection => 'Duración';

  @override
  String get careerQuickieToggle => 'Rapidito';

  @override
  String get careerQuickieSubtitle => '6 min — intenso';

  @override
  String get careerQuickieDescription =>
      '6 min, intenso de principio a fin. Para cuando no tienes tiempo.';

  @override
  String get sessionLengthBacheeLabel => 'Rapidito';

  @override
  String get sessionLengthBacheeDuration => '~6 min';

  @override
  String get sessionLengthBacheeDescription =>
      'Express, intenso de principio a fin.';

  @override
  String get sessionLengthCourteLabel => 'Corta';

  @override
  String get sessionLengthCourteDuration => '~12 min';

  @override
  String get sessionLengthCourteDescription =>
      'Formato compacto, un reto posible.';

  @override
  String get sessionLengthMoyenneLabel => 'Media';

  @override
  String get sessionLengthMoyenneDuration => '~25 min';

  @override
  String get sessionLengthMoyenneDescription =>
      'Hasta dos hitos, contenido variado.';

  @override
  String get sessionLengthLongueLabel => 'Larga';

  @override
  String get sessionLengthLongueDuration => '~45 min';

  @override
  String get sessionLengthLongueDescription =>
      'Sesión completa, varios retos intercalados.';

  @override
  String get careerChallengesToggle => 'Retos intra-sesión';

  @override
  String get careerChallengesDescription =>
      'Un reto opcional alrededor del 60% de la sesión. Se calibra rápido, puede acelerar tu progresión de nivel.';

  @override
  String get challengePassButton => 'PASAR';

  @override
  String get challengeGoButton => 'AGUANTAR';

  @override
  String get challengeHoldHintLive => 'Mantén el dedo en la pantalla';

  @override
  String get challengeHoldHintAtSeuil =>
      'Suelta para parar, o sigue aguantando';

  @override
  String get challengeHoldHintTolerance => 'Vuelve a poner el dedo';

  @override
  String get challengeCountdownReleaseRetry => 'Mantén el dedo esta vez.';

  @override
  String challengeBannerCountdown(int digit) {
    return '$digit';
  }

  @override
  String get challengeAttemptDefault =>
      'Reto: vamos a empujar tu límite. Mantén pulsado AGUANTAR cuando estés lista, contaré tres dos uno antes de empezar. Mantén el dedo en la pantalla mientras aguantes.';

  @override
  String get challengeAttemptTutorialHoldThroat =>
      'Primer reto: aguantarás en profundo durante cinco segundos. Mantén pulsado AGUANTAR, no quites el dedo de la pantalla. Si sueltas antes del umbral, fallaste. En el umbral el botón se pone verde: suelta para parar, o sigue aguantando para empujar más allá.';

  @override
  String get challengeExtensionDefault =>
      'Puedes quedarte más tiempo si quieres, o soltar.';

  @override
  String get challengeSuccessDefault =>
      'Aguantaste hasta el final. Buena chica.';

  @override
  String get challengeStopDefault => 'Aguantaste hasta el umbral. Bien hecho.';

  @override
  String get challengeFailDefault =>
      'Te rompiste antes del umbral. No te preocupes, lo conseguirás la próxima.';

  @override
  String get challengeSkipDefault =>
      'Como quieras, lo guardamos para la próxima.';

  @override
  String challengeBannerHoldThroat(int seconds) {
    return 'Aguanta en profundo $seconds segundos';
  }

  @override
  String challengeBannerHoldFull(int seconds) {
    return 'Aguanta hasta el fondo $seconds segundos';
  }

  @override
  String challengeBannerHoldGeneric(int seconds) {
    return 'Aguanta la posición $seconds segundos';
  }

  @override
  String challengeBannerRhythm(int bpm) {
    return 'Sube el ritmo hasta $bpm BPM';
  }

  @override
  String challengeBannerRhythmShallow(int bpm) {
    return 'Ritmo superficial — sube hasta $bpm BPM';
  }

  @override
  String challengeBannerRhythmThroat(int bpm) {
    return 'Ritmo hasta la garganta — sube hasta $bpm BPM';
  }

  @override
  String challengeBannerRhythmFull(int bpm) {
    return 'Ritmo hasta el fondo — sube hasta $bpm BPM';
  }

  @override
  String challengeBannerGorgeCrossingsThroat(int count, int bpm) {
    return '$count cruces hasta la garganta a $bpm BPM';
  }

  @override
  String challengeBannerGorgeCrossingsFull(int count, int bpm) {
    return '$count cruces hasta el fondo a $bpm BPM';
  }

  @override
  String get challengeBannerGorgeApnee =>
      'Apnea de garganta — alterna holds y estocadas profundas';

  @override
  String get challengeBannerGorgeEngagement =>
      'Mantén la garganta en juego — holds y ritmos profundos';

  @override
  String get challengeBannerDepthMax =>
      'Empuja la profundidad un nivel más en ritmo';

  @override
  String challengeBannerMotionStreak(int seconds) {
    return 'Ritmo sin parar $seconds segundos — varía posiciones y BPM';
  }

  @override
  String challengeBannerNoBreathStreak(int seconds) {
    return '$seconds s sin respirar — ritmo y holds';
  }

  @override
  String challengeBannerNoSwallowStreak(int seconds) {
    return 'Boca abierta, lengua fuera — $seconds s sin tragar';
  }

  @override
  String challengeBannerBiffleStreak(int seconds) {
    return 'Aguanta los vergazos durante $seconds segundos';
  }

  @override
  String challengeBannerBiffle(int bpm) {
    return 'Aguanta los vergazos hasta $bpm BPM';
  }

  @override
  String get challengeBannerGeneric => 'Empuja tu límite';

  @override
  String get challengeBannerThresholdReached =>
      'Umbral alcanzado — sigue o para';

  @override
  String get careerIncludeHandToggle => 'Incluir estimulación con la mano';

  @override
  String get careerIncludeHandSubtitle =>
      'También desactiva los vergazos (biffle) — ambos necesitan la mano.';

  @override
  String get careerIncludeHandMilestoneLocked =>
      'Bloqueado en esta sesión — el hito de aprendizaje usa la mano.';

  @override
  String specPointsBannerTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puntos sin asignar',
      one: '1 punto sin asignar',
    );
    return '$_temp0';
  }

  @override
  String get specPointsBannerSubtitle =>
      'Has ganado puntos de especialización. Asígnalos antes de empezar.';

  @override
  String get specPointsBannerCta => 'ASIGNAR';

  @override
  String get careerStartButton => 'INICIAR';

  @override
  String careerCompletedSessions(int count) {
    return 'Sesiones completadas: $count';
  }

  @override
  String careerSessionName(int level) {
    return 'Carrera';
  }

  @override
  String careerSessionNameQuickie(int level) {
    return 'Carrera — rapidito';
  }

  @override
  String get careerMilestonesBranchesPrefix => 'Rama: ';

  @override
  String get careerMilestonesBranchesPrefixPlural => 'Ramas: ';

  @override
  String get cameraTestAppBarTitle => 'PRUEBA DE CÁMARA';

  @override
  String get cameraPreviewUnavailable => 'Vista previa no disponible';

  @override
  String get cameraStartSession => 'Iniciar la sesión';

  @override
  String get cameraPermissionDenied =>
      'Permiso de cámara denegado o inicialización fallida. Activa la cámara en los ajustes de Android.';

  @override
  String get cameraUnknownError => 'Error desconocido.';

  @override
  String get cameraInitializing => 'Inicializando cámara…';

  @override
  String get cameraRecalibrate => 'Recalibrar';

  @override
  String get cameraCalibrate => 'Calibrar (10s)';

  @override
  String cameraAxisLabel(String axis) {
    return 'Eje: $axis';
  }

  @override
  String get cameraAxisHorizontal => 'horizontal';

  @override
  String get cameraAxisVertical => 'vertical';

  @override
  String cameraLivePositionLabel(String position) {
    return 'Posición en vivo: $position';
  }

  @override
  String get cameraCalibrationTitle => 'Calibración';

  @override
  String get cameraCalibrationInstructions =>
      'Durante 10 segundos, haz 3 o 4 movimientos lentos y amplios — desde el punto más alto (punta) al más bajo (fondo). La app deducirá el eje y los límites de los 5 niveles.';

  @override
  String get cameraCalibratingMessage =>
      'Calibrando… haz movimientos lentos y profundos.';

  @override
  String get cameraCalibratedTitle => 'Calibración OK';

  @override
  String cameraCalibrationSummary(String axis, String range, int samples) {
    return 'Eje: $axis — rango $range ($samples muestras)';
  }

  @override
  String get cameraCalibratedHint =>
      'Puedes iniciar la sesión. Si la polaridad está invertida (punta ↔ fondo), recalibra en el sentido correcto.';

  @override
  String cameraCalibrationFailedRange(String range) {
    return 'Rango demasiado pequeño ($range). Prueba con movimientos más amplios.';
  }

  @override
  String cameraCalibrationFailed(String error) {
    return 'Calibración fallida: $error';
  }

  @override
  String get cameraReturnButton => 'Volver';

  @override
  String get specAppBarTitle => 'ESPECIALIZACIÓN';

  @override
  String specLoadError(String error) {
    return 'Error:\n$error';
  }

  @override
  String get specNotEnoughPoints => 'Puntos insuficientes.';

  @override
  String get specRespecConfirmTitle => '¿Reiniciar tu especialización?';

  @override
  String get specRespecConfirmContent =>
      'Todos tus puntos de especialización se reiniciarán, perderás 1 nivel global y no podrás volver a respecializar en 3 días.';

  @override
  String get specRespecConfirmAction => 'Respec';

  @override
  String get specIntro =>
      'Asigna tus puntos para decirle al motor lo que te gusta. Cuanto más inviertes en una rama, más se inclina el generador hacia ese estilo — sin desequilibrar tus estadísticas.';

  @override
  String get specPointsAvailableLabel => 'puntos disponibles';

  @override
  String specSpentLabel(int spent, int cap) {
    return '$spent / $cap asignados';
  }

  @override
  String get specPointsUnit => 'pts';

  @override
  String get specRespecActiveLabel => 'Reiniciar especialización (-1 nivel)';

  @override
  String specRespecCooldownLabel(int hours) {
    return 'Respec en ${hours}h';
  }

  @override
  String formatDurationSeconds(int s) {
    return '${s}s';
  }

  @override
  String formatDurationMinutes(int m) {
    return '${m}m';
  }

  @override
  String formatDurationMinutesSeconds(int m, int s) {
    return '${m}m ${s}s';
  }

  @override
  String formatDurationHours(int h) {
    return '${h}h';
  }

  @override
  String formatDurationHoursMinutes(int h, String mm) {
    return '${h}h $mm';
  }

  @override
  String formatDaysShort(int d) {
    return '${d}d';
  }

  @override
  String get settingsAppBarTitle => 'AJUSTES';

  @override
  String get settingsLanguageSection => 'Idioma';

  @override
  String get settingsLanguageSubtitle =>
      'Idioma de la interfaz, frases del coach y contenido editorial.';

  @override
  String get settingsLanguageSystem => 'Seguir al sistema';

  @override
  String get settingsLanguageFrench => 'Français';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get languagePickerTitle => 'Elige tu idioma';

  @override
  String get languagePickerBody =>
      'El idioma de tu teléfono no está (todavía) disponible en BeatBitch. Elige el que quieras usar — podrás cambiarlo más tarde en los ajustes (icono ecualizador).';

  @override
  String languageNewlyAvailableTitle(String language) {
    return 'Disponible en $language';
  }

  @override
  String languageNewlyAvailableBody(String language) {
    return 'BeatBitch ya está traducida a $language, el idioma de tu teléfono. Puedes cambiar a este idioma, o mantener el actual (cambiable en cualquier momento desde los ajustes).';
  }

  @override
  String languageNewlyAvailableSwitch(String language) {
    return 'Cambiar a $language';
  }

  @override
  String get languageNewlyAvailableKeep => 'Mantener idioma actual';

  @override
  String get soundsAppBarTitle => 'SONIDOS';

  @override
  String get soundsStopLoopTooltip => 'Parar el loop';

  @override
  String get soundsIdentitySection => 'Identidad';

  @override
  String soundsIdentitySubtitle(String token) {
    return 'El marcador «$token» en las frases se sustituye por una elección aleatoria entre tu nombre (si lo has introducido) y la lista de apodos de abajo.';
  }

  @override
  String get soundsFirstNameLabel => 'Nombre (opcional)';

  @override
  String get soundsFirstNameHelper =>
      'Vacío = sin nombre en el pool. Las voces de red pronuncian los nombres de forma desigual.';

  @override
  String get soundsTestSubstitution => 'Probar sustitución';

  @override
  String get soundsDefaultNicknames => 'Apodos por defecto';

  @override
  String get soundsCustomNicknames => 'Apodos personalizados';

  @override
  String get soundsNoCustomNicknames => 'Aún sin apodo personalizado.';

  @override
  String get soundsAddNicknameLabel => 'Añadir un apodo';

  @override
  String get soundsRemoveNicknameTooltip => 'Eliminar';

  @override
  String get soundsVoiceSection => 'Voz';

  @override
  String get soundsVoiceSubtitle =>
      'Elige la voz y la velocidad. El botón «Probar» pronuncia una frase de muestra.';

  @override
  String get soundsRateLabel => 'Velocidad';

  @override
  String get soundsPitchLabel => 'Tono';

  @override
  String get soundsTestVoice => 'Probar la voz';

  @override
  String get soundsNoVoiceDetected =>
      'Ninguna voz compatible detectada en este dispositivo.';

  @override
  String get soundsAmbienceSection => 'Ambiente';

  @override
  String get soundsAmbienceSubtitle =>
      'Pack de fondo reproducido durante las sesiones. La selección se comparte con la pantalla de juego. Toca un modo para escuchar.';

  @override
  String get soundsPackLabel => 'Pack';

  @override
  String get soundsPackNoneLabel => 'Ninguno';

  @override
  String soundsModeLabel(String name) {
    return 'Modo $name';
  }

  @override
  String get soundsNoTrack => 'sin pista para este modo';

  @override
  String get soundsRhythmPositionsSection => 'Posiciones (ritmo)';

  @override
  String get soundsRhythmPositionsSubtitle =>
      'Tono del bip por profundidad. De más agudo a más grave.';

  @override
  String get soundsLickPositionsSection => 'Posiciones (lengua)';

  @override
  String get soundsLickPositionsSubtitle =>
      'Mismas posiciones, volumen más bajo para el efecto «ligero».';

  @override
  String soundsLickPositionLabel(String name) {
    return '$name · lengua';
  }

  @override
  String soundsLickPositionSubtitle(String name) {
    return 'Posición $name en modo lengua';
  }

  @override
  String get soundsHoldSection => 'Hold (posición + capa overlay)';

  @override
  String get soundsHoldSubtitle =>
      'Bip de posición reproducido simultáneamente con la capa hold (más densa).';

  @override
  String soundsHoldButton(String position) {
    return 'Hold $position';
  }

  @override
  String soundsHoldPositionSubtitle(String name) {
    return '$name + capa hold';
  }

  @override
  String get soundsSuckleSection => 'Mamada (succión)';

  @override
  String get soundsSuckleSubtitle =>
      'Sorbo húmedo pulsado. Una pulsación reproduce un único golpe; en sesión se repite cada ~1,2 s durante la duración del paso.';

  @override
  String soundsSuckleButton(String position) {
    return 'Mamar $position';
  }

  @override
  String soundsSucklePositionSubtitle(String name) {
    return 'Mamada en $name';
  }

  @override
  String get soundsSpecificSounds => 'Sonidos específicos';

  @override
  String get soundsBiffleOneShot => 'Vergazo (one-shot)';

  @override
  String get soundsBiffleOneShotSubtitle =>
      'Sonido corto y percusivo. En loop, sigue los BPM.';

  @override
  String get soundsBreath => 'Respiración';

  @override
  String get soundsBreathSubtitle => 'Tono largo y grave, efecto «liberación».';

  @override
  String get soundsLoopsDemoSection => 'Demos de loop';

  @override
  String get soundsLoopsDemoSubtitle =>
      'Ajusta los BPM, inicia el loop, escucha, para.';

  @override
  String get soundsBpmLabel => 'BPM';

  @override
  String get soundsLoopActive => 'EN CURSO';

  @override
  String get soundsLoopRhythmHeadMid => 'Ritmo cabeza→medio';

  @override
  String get soundsLoopRhythmThroatFull => 'Ritmo garganta→fondo';

  @override
  String get soundsLoopLickTipHead => 'Lengua punta→cabeza';

  @override
  String get soundsLoopBiffle => 'Vergazo';

  @override
  String get soundsPosDescTip => 'Muy alto, ligero';

  @override
  String get soundsPosDescHead => 'Alto';

  @override
  String get soundsPosDescMid => 'Medio';

  @override
  String get soundsPosDescThroat => 'Bajo';

  @override
  String get soundsPosDescFull => 'Muy bajo, denso';

  @override
  String get soundsPosDescBalls => 'Muy bajo y apagado, zona lateral';

  @override
  String get soundsPosDescSuckle =>
      'Tono medio húmedo, pulso de succión continuo';

  @override
  String get soundsDebugSection => 'Debug';

  @override
  String get soundsDebugSubtitle => 'Opciones técnicas para el desarrollo.';

  @override
  String get soundsDebugShowTimer => 'Mostrar temporizador';

  @override
  String get soundsDebugShowTimerSubtitle =>
      'Sustituye la animación de movimiento por el contador mm:ss durante la sesión.';

  @override
  String get soundsDebugShowStaminaBar => 'Mostrar barra de stamina';

  @override
  String get soundsDebugShowStaminaBarSubtitle =>
      'Muestra el perfil de stamina proyectado durante una sesión de Carrera.';

  @override
  String get soundsDebugShowHumiliationBar => 'Mostrar barra de humillación';

  @override
  String get soundsDebugShowHumiliationBarSubtitle =>
      'Muestra la puntuación de humillación acumulada durante la sesión.';

  @override
  String get soundsDebugShowObedienceBar => 'Mostrar puntuación de obediencia';

  @override
  String get soundsDebugShowObedienceBarSubtitle =>
      'Muestra la puntuación de obediencia 0–100 (baja con cada fallo, sube con los castigos).';

  @override
  String get soundsDebugShowSalivaBar => 'Mostrar barra de saliva';

  @override
  String get soundsDebugShowSalivaBarSubtitle =>
      'Muestra la barra de saliva 0–máx acumulada durante la sesión. Sube con lengua/ritmo/hold profundos, baja con respiración/mano. Trago automático a 75 cuando tragar está permitido.';

  @override
  String get soundsDebugShowSessionControls => 'Mostrar pausa / parar';

  @override
  String get soundsDebugShowSessionControlsSubtitle =>
      'Solo debug: en prod la sesión va sin interacción (móvil apoyado), solo el botón FALLO sigue útil.';

  @override
  String get soundsDebugShowModeBadge => 'Mostrar modo / BPM / posición';

  @override
  String get soundsDebugShowModeBadgeSubtitle =>
      'Solo debug: en prod la animación basta para indicar lo que pasa.';

  @override
  String get debugBarLabelHumiliation => 'HUMIL.';

  @override
  String get debugBarLabelObedience => 'OBED.';

  @override
  String get debugBarLabelSaliva => 'SALIVA';

  @override
  String get soundsDebugCameraHoldCheck => 'Verificación de cámara en holds';

  @override
  String get soundsDebugCameraHoldCheckSubtitle =>
      'Durante los holds, la cámara frontal comprueba que se mantiene la posición. El coach te avisa breve si te desvías. Requiere calibrar la cámara antes (icono cámara en la pantalla ESCENARIO).';

  @override
  String get soundsDebugSkipSession => 'Botón «Terminar como éxito»';

  @override
  String get soundsDebugSkipSessionSubtitle =>
      'Muestra un botón en la sesión que la termina inmediatamente como éxito total (insignias, hitos, nivel). Útil para iterar sobre el contenido sin jugar.';

  @override
  String get soundsShowBackgroundMedia => 'Medios de fondo en sesión';

  @override
  String get soundsShowBackgroundMediaSubtitle =>
      'Muestra imágenes/GIFs de assets/backgrounds/ en el fondo, rotando con cada paso. Desactívalo para ver solo el degradado de ambiente.';

  @override
  String get sessionDebugFinishButton => 'DEBUG: terminar como éxito';

  @override
  String get soundsDebugScenarioButton => 'Debug — escenario de carrera';

  @override
  String get soundsDebugScenarioSubtitle =>
      'Visualiza una sesión generada sin jugarla: nivel, humil, obed, hitos, desbloqueos y simulación de Súplica / fallo.';

  @override
  String get careerDebugTitle => 'Debug — escenario de Carrera';

  @override
  String get careerDebugSectionParams => 'Parámetros';

  @override
  String get careerDebugSectionScenario => 'Escenario';

  @override
  String get careerDebugLevel => 'Nivel';

  @override
  String get careerDebugHumiliation => 'Humillación';

  @override
  String get careerDebugObedience => 'Obediencia';

  @override
  String get careerDebugIncludeHand => 'Incluir estimulación con la mano';

  @override
  String get careerDebugQuickie => 'Modo rapidito';

  @override
  String get careerDebugIntense => 'Modo intenso (post-Súplica)';

  @override
  String get careerDebugDurationOverride => 'Sobrescribir duración';

  @override
  String get careerDebugMilestoneBody => 'Hito cuerpo';

  @override
  String get careerDebugMilestoneFinal => 'Hito final';

  @override
  String get careerDebugUnlocks => 'Desbloqueos';

  @override
  String get careerDebugUnlocksLoadCurrent => 'Conseguidos';

  @override
  String get careerDebugUnlocksClear => 'Ninguno';

  @override
  String get careerDebugUnlocksAll => 'Todos';

  @override
  String get careerDebugAuto => 'Auto';

  @override
  String get careerDebugNone => 'Ninguno';

  @override
  String get careerDebugRegenerate => 'Regenerar';

  @override
  String get careerDebugShowTtsTexts => 'Mostrar textos TTS';

  @override
  String get careerDebugStatStamina => 'Stamina final';

  @override
  String get careerDebugStatHumilCap => 'Tope humil final';

  @override
  String get careerDebugTagMilestoneBody => 'HITO';

  @override
  String get careerDebugTagMilestoneFinal => 'HITO FINAL';

  @override
  String get careerDebugTagBoost => 'BOOST';

  @override
  String get careerDebugTagFinal => 'FINAL';

  @override
  String get careerDebugTagPostFinal => 'POST-FINAL';

  @override
  String get careerDebugTextOnly => 'SOLO-TEXTO';

  @override
  String get careerDebugHumilReq => 'req';

  @override
  String get careerDebugStepActionsTitle => 'Paso';

  @override
  String get careerDebugSimulateFail => 'Simular un fallo aquí';

  @override
  String get careerDebugSimulateSupplier => 'Simular una Súplica aquí';

  @override
  String get careerDebugClearFork => 'Limpiar la rama';

  @override
  String get careerDebugClearAnnotation => 'Limpiar la anotación';

  @override
  String get careerDebugForkBanner => 'RAMA DE SÚPLICA';

  @override
  String get careerDebugForkFrom => 'Desde';

  @override
  String get careerDebugForkSteps => 'pasos';

  @override
  String get careerDebugFailSnapshotTitle => 'FALLO simulado';

  @override
  String get careerDebugFailSnapshotNext => 'Reanuda en el paso';

  @override
  String get careerDebugFailSnapshotNoNext =>
      'Sin paso jugable tras este fallo (fin de la sesión).';

  @override
  String get positionTip => 'Punta';

  @override
  String get positionHead => 'Glande';

  @override
  String get positionMid => 'Medio';

  @override
  String get positionThroat => 'Garganta';

  @override
  String get positionFull => 'Fondo';

  @override
  String get positionBalls => 'Huevos';

  @override
  String get modeShortRhythm => 'MAMAR';

  @override
  String get modeShortHold => 'PROF.';

  @override
  String get modeShortLick => 'LENGUA';

  @override
  String get modeShortBiffle => 'GOLPE';

  @override
  String get modeShortBreath => 'RESPIRA';

  @override
  String get modeShortBeg => 'SUPLICA';

  @override
  String get modeShortFreestyle => 'LIBRE';

  @override
  String get modeShortHand => 'MANO';

  @override
  String get modeShortSuckle => 'SUCC.';

  @override
  String get badgeTierBronze => 'Bronce';

  @override
  String get badgeTierSilver => 'Plata';

  @override
  String get badgeTierGold => 'Oro';

  @override
  String get badgeTierPlatinium => 'Platino';

  @override
  String badgeUnlockAnnouncement(String name, String tier) {
    return 'Insignia desbloqueada: $name, nivel $tier.';
  }

  @override
  String get badgeNameMarathonien => 'Maratonista';

  @override
  String get badgeNameThroatQueen => 'Reina de la Garganta';

  @override
  String get badgeNameIronLungs => 'Pulmones de Hierro';

  @override
  String get badgeNameToutTerrain => 'Todoterreno';

  @override
  String get badgeNameSansBroncher => 'Sin Pestañear';

  @override
  String get badgeNameReguliere => 'Constante';

  @override
  String get badgeNameJamaisRassasiee => 'Insaciable';

  @override
  String get badgeNameVideCouilles => 'Vaciahuevos';

  @override
  String get badgeNameBouchePleine => 'Boca Llena';

  @override
  String get badgeNameRepeinte => 'Cubierta';

  @override
  String get badgeNameGobeuse => 'Tragadora';

  @override
  String get badgeNameNettoyeuse => 'Limpiadora';

  @override
  String get badgeNameSuppliante => 'Suplicante';

  @override
  String get badgeUnitMarathonien => 'minutos totales';

  @override
  String get badgeUnitThroatQueen => 'gargantas profundas totales';

  @override
  String get badgeUnitIronLungs => 'segundos del hold profundo más largo';

  @override
  String get badgeUnitToutTerrain => 'modos diferentes usados';

  @override
  String get badgeUnitSansBroncher => 'sesiones completas seguidas sin fallar';

  @override
  String get badgeUnitReguliere => 'días consecutivos con sesión';

  @override
  String get badgeUnitJamaisRassasiee => 'veces que pediste «más»';

  @override
  String get badgeUnitVideCouilles => 'rapiditos completados';

  @override
  String get badgeUnitBouchePleine => 'finales en la boca';

  @override
  String get badgeUnitRepeinte => 'finales en la cara';

  @override
  String get badgeUnitGobeuse => 'finales en la lengua';

  @override
  String get badgeUnitNettoyeuse => 'post-finales limpiados con la lengua';

  @override
  String get badgeUnitSuppliante => 'súplicas post-orgasmo';

  @override
  String get careerLevelTitleDebutante => 'Principiante';

  @override
  String get careerLevelTitleApprentieSuceuse => 'Aprendiz de mamadora';

  @override
  String get careerLevelTitlePetiteSalopeConfirmee => 'Putita confirmada';

  @override
  String get careerLevelTitleBoucheAPipe => 'Boca chupapollas';

  @override
  String get careerLevelTitleAvaleuse => 'Tragadora';

  @override
  String get careerLevelTitleThroatQueen => 'Reina de la Garganta';

  @override
  String get careerLevelTitleReineDuSloppy => 'Reina del Sloppy';

  @override
  String get careerLevelTitleTrouABiteOfficiel => 'Agujero oficial para polla';

  @override
  String get careerLevelTitleVideCouillesPro => 'Vaciahuevos Pro';

  @override
  String get careerLevelTitleReineDesPutes => 'Reina de las Putas';

  @override
  String get specBranchEnduranceLabel => 'Resistencia';

  @override
  String get specBranchEnduranceDesc =>
      'Aguanta. Más holds, duraciones más largas.';

  @override
  String get specBranchProfondeurLabel => 'Profundidad';

  @override
  String get specBranchProfondeurDesc =>
      'Llega hasta el fondo. Sesgo garganta / a fondo.';

  @override
  String get specBranchRythmeBiffleLabel => 'Ritmo y Vergazo';

  @override
  String get specBranchRythmeBiffleDesc =>
      'BPM más altos, vergazos más frecuentes.';

  @override
  String get specBranchObeissanceLabel => 'Obediencia';

  @override
  String get specBranchObeissanceDesc =>
      'Súplicas insistentes, ruegos sostenidos.';

  @override
  String get specBranchSloppyLabel => 'Sloppy';

  @override
  String get specBranchSloppyDesc =>
      'Lengua húmeda, vergazos lentos, más baba.';

  @override
  String get specBranchResilienceLabel => 'Resiliencia';

  @override
  String get specBranchResilienceDesc =>
      'Encaja los fallos. Castigos más duros.';

  @override
  String get coachPickerTitle => 'Elige un coach';

  @override
  String get coachPickerSection => 'COACH';

  @override
  String coachPickerTierLabel(int tier) {
    return 'NIVEL $tier';
  }

  @override
  String get coachBadgePrincipal => 'PRINCIPAL';

  @override
  String get coachBadgePalierAcquis => 'NIVEL DESBLOQUEADO';

  @override
  String get coachBadgeFreeTraining => 'ENTRENAMIENTO LIBRE';

  @override
  String get coachBadgeLocked => 'BLOQUEADO';

  @override
  String coachSummaryPrincipal(String title, int tier) {
    return '$title · Principal nivel $tier';
  }

  @override
  String coachSummaryFree(String title) {
    return '$title · entrenamiento libre';
  }

  @override
  String get coachFreeTrainingDialogTitle => 'Entrenamiento libre';

  @override
  String coachFreeTrainingDialogBody(String coachName) {
    return 'Vas a entrenar con $coachName. Progresarás en tus habilidades, pero tu medidor de nivel no se moverá.';
  }

  @override
  String coachFreeTrainingDialogHint(String principalName) {
    return 'Para avanzar en tu nivel, elige a $principalName.';
  }

  @override
  String coachFreeTrainingDialogChoosePrincipal(String principalName) {
    return 'Elegir a $principalName';
  }

  @override
  String get coachFreeTrainingDialogContinueAnyway => 'Continuar igualmente';

  @override
  String coachPrenomGateTitle(String coachName) {
    return '$coachName quiere conocerte';
  }

  @override
  String coachPrenomGateBody(String coachName) {
    return 'Antes de empezar la sesión con $coachName, dime tu nombre — no te hablará más de forma anónima.';
  }

  @override
  String get coachPrenomGateField => 'Tu nombre';

  @override
  String get coachPrenomGateConfirm => 'Continuar';

  @override
  String coachFreeTrainingBannerTitle(String coachName) {
    return 'Sesión libre con $coachName';
  }

  @override
  String coachFreeTrainingBannerBodyWithPrincipal(String principalName) {
    return 'Estás progresando en tus habilidades. Tu nivel no se mueve — para eso, elige a $principalName.';
  }

  @override
  String get coachFreeTrainingBannerBodyNoPrincipal =>
      'Estás progresando en tus habilidades. Tu nivel no se mueve.';

  @override
  String get coachFreeTrainingBannerSwitchAction => 'CAMBIAR';

  @override
  String coachErrorLockedTier(int tier) {
    return 'Este coach sigue bloqueado — alcanza el nivel $tier para desbloquearla.';
  }

  @override
  String coachErrorMinPlayerSeconds(String coachName, String duration) {
    return '$coachName se desbloquea a las $duration de tiempo de juego total.';
  }

  @override
  String coachErrorNoVoice(String coachName) {
    return '$coachName necesita una voz que no está disponible en este dispositivo. Instala una voz masculina TTS en los ajustes del sistema para desbloquearlo.';
  }

  @override
  String get coachBadgeNoVoice => 'SIN VOZ';

  @override
  String get unlockAnnouncementSloppyDroolBasic =>
      'A partir de ahora tu boca retiene más saliva, y lamer te genera más. Babea sobre mí, sé guarra.';

  @override
  String get unlockAnnouncementSloppyBiffleSlow =>
      'Los vergazos te hacen babear ahora. Tómalos con la boca bien abierta.';

  @override
  String get unlockAnnouncementSloppySwallowControl =>
      'Ya puedes retener la saliva cuando te lo ordene. Cuando te lo diga, no tragas.';

  @override
  String get unlockAnnouncementSloppySpit =>
      'Ya sabes escupir para mí. Cuando te lo pida, lo sueltas todo.';

  @override
  String get unlockAnnouncementSloppyDroolDeep =>
      'Cuando bajas a fondo, tu boca desborda aún más. Disfrútalo.';

  @override
  String get modeSelectionSurpriseTooltip => 'Recordatorios sorpresa';

  @override
  String get surpriseNotifTitle => 'Es la hora';

  @override
  String get surpriseNotifBody1 => 'Mámame ahora mismo';

  @override
  String get surpriseNotifBody2 => 'Quiero llenarte la boca YA';

  @override
  String get surpriseNotifBody3 => '¡De rodillas, es la hora!';

  @override
  String get surpriseSettingsAppBarTitle => 'Recordatorio sorpresa';

  @override
  String get surpriseSettingsHeaderSubtitle =>
      'Durante la ventana, la app puede enviar notificaciones a horas aleatorias. Al tocar, abre una sesión corta.';

  @override
  String get surpriseSettingsEnableLabel => 'Activar recordatorios';

  @override
  String get surpriseSettingsEnableSubtitle =>
      'Notificaciones aleatorias durante la ventana.';

  @override
  String get surpriseSettingsWindowLabel => 'Ventana horaria';

  @override
  String surpriseSettingsWindowValue(int minutes) {
    return '$minutes min';
  }

  @override
  String get surpriseSettingsAlertCountLabel => 'Número de recordatorios';

  @override
  String surpriseSettingsAlertCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordatorios',
      one: '1 recordatorio',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsDurationLabel => 'Duración de la sesión';

  @override
  String surpriseSettingsDurationValue(int minSec, int maxSec) {
    return '${minSec}s – ${maxSec}s';
  }

  @override
  String surpriseSettingsActiveStatus(String endTime) {
    return 'Activo hasta las $endTime';
  }

  @override
  String surpriseSettingsActiveAlertsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alertas restantes',
      one: '1 alerta restante',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsInactiveStatus => 'Ningún recordatorio programado';

  @override
  String get surpriseSettingsPermissionMissing =>
      'Autoriza las notificaciones en los ajustes del sistema.';

  @override
  String get surpriseSettingsExactAlarmMissing =>
      'Las alarmas exactas están denegadas por el sistema.';

  @override
  String get surpriseSettingsBatteryHintTitle => 'Optimización de batería';

  @override
  String get surpriseSettingsBatteryHintBody =>
      'En algunos móviles (Xiaomi, Huawei, Samsung), desactiva la optimización de batería para BeatBitch para garantizar los recordatorios.';

  @override
  String get surpriseSettingsOpenBatterySettings => 'Abrir los ajustes';

  @override
  String get adultGateTitle => 'Solo adultos';

  @override
  String get adultGateBody =>
      'BeatBitch contiene contenido sexual explícito: voz del coach cruda y dominante, textos explícitos y GIFs de fondo. Al continuar, confirmas que:\n\n• tienes al menos 18 años (o la mayoría de edad en tu país);\n• usarás la app en privado — el audio y los visuales no son adecuados para uso público;\n• entiendes que las frases pueden ser crudas y dominantes.';

  @override
  String get adultGateAccept => 'Tengo 18+, acepto';

  @override
  String get adultGateLeave => 'Salir';

  @override
  String get onboardingStep1Title =>
      'Mantén la pantalla a la vista al principio';

  @override
  String get onboardingStep1Body =>
      'En tus primeras sesiones, ten el móvil a la vista: la animación y las barras te ayudan a ajustar posiciones y ritmo. Cuando te acostumbres, podrás apoyarlo de lado y jugar manos libres, guiada por la voz y los bips.';

  @override
  String get onboardingStep2Title => 'Sube el volumen';

  @override
  String get onboardingStep2Body =>
      'El coach habla bajo y los bips son sutiles. Sube el volumen multimedia o usa auriculares/altavoz. La app no envía nada por Internet.';

  @override
  String get onboardingStep3Title => 'Configura voz y nombre';

  @override
  String get onboardingStep3Body =>
      'En la pantalla Perfil (icono silueta): introduce tu nombre, elige tus apodos, escoge el idioma de la interfaz y ajusta la voz por defecto (velocidad, timbre) — escucha una muestra. Las coaches de carrera usan sus propias voces fijas; solo la voz por defecto (sin carrera) es ajustable. Así el coach podrá llamarte por tu nombre.';

  @override
  String get onboardingNext => 'Siguiente';

  @override
  String get onboardingPrevious => 'Atrás';

  @override
  String get onboardingTestVoice => 'Probar mi voz';

  @override
  String get onboardingSkip => 'Más tarde';

  @override
  String get profileAboutSection => 'ACERCA DE';

  @override
  String profileAboutVersion(String appName, String version, String build) {
    return '$appName v$version (build $build)';
  }

  @override
  String get profileAboutOffline =>
      '100% offline — sin telemetría, nada se envía por la red.';

  @override
  String get profileUpdatesSection => 'ACTUALIZACIONES';

  @override
  String get profileUpdatesBody =>
      'BeatBitch es 100% offline y nunca busca actualizaciones por sí sola. Para enterarte cuando salga una nueva versión, instala Obtainium — una tienda Android open-source que vigila las páginas de GitHub Releases:\n\n• Obtainium: github.com/ImranR98/Obtainium\n• En Obtainium → «Add App», pega: github.com/bbstudioapp/beatbitch\n\nNingún tráfico de red sale de BeatBitch: Obtainium consulta GitHub por su cuenta, independientemente de la app.';

  @override
  String get profileDisclaimerSection => 'AVISO LEGAL';

  @override
  String get profileDisclaimerBody =>
      'BeatBitch es un juego para adultos consintientes, pensado para usarse en un contexto estrictamente privado. Usarlo de forma segura depende solo de ti: escucha a tu cuerpo, nunca mantengas una posición o duración que duela, y conserva siempre la capacidad de parar al momento (el botón «No puedo», o simplemente cerrar la app). No uses la app bajo los efectos de nada que afecte tu juicio.\n\nLas voces, textos y escenarios son ficción lúdica de dominación: ninguna frase es una orden real, y nada de lo que diga el coach debería hacerse jamás a otra persona sin su consentimiento explícito e informado.\n\nEl editor no puede ser responsabilizado por ninguna lesión o daño — físico o psicológico — derivado del uso, o mal uso, de la app. Si tienes cualquier duda sobre tu salud, consulta a un profesional.';

  @override
  String get sessionCameraInactiveWarning =>
      'Verificación de cámara inactiva — recalibrar';

  @override
  String get sessionCameraInactiveAction => 'Calibrar';

  @override
  String get modeSelectionCustomTitle => 'CUSTOM';

  @override
  String get modeSelectionCustomSubtitle =>
      'Sesiones a medida: duración, mezcla de modos, dificultad, non-stop.';

  @override
  String get customAppBarTitle => 'Sesiones a medida';

  @override
  String get customListEmptyTitle => 'Aún sin configuración guardada';

  @override
  String get customListEmptyBody =>
      'Crea tu primera configuración para generar sesiones a medida.';

  @override
  String get customNewConfig => 'Nueva configuración';

  @override
  String get customLaunchLastTitle => 'Relanzar la última configuración';

  @override
  String get customUnnamed => 'Sin título';

  @override
  String get customNonStopBadge => 'Non-stop';

  @override
  String get customDeleteConfirmTitle => '¿Eliminar esta configuración?';

  @override
  String customDeleteConfirmBody(String name) {
    return '«$name» será eliminada definitivamente.';
  }

  @override
  String get customDuplicateSuffix => ' (copia)';

  @override
  String get customActionEdit => 'Editar';

  @override
  String get customActionDuplicate => 'Duplicar';

  @override
  String get customActionDelete => 'Eliminar';

  @override
  String get customActionLaunch => 'Lanzar';

  @override
  String get customConfigSavedSnack => 'Configuración guardada.';

  @override
  String customSessionName(String name) {
    return 'Custom — $name';
  }

  @override
  String get customEditorTitleNew => 'Nueva configuración custom';

  @override
  String get customEditorTitleEdit => 'Editar configuración';

  @override
  String get customFieldNameLabel => 'Nombre de la configuración';

  @override
  String get customFieldNameHint => 'ej. Maratón profundo';

  @override
  String get customSectionCoach => 'Coach';

  @override
  String get customCoachDefaultVoice => 'Voz por defecto (sin coach)';

  @override
  String get customCoachPickerTitle => 'Elige un coach';

  @override
  String get customCoachPickerDefaultSubtitle =>
      'Banco de frases genérico, voz TTS del sistema';

  @override
  String get customSectionDuration => 'Duración';

  @override
  String get customNonStopToggle => 'Modo non-stop';

  @override
  String get customNonStopDescription =>
      'Encadena ciclos completos (boosts + final) sin parar. El botón «Termíname» dispara un boost final y termina de verdad.';

  @override
  String get customCycleDurationLabel => 'Duración del ciclo';

  @override
  String get customProgressiveDifficultyToggle => 'Dificultad progresiva';

  @override
  String get customProgressiveDifficultyDescription =>
      'Cada ciclo es un poco más duro y más largo que el anterior.';

  @override
  String customDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get customSectionDifficulty => 'Dificultad global';

  @override
  String get customSectionDoses => 'Mezcla de modos';

  @override
  String get customDosesHint =>
      '«Ninguno» excluye el modo. «Frecuente» lo favorece.';

  @override
  String get customDangerNoMouthMode =>
      'Mantén al menos un modo de boca activo (ritmo, lengua o hold).';

  @override
  String get customSectionAxes => 'Ejes de enfoque';

  @override
  String get customAxesHint =>
      'Asigna puntos para sesgar el generador. No afecta a tu especialización de carrera.';

  @override
  String customAxesSpent(int spent) {
    return '$spent pts asignados';
  }

  @override
  String get customSectionAdvanced => 'Avanzado';

  @override
  String get customIncludeHandToggle => 'Incluir estimulación con la mano';

  @override
  String get customIncludeHandDescription =>
      'Activa los modos mano y vergazo en la generación.';

  @override
  String get customMaxDepthLabel => 'Profundidad máxima';

  @override
  String get customBpmRangeLabel => 'Rango de BPM';

  @override
  String customBpmRangeValue(int min, int max) {
    return '$min–$max BPM';
  }

  @override
  String get customBpmRangeHint =>
      'Aplica a los modos rítmicos (ritmo, lengua, vergazo, mano).';

  @override
  String get customHoldDurationRangeLabel => 'Duración del hold';

  @override
  String customHoldDurationRangeValue(int min, int max) {
    return '$min–$max s';
  }

  @override
  String get customHoldDurationRangeHint =>
      'Acota la duración de holds y súplicas mantenidas.';

  @override
  String get customSaveAndLaunch => 'Guardar y lanzar';

  @override
  String get customSaveOnly => 'Guardar';

  @override
  String customHostLoadError(String error) {
    return 'No se pudo cargar la sesión custom: $error';
  }

  @override
  String customSaveError(String error) {
    return 'No se pudo guardar la configuración: $error';
  }

  @override
  String customLaunchError(String error) {
    return 'No se pudo lanzar la sesión: $error';
  }

  @override
  String get customFinishNowButton => 'Termíname';

  @override
  String get customFinishNowSubtitle => 'boost final y luego terminar';

  @override
  String get customDifficultyFacile => 'Fácil';

  @override
  String get customDifficultyNormal => 'Normal';

  @override
  String get customDifficultyDifficile => 'Difícil';

  @override
  String get customDifficultyExtreme => 'Extremo';

  @override
  String get customDoseNone => 'Ninguno';

  @override
  String get customDoseRare => 'Raro';

  @override
  String get customDoseNormal => 'Normal';

  @override
  String get customDoseFrequent => 'Frecuente';

  @override
  String get profileSessionDisplaySection => 'Visualización de sesión';

  @override
  String get profileShowRemainingTime => 'Mostrar tiempo restante';

  @override
  String get profileShowRemainingTimeSubtitle =>
      'Reloj mm:ss pequeño en la parte alta de la pantalla durante la sesión.';

  @override
  String sessionRemainingTimeLabel(String time) {
    return 'Quedan: $time';
  }
}
