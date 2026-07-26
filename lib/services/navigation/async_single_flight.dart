/// Prevents duplicate asynchronous navigation or connection attempts.
class AsyncSingleFlight {
  bool _active = false;

  bool get isActive => _active;

  Future<bool> run(Future<void> Function() action) async {
    if (_active) return false;
    _active = true;
    try {
      await action();
      return true;
    } finally {
      _active = false;
    }
  }
}
