//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audioplayers_darwin
import flutter_local_notifications
import flutter_tts
import package_info_plus
import shared_preferences_foundation
import wakelock_plus

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioplayersDarwinPlugin.register(with: registry.registrar(forPlugin: "AudioplayersDarwinPlugin"))
  FlutterLocalNotificationsPlugin.register(with: registry.registrar(forPlugin: "FlutterLocalNotificationsPlugin"))
  FlutterTtsPlugin.register(with: registry.registrar(forPlugin: "FlutterTtsPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  WakelockPlusMacosPlugin.register(with: registry.registrar(forPlugin: "WakelockPlusMacosPlugin"))
}
