import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/utils/app_version.dart';
import 'package:jujostream/utils/changelog.dart';

void main() {
  test('every release bump ships its changelog in both languages', () {
    final entry = kChangelog[kAppVersion];
    expect(entry, isNotNull, reason: 'add kChangelog[$kAppVersion]');
    expect(entry!.es, isNotEmpty);
    expect(entry.en.length, entry.es.length);
  });
}
