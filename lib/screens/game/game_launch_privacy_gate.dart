/// Fail-closed state machine that decides whether decoded game video may be
/// presented. Transport connectivity alone is intentionally insufficient.
class GameLaunchPrivacyGate {
  GameLaunchPrivacyGate({required this.required})
    : hostGameReady = !required,
      postReadyFrameRendered = !required;

  final bool required;

  bool transportConnected = false;
  bool hostGameReady;
  bool postReadyFrameRendered;
  bool revealCompleted = false;
  int readyGeneration = 0;
  int? postReadyFrameBaseline;

  bool get revealEligible =>
      transportConnected && hostGameReady && postReadyFrameRendered;

  bool get videoVisible => revealCompleted && revealEligible;

  void resetTransport() {
    transportConnected = false;
    hostGameReady = !required;
    postReadyFrameRendered = !required;
    revealCompleted = false;
    readyGeneration = 0;
    postReadyFrameBaseline = null;
  }

  void markTransportConnected() {
    transportConnected = true;
  }

  void hideForRetry() {
    hostGameReady = !required;
    postReadyFrameRendered = !required;
    revealCompleted = false;
    postReadyFrameBaseline = null;
  }

  /// Returns true only for a new readiness generation that needs a fresh IDR.
  bool markHostReady({required int generation, required int framesRendered}) {
    if (!required || generation <= 0 || generation == readyGeneration) {
      return false;
    }
    readyGeneration = generation;
    hostGameReady = true;
    postReadyFrameRendered = false;
    revealCompleted = false;
    postReadyFrameBaseline = framesRendered;
    return true;
  }

  /// Returns true when the first frame proven newer than host readiness lands.
  bool observeFramesRendered(int framesRendered) {
    final baseline = postReadyFrameBaseline;
    if (!required ||
        !hostGameReady ||
        postReadyFrameRendered ||
        baseline == null) {
      return false;
    }
    if (framesRendered <= baseline) return false;
    postReadyFrameRendered = true;
    return true;
  }

  bool completeReveal() {
    if (!revealEligible) return false;
    revealCompleted = true;
    return true;
  }
}
