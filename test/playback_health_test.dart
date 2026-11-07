import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/playback_health.dart';

void main() {
  test('A deliberate pause at the first frame is not an opening failure', () {
    final now = DateTime(2026, 10, 29);
    final h = PlaybackHealth()..reset(now);
    expect(
      h.sample(
        now: now.add(const Duration(minutes: 2)),
        currentPosition: Duration.zero,
        currentDuration: const Duration(minutes: 24),
        completed: false,
        idle: false,
        paused: true,
      ),
      false,
    );
  });
  final start = DateTime(2026, 10, 29);
  bool sample(
    PlaybackHealth health,
    int seconds,
    int position, {
    int duration = 1400,
    bool idle = false,
    bool completed = false,
  }) => health.sample(
    now: start.add(Duration(seconds: seconds)),
    currentPosition: Duration(seconds: position),
    currentDuration: Duration(seconds: duration),
    completed: completed,
    idle: idle,
  );
  test('Diagnostics do not cover a video that keeps advancing', () {
    final h = PlaybackHealth()..reset(start);
    sample(h, 1, 1);
    h.note('Failed hardware decoder; falling back');
    expect(sample(h, 2, 2), false);
    expect(h.diagnostic, isNull);
    h.note('Temporary tcp message');
    expect(sample(h, 5, 5), false);
  });
  test('Pause and buffering do not become a fatal error', () {
    final h = PlaybackHealth()..reset(start);
    sample(h, 1, 10);
    h.note('Temporary network error');
    expect(sample(h, 50, 10), false);
    expect(sample(h, 51, 11), false);
  });
  test('Natural episode completion has no error overlay', () {
    final h = PlaybackHealth()..reset(start);
    sample(h, 1, 1399);
    h.note('EOF');
    expect(sample(h, 20, 1399, idle: true, completed: true), false);
  });
  test('Premature EOF must persist before it is considered interrupted', () {
    final h = PlaybackHealth()..reset(start);
    sample(h, 1, 30);
    expect(sample(h, 2, 30, completed: true), false);
    expect(sample(h, 5, 30, completed: true), true);
    expect(sample(h, 6, 31), false);
  });
  test('Opening without playback times out after 40 seconds', () {
    final h = PlaybackHealth()..reset(start);
    expect(sample(h, 39, 0, duration: 0, idle: true), false);
    expect(sample(h, 40, 0, duration: 0, idle: true), true);
  });
  test('Changing servers clears old diagnostics and progress', () {
    final h = PlaybackHealth()..reset(start);
    sample(h, 1, 100);
    h.note('Old error');
    h.reset(start.add(const Duration(seconds: 20)));
    expect(h.diagnostic, isNull);
    expect(h.position, Duration.zero);
    expect(sample(h, 21, 0, duration: 0, idle: true), false);
  });
}
