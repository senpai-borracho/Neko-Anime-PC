import 'dart:convert';
import 'dart:io';
import '../runtime/node_runtime.dart';

/// Adaptador de Complementos. No modifica los motores de Neko ni de Anix.
class NuvioRuntime {
  static const worker = r'''
const vm = require('node:vm');
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', c => input += c);
process.stdin.on('end', async () => {
  const finish = value => process.stdout.write(JSON.stringify(value), () => process.exit());
  const timeout = setTimeout(() => finish({error:'El complemento tardó demasiado.'}), 30000);
  try {
    const request = JSON.parse(input);
    const module = {exports:{}};
    const context = vm.createContext({module, exports:module.exports,
      fetch, URL, URLSearchParams, TextEncoder, TextDecoder, atob, btoa,
      setTimeout, clearTimeout, AbortController, AbortSignal,
      console:{log(){},info(){},warn(){},error(){},debug(){}}});
    vm.runInContext('globalThis.global=globalThis;globalThis.window=globalThis;globalThis.self=globalThis;', context);
    vm.runInContext(request.code, context, {timeout:3000});
    context.__args = [request.id,request.type,request.season,request.episode];
    const result = await vm.runInContext('(module.exports.getStreams || (typeof getStreams === "function" ? getStreams : null))(...__args)',context,{timeout:3000});
    finish({streams:result});
  } catch(e) { finish({error:String(e.message||e)}); }
  finally { clearTimeout(timeout); }
});
''';

  static Future<List<Map<String, dynamic>>> run(
    String file,
    String id,
    String type,
    int? season,
    int? episode,
  ) async {
    final code = await File(file).readAsString();
    final Process process;
    try {
      process = await NodeRuntime.start(['-e', worker]);
    } on ProcessException {
      throw const FormatException(
        'No se pudo iniciar el runtime incluido de Neko. Reinstala Neko o extrae el portable completo.',
      );
    }
    try {
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      process.stdin.write(
        jsonEncode({
          'code': code,
          'id': id,
          'type': type,
          'season': season,
          'episode': episode,
        }),
      );
      await process.stdin.close();
      final result = jsonDecode(
        await output.timeout(const Duration(seconds: 35)),
      );
      await errors;
      if (result['error'] != null) throw FormatException('${result['error']}');
      var streams = result['streams'];
      if (streams is Map) streams = streams['streams'];
      return streams is List
          ? streams
                .whereType<Map>()
                .map((s) => Map<String, dynamic>.from(s))
                .toList()
          : [];
    } finally {
      process.kill();
    }
  }
}
