import 'dart:io';

/// Runtime privado distribuido con Neko; nunca busca node en PATH.
class NodeRuntime {
  static String resolve({
    String? applicationExecutable,
    String? projectDirectory,
  }) {
    final executable = File(
      applicationExecutable ?? Platform.resolvedExecutable,
    ).absolute;
    final name = executable.uri.pathSegments.last.toLowerCase();
    final bundled = File('${executable.parent.path}/runtime/node/node.exe');
    if (bundled.existsSync()) return bundled.resolveSymbolicLinksSync();
    // Flutter/Dart de desarrollo: utiliza el mismo binario preparado en el proyecto.
    if ([
      'dart.exe',
      'flutter_tester.exe',
      'dart',
      'flutter_tester',
    ].contains(name)) {
      final development = File(
        '${projectDirectory ?? Directory.current.path}/runtime/node/node.exe',
      );
      if (development.existsSync()) return development.resolveSymbolicLinksSync();
    }
    throw const FileSystemException(
      'Falta el runtime incluido de Neko. Reinstala Neko o extrae el portable completo.',
    );
  }

  static Map<String, String> get environment =>
      Map<String, String>.from(Platform.environment)
        ..remove('NODE_OPTIONS')
        ..remove('NODE_PATH');

  static Future<Process> start(List<String> arguments) => Process.start(
    resolve(),
    arguments,
    runInShell: false,
    includeParentEnvironment: false,
    environment: environment,
  );
}
