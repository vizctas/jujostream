import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

void main() {
  test('app list parser keeps poster hero and complete gallery separate', () {
    const xml = '''
      <root>
        <App>
          <ID>42</ID>
          <AppTitle>Hades</AppTitle>
          <IsRunning>0</IsRunning>
          <IsHdrSupported>1</IsHdrSupported>
          <UUID>game-uuid</UUID>
          <HasHeroImage>1</HasHeroImage>
          <ExtraImageCount>3</ExtraImageCount>
        </App>
      </root>
    ''';

    final app = NvHttpClient().parseAppList(xml, '192.168.1.10', 47984).single;

    expect(app.posterUrl, contains('AssetType=2'));
    expect(app.heroImageUrl, contains('AssetType=3'));
    expect(app.screenshotUrls, hasLength(3));
    expect(
      app.screenshotUrls.every((url) => url.contains('AssetType=4')),
      isTrue,
    );
  });
}
