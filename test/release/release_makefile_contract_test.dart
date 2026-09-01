import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release pipeline builds explicit distribution flavors', () {
    final makefile = File('Makefile').readAsStringSync();

    expect(
      makefile,
      contains(
        'flutter build apk --release --flavor directFire '
        '-t lib/main_direct_fire.dart',
      ),
    );
    expect(
      makefile,
      contains(
        'flutter build appbundle --release --flavor play '
        '-t lib/main_play.dart',
      ),
    );
    expect(
      makefile,
      contains(
        'APK_SRC        = '
        'build/app/outputs/flutter-apk/app-directfire-release.apk',
      ),
    );
    expect(
      makefile,
      contains(
        'AAB_SRC        = '
        'build/app/outputs/bundle/playRelease/app-play-release.aab',
      ),
    );
  });
}
