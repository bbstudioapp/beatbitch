# BeatBitch

![version](https://img.shields.io/badge/version-0.5.1-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)

> Coach vocal rítmico inmersivo. El móvil se apoya de lado, no hace falta mirar la pantalla: todo pasa por la voz y los bips de guía.

**Idiomas** : [English](README.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · Español

---

## Capturas de pantalla

> _Próximamente — la app está en alfa privada._

<p>
  <em>placeholder</em> · inicio · sesión · sonidos · perfil · insignias
</p>

## Funcionalidades

- **Coach con voz TTS femenina**, tono firme, voz local únicamente (sin síntesis por red).
- **8 modos de juego**: rhythm, lick, biffle, hold, breath, beg, freestyle, hand.
- **Modo Carrera**: 20+ niveles, 6 ramas de especialización, hitos de aprendizaje, encore encadenado, sesiones rapidito, insignias de progresión.
- **Escenarios libres**: sesiones JSON editables, castigos y comentarios aleatorios extensibles sin tocar el código.
- **Verificación de cámara en holds** (experimental, opt-in): detección on-device vía Google ML Kit — ninguna imagen sale del dispositivo.
- **Multi-idioma**: francés, inglés, alemán y español entregados; otros idiomas = simple drop-in de assets.
- **Adult gate 18+** no salteable al primer arranque, onboarding de 3 pantallas.

## 100 % offline · sin telemetría

Ningún dato sale de tu móvil. Permiso `INTERNET` no declarado. ML Kit corre en local. Consulta [PRIVACY.md](PRIVACY.md).

## Instalación (side-load Android)

La app **no se distribuye en la Play Store** — solo instalación manual.

1. Descarga el APK desde la página Releases del repo.
2. Verifica el SHA256 publicado junto al APK:
   ```bash
   sha256sum BeatBitch-X.Y.Z.apk
   ```
3. En el móvil: permite la instalación desde orígenes desconocidos para tu gestor de archivos / navegador.
4. Abre el APK y confirma la instalación.
5. Primer arranque: adult gate 18+, luego onboarding de 3 pasos.

> ⚠ Se requiere Android 9+. Probado en Android 13/14.

## Instalación (Windows escritorio)

Disponible desde v0.1.3 — zip portable, sin instalador.

1. Descarga `BeatBitch-X.Y.Z-windows-x64.zip` desde la página Releases.
2. Verifica el SHA256:
   ```powershell
   Get-FileHash BeatBitch-X.Y.Z-windows-x64.zip -Algorithm SHA256
   ```
3. Descomprime donde quieras (`Documents\BeatBitch\`, memoria USB, …).
4. Lanza `rhythm_coach.exe`. Windows SmartScreen puede avisar (binario sin firmar) →
   pulsa *Más información* → *Ejecutar de todas formas*.
5. Primer arranque: adult gate 18+, luego onboarding de 3 pasos.

> ⚠ Desactivado en Windows: verificación de cámara en holds, notificaciones sorpresa.
> La voz del coach usa Microsoft Julie (SAPI). Todo lo demás — sesiones, modo
> Carrera, coaches, insignias, i18n — funciona idéntico a Android.

## Instalación (Linux escritorio)

Disponible desde v0.3.0 — `tar.gz` portable, sin paquete `.deb`/`.rpm`.

1. Descarga `BeatBitch-X.Y.Z-linux-x64.tar.gz` desde la página Releases.
2. Verifica el SHA256:
   ```bash
   sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256
   ```
3. Descomprime donde quieras: `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Lanza el binario: `./BeatBitch-X.Y.Z-linux-x64/beat_bitch`.
5. Primer arranque: adult gate 18+, luego onboarding de 3 pasos.

> ⚠ Desactivado en Linux: verificación de cámara en holds, notificaciones sorpresa.
> La voz del coach usa la voz por defecto del Speech Dispatcher (típicamente
> `espeak-ng`). Todo lo demás — sesiones, modo Carrera, coaches, insignias,
> i18n — funciona idéntico a Android.

## Actualizaciones automáticas (Obtainium)

La app se mantiene **estrictamente offline** — no contacta con nada para actualizarse por sí sola. Para enterarte cuando salga una nueva versión, usa **[Obtainium](https://github.com/ImranR98/Obtainium)**, una tienda Android open-source que vigila las páginas de GitHub Releases. *Add App* → pega `https://github.com/bbstudioapp/beatbitch`. Ningún tráfico de red sale de BeatBitch — Obtainium consulta GitHub por el lado del usuario, independientemente de la app.

## Build local (desarrolladores)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # debe devolver "No issues found!"
flutter test
flutter run           # dispositivo Android conectado / `-d windows` / `-d chrome`
flutter build apk --release
flutter build windows --release
```

El contenido editorial vive en `assets/` (sesiones JSON, castigos, comentarios aleatorios, packs de ambiente, banco de frases de carrera). Setup completo por plataforma + rutas de personalización: **[`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md)**.

> ⚠ **Assets binarios externalizados**: las carpetas `assets/backgrounds/` (GIFs/imágenes de fondo) y `assets/audio/ambience/` (MP3s de ambiente) están **gitignoradas** — sus archivos no están versionados en el repo y deben rapatriarse desde un canal externo (TBD) antes de `flutter build`. El código degrada gracefully cuando estas carpetas están vacías: el fondo cae sobre un degradado animado, el ambiente sobre silencio.

## Privacidad

Consulta [PRIVACY.md](PRIVACY.md) — versión corta: nada se recopila, todo es local, `allowBackup="false"`.

## Licencia

Código y contenido editorial (sesiones JSON, frases del coach, comentarios aleatorios, apodos, hitos, etc.) bajo **[PolyForm Noncommercial License 1.0.0](../LICENSE)**.

- ✅ **Estudio, fork, modificación, redistribución** para uso no comercial.
- ✅ **Contribuciones bienvenidas** — nuevas frases del coach, sesiones, traducciones, fixes de código, ideas de especialización, etc. Abre un issue o un PR.
- ❌ **Sin uso comercial, venta ni redistribución de pago** — ningún fork «BeatBitch Premium» en Telegram, Gumroad o tienda alternativa.

Los assets binarios fuera del repo (`assets/backgrounds/*.gif`, `assets/audio/ambience/*.mp3`) siguen sujetos a los derechos de sus fuentes originales y no están cubiertos por esta licencia.

## Reporte de bugs

Abre un issue en el repo. Por favor incluye modelo del dispositivo, versión de Android y pasos para reproducir.
