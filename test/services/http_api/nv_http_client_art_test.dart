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

  test('app list parser reads host metadata and decodes XML entities', () {
    const xml = '''
      <root>
        <App>
          <ID>7</ID>
          <AppTitle>End of Abyss</AppTitle>
          <UUID>abyss</UUID>
          <Description>Cel &amp; the &quot;derelict&quot; areas</Description>
          <Developer>Section 9 Interactive</Developer>
          <Publisher>Epic Games Publishing</Publisher>
          <ReleaseDate>2026-10-01</ReleaseDate>
          <Genres>Adventure|Shooter</Genres>
        </App>
        <App>
          <ID>8</ID>
          <AppTitle>Bare</AppTitle>
        </App>
      </root>
    ''';

    final apps = NvHttpClient().parseAppList(xml, '192.168.1.10', 47984);
    final abyss = apps.firstWhere((a) => a.appId == 7);
    final bare = apps.firstWhere((a) => a.appId == 8);

    expect(abyss.description, 'Cel & the "derelict" areas');
    expect(abyss.developer, 'Section 9 Interactive');
    expect(abyss.publisher, 'Epic Games Publishing');
    expect(abyss.releaseDate, '2026-10-01');
    expect(abyss.metadataGenres, ['Adventure', 'Shooter']);
    expect(bare.description, isNull);
    expect(bare.metadataGenres, isEmpty);
  });
}
