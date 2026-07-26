import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/update/client_update_service.dart';

void main() {
  group('ClientVersion', () {
    test('orders semantic versions numerically', () {
      expect(
        ClientVersion.parse('client-1.10.0')
            .compareTo(ClientVersion.parse('1.9.9')),
        greaterThan(0),
      );
    });
  });

  group('ClientUpdateService.selectLatestRelease', () {
    Map<String, Object> release(
      String tag, {
      bool draft = false,
      bool prerelease = false,
      String asset = 'JujoStream-client-1.2.0-android.apk',
    }) {
      return {
        'tag_name': tag,
        'draft': draft,
        'prerelease': prerelease,
        'html_url': 'https://github.com/releases/$tag',
        'assets': [
          {
            'name': asset,
            'browser_download_url': 'https://github.com/download/$asset',
            'size': 123,
            'digest':
                'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          },
        ],
      };
    }

    test('selects newest stable production Android release', () {
      final result = ClientUpdateService.selectLatestRelease(
        [
          release('client-1.2.0'),
          release('client-2.0.0', prerelease: true),
          release('admin-9.0.0'),
          release('client-1.10.0'),
        ],
        ClientVersion.parse('1.1.18'),
      );

      expect(result?.version.toString(), '1.10.0');
      expect(result?.apk.sha256, 'a' * 64);
    });

    test('ignores debug APKs and releases that are not newer', () {
      final result = ClientUpdateService.selectLatestRelease(
        [
          release(
            'client-2.0.0',
            asset: 'JujoStream-client-2.0.0-android-debug.apk',
          ),
          release('client-1.1.18'),
        ],
        ClientVersion.parse('1.1.18'),
      );

      expect(result, isNull);
    });
  });
}
