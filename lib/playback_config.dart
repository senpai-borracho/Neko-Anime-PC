import 'package:media_kit/media_kit.dart';

/// Match the proven Android network margin. No engine or package is modified.
Future<void> configurePlayback(Player player) async {
  final native = player.platform;
  if (native is NativePlayer) {
    await native.setProperty('network-timeout', '20');
  }
}
