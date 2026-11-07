import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/runtime/node_runtime.dart';

void main() {
  test(
    'runtime uses application-relative path including spaces and never PATH',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'neko runtime path ',
      );
      try {
        final node = File('${directory.path}/runtime/node/node.exe');
        await node.parent.create(recursive: true);
        await node.writeAsString('fixture');
        expect(
          NodeRuntime.resolve(
            applicationExecutable: '${directory.path}/neko_player_pc.exe',
          ),
          node.resolveSymbolicLinksSync(),
        );
        await node.delete();
        expect(
          () => NodeRuntime.resolve(
            applicationExecutable: '${directory.path}/neko_player_pc.exe',
            projectDirectory: Directory.current.path,
          ),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'development invokes the included binary and strips external Node options',
    () async {
      final process = await NodeRuntime.start([
        '-p',
        'JSON.stringify({path:process.execPath,options:process.env.NODE_OPTIONS})',
      ]);
      final result = jsonDecode(
        await process.stdout.transform(utf8.decoder).join(),
      );
      await process.stderr.drain<void>();
      expect(await process.exitCode, 0);
      expect(
        File(result['path']).absolute.path.toLowerCase(),
        NodeRuntime.resolve().toLowerCase(),
      );
      expect(result['options'], isNull);
      expect(NodeRuntime.environment.containsKey('NODE_PATH'), isFalse);
    },
  );
}
