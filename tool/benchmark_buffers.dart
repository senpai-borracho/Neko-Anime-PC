import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Microprueba de la acumulación de una respuesta de 8 MiB; no mide la RAM de Neko.
void main(List<String> args) {
  final optimized = args.contains('optimized');
  final before = ProcessInfo.currentRss;
  final clock = Stopwatch()..start();
  final list = <int>[];
  final builder = BytesBuilder(copy: false);
  for (var i = 0; i < 128; i++) {
    final chunk = Uint8List(65536)..fillRange(0, 65536, 97);
    if (optimized) {
      builder.add(chunk);
    } else {
      list.addAll(chunk);
    }
  }
  final result = utf8.decode(optimized ? builder.takeBytes() : list);
  clock.stop();
  stdout.writeln(
    jsonEncode({
      'mode': optimized ? 'optimized' : 'original',
      'decodedBytes': result.length,
      'milliseconds': clock.elapsedMicroseconds / 1000,
      'rssDeltaMiB': (ProcessInfo.currentRss - before) / 1048576,
    }),
  );
}
