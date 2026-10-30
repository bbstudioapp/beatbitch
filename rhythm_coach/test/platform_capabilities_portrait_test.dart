import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/services/platform_capabilities.dart';

void main() {
  bool locks(TargetPlatform platform, double shortestSide,
          {bool isWeb = false}) =>
      PlatformCapabilities.locksPortrait(
          isWeb: isWeb, platform: platform, shortestSide: shortestSide);

  test('un téléphone Android ou iOS est bloqué en portrait', () {
    expect(locks(TargetPlatform.android, 384), isTrue);
    expect(locks(TargetPlatform.iOS, 390), isTrue);
  });

  test('une tablette garde la rotation libre', () {
    expect(locks(TargetPlatform.android, 800), isFalse);
    expect(locks(TargetPlatform.iOS, 600), isFalse);
  });

  test('desktop et web ne sont jamais bloqués', () {
    expect(locks(TargetPlatform.windows, 384), isFalse);
    expect(locks(TargetPlatform.linux, 384), isFalse);
    expect(locks(TargetPlatform.android, 384, isWeb: true), isFalse);
  });
}
