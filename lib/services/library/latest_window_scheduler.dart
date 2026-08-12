import 'dart:async';

/// Runs only the newest requested work window under a fixed concurrency budget.
///
/// Active tasks finish normally; queued tasks from an obsolete focus position
/// are replaced when [schedule] receives a newer window.
class LatestWindowScheduler<T> {
  final int maxConcurrent;
  final String Function(T item) keyOf;
  final Future<void> Function(T item) load;

  LatestWindowScheduler({
    required this.keyOf,
    required this.load,
    this.maxConcurrent = 2,
  }) : assert(maxConcurrent > 0);

  final Set<String> _inFlight = <String>{};
  List<T> _pending = const [];
  bool _disposed = false;

  int get activeCount => _inFlight.length;
  int get pendingCount => _pending.length;

  void schedule(Iterable<T> items) {
    if (_disposed) return;
    final newest = <String, T>{};
    for (final item in items) {
      final key = keyOf(item);
      if (!_inFlight.contains(key)) newest[key] = item;
    }
    _pending = newest.values.toList(growable: true);
    _pump();
  }

  void _pump() {
    while (!_disposed &&
        _inFlight.length < maxConcurrent &&
        _pending.isNotEmpty) {
      final item = _pending.removeAt(0);
      final key = keyOf(item);
      if (!_inFlight.add(key)) continue;
      unawaited(
        Future<void>.sync(
          () => load(item),
        ).catchError((Object _) {}).whenComplete(() {
          _inFlight.remove(key);
          _pump();
        }),
      );
    }
  }

  void dispose() {
    _disposed = true;
    _pending = const [];
  }
}
