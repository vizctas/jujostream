import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/preferences/hidden_apps_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stores hidden apps per device and host', () async {
    SharedPreferences.setMockInitialValues({});
    const store = HiddenAppsStore();

    await store.save('living-room', {8, 3});
    await store.save('bedroom', {21});

    expect(await store.load('living-room'), {3, 8});
    expect(await store.load('bedroom'), {21});
  });

  test('ignores malformed persisted app ids', () async {
    SharedPreferences.setMockInitialValues({
      'hidden_apps_v1_host': ['4', 'bad-id'],
    });

    expect(await const HiddenAppsStore().load('host'), {4});
  });
}
