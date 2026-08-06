import 'package:logger/logger.dart';

/// Logger for the networking and pairing layers, which stays on in release.
///
/// A bare `Logger()` uses `DevelopmentFilter`, which emits only when
/// `kDebugMode` is true. Every line from NvHttpClient, PairingService,
/// CloudSyncService and DiscoveryService was therefore dropped from the shipped
/// app — so a field failure produced a user-visible error and nothing at all to
/// diagnose it with. These are the four call sites that matter when a client
/// cannot reach its server, which is exactly when logs are needed.
///
/// Output goes through `print`, so it reaches logcat on Android and is picked
/// up by BetaTelemetryService's debugPrint capture on every platform.
Logger diagnosticsLogger(String name) => Logger(
  filter: ProductionFilter(),
  printer: PrefixedPrinter(name),
  level: Level.debug,
);

/// One line per event: a timestamp, the subsystem, and the message.
///
/// PrettyPrinter's boxes and stack traces are unreadable in logcat and bloat
/// the telemetry file; the point here is greppability.
class PrefixedPrinter extends LogPrinter {
  PrefixedPrinter(this.name);

  final String name;

  @override
  List<String> log(LogEvent event) {
    final level = event.level.name.toUpperCase().padRight(5);
    final time = DateTime.now().toIso8601String().substring(11, 23);
    final lines = <String>['$time $level [$name] ${event.message}'];
    if (event.error != null) lines.add('$time $level [$name]   ${event.error}');
    return lines;
  }
}
