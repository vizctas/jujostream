import 'dart:async';

import 'guest_link.dart';

/// While streaming a server I manage: polls the guests waiting for approval
/// on that server and keeps them as a FIFO queue. A request disappears when
/// it expires or somebody else answers it.
class GuestRequestPoller {
  GuestRequestPoller({
    required this.serverUrl,
    required this.fetch,
    required this.respond,
    required this.onChanged,
    this.isActive = _always,
    this.interval = const Duration(seconds: 3),
  });

  static bool _always() => true;

  final String serverUrl;
  final Future<List<GuestRequest>> Function() fetch;
  final Future<bool> Function(String inviteId, bool approve) respond;
  final void Function() onChanged;

  /// Polling is skipped while this returns false (not streaming / backgrounded).
  final bool Function() isActive;
  final Duration interval;

  List<GuestRequest> queue = const [];
  Timer? _timer;
  bool _busy = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static String _key(String url) =>
      url.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

  Future<void> poll() async {
    if (_busy || !isActive()) return;
    _busy = true;
    try {
      final next = [
        for (final r in await fetch())
          if (_key(r.serverUrl) == _key(serverUrl) && !r.isExpired) r,
      ];
      if (_timer == null) return;
      if (!_sameIds(next, queue)) {
        queue = next;
        onChanged();
      }
    } catch (_) {
      // Next tick retries; never disturb the stream.
    } finally {
      _busy = false;
    }
  }

  /// Approves or declines [request]; drops it from the queue on success.
  Future<bool> answer(GuestRequest request, {required bool approve}) async {
    final ok = await respond(request.id, approve);
    if (ok) {
      queue = [
        for (final r in queue)
          if (r.id != request.id) r,
      ];
      onChanged();
    }
    return ok;
  }

  static bool _sameIds(List<GuestRequest> a, List<GuestRequest> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i].id == b[i].id].every((e) => e);
}
