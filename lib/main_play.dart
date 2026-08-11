import 'main.dart' as app;
import 'services/update/play_store_update_provider.dart';

Future<void> main() =>
    app.runJujostream(updateProvider: PlayStoreUpdateProvider());
