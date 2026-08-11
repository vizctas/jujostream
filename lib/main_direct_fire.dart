import 'main.dart' as app;
import 'services/update/direct_fire_update_provider.dart';
import 'services/update/update_models.dart';
import 'utils/app_version.dart';

Future<void> main() => app.runJujostream(
  updateProvider: DirectFireUpdateProvider(
    currentVersion: ClientVersion.parse(kAppVersion),
  ),
);
