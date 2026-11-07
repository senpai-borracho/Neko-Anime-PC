/// Application-side interpretation of native playback signals.
/// Decoder/network diagnostics alone never mean that playback has failed.
class PlaybackHealth {
  DateTime? openedAt, lastProgressAt;
  Duration position = Duration.zero, duration = Duration.zero;
  String? diagnostic;
  bool hasProgress = false;
  void reset(DateTime now) {
    openedAt = now;
    lastProgressAt = null;
    position = Duration.zero;
    duration = Duration.zero;
    diagnostic = null;
    hasProgress = false;
  }

  void note(String message) {
    diagnostic = message;
  }

  bool sample({
    required DateTime now,
    required Duration currentPosition,
    required Duration currentDuration,
    required bool completed,
    required bool idle,
    bool paused = false,
  }) {
    if (currentDuration > Duration.zero) duration = currentDuration;
    if (currentPosition > Duration.zero && currentPosition != position) {
      position = currentPosition;
      lastProgressAt = now;
      hasProgress = true;
      diagnostic = null;
      return false;
    }
    final naturalEnd =
        duration > Duration.zero &&
        position >= duration - const Duration(seconds: 2);
    if (naturalEnd) return false;
    if (paused && !idle && !completed) return false;
    if (!hasProgress) {
      return now.difference(openedAt ?? now) >= const Duration(seconds: 40);
    }
    // Pausing and ordinary buffering are not fatal; idle/EOF must confirm a stop.
    return (idle || completed) &&
        now.difference(lastProgressAt ?? now) >= const Duration(seconds: 3);
  }
}
