# BeatBitch — règles ProGuard/R8 pour le buildType release.
#
# `proguard-android-optimize.txt` (chargé en amont) couvre déjà les bases
# Flutter, AndroidX et le bytecode général. Ce fichier ajoute uniquement
# les `-keep` indispensables aux plugins qui font de la réflexion ou
# instancient des classes par nom.
#
# Si un plugin casse en release après une montée de version, vérifier
# d'abord les CHANGELOG / README du plugin — beaucoup distribuent
# leurs propres règles via `consumer-rules.pro` qui s'appliquent
# automatiquement, et la liste ci-dessous peut devenir partiellement
# redondante. On garde quand même par sécurité : R8 dédoublonne.

# ---------------------------------------------------------------------
# ML Kit — google_mlkit_face_detection
# ---------------------------------------------------------------------
# Les classes Vision sont chargées dynamiquement via les options de
# détecteur ; sans -keep, R8 strippe les implémentations et la création
# du `FaceDetector` lance un `ClassNotFoundException` au runtime.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.vision.**

# ---------------------------------------------------------------------
# flutter_local_notifications
# ---------------------------------------------------------------------
# Les `BroadcastReceiver` (boot, reschedule, action) sont déclarés dans
# le manifest et instanciés par le système — R8 les voit comme orphelins
# côté code Kotlin. Le plugin utilise aussi GSON pour sérialiser les
# notifs persistées.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
# TypeToken<...> de GSON repose sur la signature générique préservée.
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.TypeAdapter

# ---------------------------------------------------------------------
# Divers — silencer les warnings sur les transitive deps connues
# ---------------------------------------------------------------------
# audioplayers / camera / permission_handler / sensors_plus / wakelock_plus
# ne nécessitent pas de -keep custom (réflexion mineure, géré par leurs
# propres consumer-rules). On note ici uniquement les `dontwarn`
# courants si R8 grogne sur des classes d'androidx introspectées.
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
