# BeatBitch

![version](https://img.shields.io/badge/version-0.5.1-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Web-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)
![no tracking](https://img.shields.io/badge/no-tracking-success)
![license](https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-lightgrey)

> **Coach vocal rítmico inmersivo para Android, Windows, Linux, iOS (PWA) y web.** Apoya el móvil de lado, lanza la sesión, cierra los ojos. Una voz te guía, los bips marcan el ritmo — no hace falta mirar la pantalla.

**Idiomas**: [English](README.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · Español

---

## En 30 segundos

- Un **coach con voz** que habla tu idioma, en local — sin síntesis por red.
- **Bips de guía** sincronizados a un BPM para marcar cada movimiento.
- 8 modos de juego, un modo Carrera que se desbloquea con la práctica, coaches con personalidades distintas.
- **100 % offline** en Android: el permiso `INTERNET` no está declarado, nada sale de tu móvil.
- **Sin Play Store, sin anuncios, sin compras integradas.** Distribución directa: APK firmado (Android), zip portable (escritorio), aplicación web instalable (iOS / navegador).

## 📥 Descargar

➡ **[Página de Releases](../../releases)** — APK firmado + su SHA256.

> ⚠ Android 9 mínimo. Probado en Android 13/14.

## 📲 Instalar en Android (side-load, paso a paso)

**Side-load** significa simplemente «instalar una aplicación fuera de la Play Store». Android lo permite de forma nativa — solo tienes que autorizar a tu navegador o gestor de archivos a hacerlo.

1. **En tu móvil**, abre la [página de Releases](../../releases) y descarga el último `BeatBitch-X.Y.Z.apk`.
2. (*Opcional pero recomendado*) Verifica que el hash SHA256 del archivo descargado coincida con el publicado junto al APK. Una app como **Hash Droid** en F-Droid lo hace en dos toques.
3. Abre el APK desde tus descargas.
4. Android te pedirá **autorizar esta fuente**: pulsa «Ajustes», activa el permiso para tu navegador (o gestor de archivos), vuelve y confirma.
5. La instalación corre. Cuando termine, abre BeatBitch.
6. **Primer arranque**: confirmación 18+ (no se puede saltar), luego 3 pantallas de onboarding (colocación del móvil, volumen, prueba de voz).

> 💡 Puedes volver a desactivar «orígenes desconocidos» después de instalar — Android no lo reabre salvo que actualices la app.

## 🍎 Instalar en iPhone / iPad (PWA)

BeatBitch **no** está disponible en la App Store (Apple no permite contenido para adultos). En iOS entregamos una **versión web instalable** (PWA). Una vez añadida a la pantalla de inicio, se comporta como una app real: icono propio, pantalla completa, sin la barra de Safari, funciona offline tras la primera carga.

1. En tu iPhone / iPad (iOS 16.4+), abre **Safari** (no Chrome / Firefox — Apple bloquea la instalación PWA desde ellos).
2. Ve a **[beatbitch.pages.dev](https://beatbitch.pages.dev)** y espera a que la página cargue por completo (toda la app se descarga la primera vez).
3. Pulsa el botón **Compartir** → **Añadir a la pantalla de inicio** → **Añadir**.
4. Lanza BeatBitch desde tu pantalla de inicio. Primer arranque: adult gate 18+, luego onboarding de 3 pasos.

> Guía detallada: **[docs/INSTALL-iOS.en.md](docs/INSTALL-iOS.en.md)**.
>
> ⚠ La versión web/iOS usa la **síntesis vocal nativa de iOS** (sin voces Android). La verificación de cámara en holds y las notificaciones sorpresa no están disponibles. La primera carga necesita conexión a Internet; todo lo demás corre offline desde el icono de inicio.

## 🌐 Usar en un navegador de escritorio

Misma URL que en iOS — **[beatbitch.pages.dev](https://beatbitch.pages.dev)** funciona en cualquier navegador moderno (Chrome, Edge, Firefox, Safari). Práctico para probar la app antes de instalar el APK o el build de escritorio. La calidad de voz depende del motor TTS de tu sistema.

## 🖥 Instalar en Windows escritorio

Disponible desde **v0.1.3**. Zip portable — sin instalador, sin escrituras en registro / carpetas del sistema.

1. Desde la [página de Releases](../../releases), descarga `BeatBitch-X.Y.Z-windows-x64.zip` (y su `.sha256` si quieres verificar la integridad).
2. Descomprime donde quieras: `C:\Users\tú\Documents\BeatBitch\`, una memoria USB, etc.
3. Lanza `rhythm_coach.exe`. Windows SmartScreen puede avisar (binario no firmado por un editor reconocido) → pulsa *Más información* → *Ejecutar de todas formas*.
4. Primer arranque: adult gate 18+, luego onboarding de 3 pasos (idéntico a Android).

> ⚠ **Desactivado en Windows**: la verificación de cámara en holds y las notificaciones sorpresa no están portadas (los plugins nativos no tienen implementación Windows). La voz del coach usa **Microsoft Julie** (SAPI) en lugar de las voces Android. Sesiones, modo Carrera, coaches, insignias, idiomas: todo funciona idéntico a Android.

## 🐧 Instalar en Linux escritorio

Disponible desde **v0.3.0**. `tar.gz` portable — sin paquete `.deb`/`.rpm`, la app se queda en su carpeta y nada se instala a nivel sistema.

1. Desde la [página de Releases](../../releases), descarga `BeatBitch-X.Y.Z-linux-x64.tar.gz` (y su `.sha256` si quieres verificar la integridad).
2. Verifica el hash: `sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256`.
3. Descomprime donde quieras: `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Lanza el binario: `./BeatBitch-X.Y.Z-linux-x64/beat_bitch` (clic derecho → *Permitir la ejecución* en tu gestor de archivos si hace falta).
5. Primer arranque: adult gate 18+, luego onboarding de 3 pasos (idéntico a Android).

> ⚠ **Desactivado en Linux**: la verificación de cámara en holds y las notificaciones sorpresa no están portadas. La voz del coach usa la voz por defecto del **Speech Dispatcher** (típicamente `espeak-ng` en Ubuntu/Debian — instala una voz en español a través de tu gestor de paquetes si la voz por defecto no suena bien). Sesiones, modo Carrera, coaches, insignias, idiomas: todo funciona idéntico a Android.

## 🔄 Actualizaciones automáticas (Obtainium)

La app Android se mantiene **estrictamente offline** — no contacta con nada para actualizarse por sí sola. Para enterarte cuando salga una nueva versión e instalarla en dos toques, usa **[Obtainium](https://github.com/ImranR98/Obtainium)**, una tienda Android open-source que vigila las páginas de GitHub Releases.

1. Instala Obtainium (disponible en [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/) o como APK directo desde su repo).
2. En Obtainium: *Add App* → pega la URL `https://github.com/bbstudioapp/beatbitch`.
3. En cada nuevo release, Obtainium detecta el `BeatBitch-X.Y.Z.apk` y te propone la actualización.

> Ningún tráfico de red sale de BeatBitch — Obtainium consulta GitHub por el lado del usuario, independientemente de la app. La promesa 100 % offline se mantiene intacta.

## 🔒 ¿Es seguro?

- **APK firmado** con la misma clave en cada release — Android rechaza instalar un APK manipulado (la firma no coincide).
- **Código fuente público** — puedes leer lo que se ejecuta (o que te lo lean).
- **Sin permiso de red** (Android) — ni `INTERNET` ni `ACCESS_NETWORK_STATE`. La app Android *literalmente no puede* contactar con un servidor.
- **`allowBackup="false"`** — sin subida a Google Backup.
- **La cámara es opt-in** — la verificación de cámara en holds está apagada por defecto y el procesamiento corre 100 % en el dispositivo (Google ML Kit local). Ninguna imagen sale del móvil.

Detalles en **[PRIVACY.md](docs/PRIVACY.md)** ([versión publicada](https://bbstudioapp.github.io/beatbitch/PRIVACY)).

## 🎮 Cómo jugar

1. Apoya el móvil de lado — no hace falta tenerlo a la vista.
2. Elige una sesión preconfigurada o deja que el modo Carrera te genere una.
3. Sigue la voz. Los bips marcan el tempo (un grave + un agudo alternados, o solo uno si tienes que mantener una posición).
4. El botón **«No puedo»** siempre está disponible si te quedas sin fuerzas. El coach toma el relevo con un castigo corto, luego la sesión retoma donde tenga sentido.
5. Al final, la pantalla te dice qué has desbloqueado (insignias, niveles de carrera, hitos).

## 🐛 ¿Has encontrado un bug, una idea, quieres contribuir?

Plantillas de issues disponibles:
- 🐛 [Bug](.github/ISSUE_TEMPLATE/bug_report.md) · 💡 [Idea / feature](.github/ISSUE_TEMPLATE/feature_request.md) · ✍ [Frases del coach / escenarios / traducción](.github/ISSUE_TEMPLATE/content_contribution.md)

Todo está explicado en **[CONTRIBUTING.md](CONTRIBUTING.md)** ([versión española](CONTRIBUTING.es.md)).

> Las contribuciones **editoriales** (frases del coach, escenarios, apodos, nuevos idiomas) son las más valiosas y **no requieren conocimientos técnicos**. La plantilla de contenido te guía hasta el formato correcto.
>
> Los contribuidores con IA (ChatGPT, Claude, etc.) pueden referirse a **[docs/CONTENT_GUIDE.md](docs/CONTENT_GUIDE.md)** — guía estructurada de los formatos JSON que consume el generador.

## 🛠 ¿Curiosidad por el código?

El proyecto Flutter completo vive en **[`rhythm_coach/`](rhythm_coach/)**:
- **[Configuración para desarrolladores](docs/DEVELOPMENT.md)** — instalar Flutter, lanzar por plataforma (Android, Windows, web Chrome), personalizar assets sin programar
- **[README de desarrollo completo](rhythm_coach/README.md)** — funciones detalladas, build local, tests
- **[Arquitectura](rhythm_coach/CLAUDE.md)** — flujo de sesión, motor de excitación, modo Carrera, i18n
- **[CI/CD setup](.github/RELEASE_SETUP.md)** — workflow de auto-release

## 📝 Licencia

Código y contenido editorial bajo **[PolyForm Noncommercial 1.0.0](LICENSE)**.

- ✅ Uso personal, estudio, modificación, fork, redistribución no comercial.
- ❌ Venta, monetización, fork «Premium» en Telegram / Gumroad / tiendas alternativas.

Los assets binarios fuera del repo (gifs de fondo y mp3s de ambiente) siguen sujetos a los derechos de sus fuentes originales.
