import 'dart:io';
import 'package:neko_player_pc/addons/anix_catalog.dart';

Future<void> main() async {
  final client=AnixCatalog(directory:Directory('work/anix-catalog-probe'));
  final result=await client.load(1);
  stdout.writeln('Portadas recibidas: ${result.items.length}');
  stdout.writeln('Con imagen: ${result.items.where((s)=>'${s['image']}'.startsWith('https://')).length}');
  if(result.notice.isNotEmpty) stdout.writeln(result.notice);
}
