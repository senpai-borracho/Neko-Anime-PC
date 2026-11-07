import 'dart:io';
import 'dart:convert';
import 'package:neko_player_pc/catalog.dart';
Future<void> main()async{final api=ProviderClient();try{final result=await api.catalog(query:'Dark Machine');final cards=result.cards.where((a)=>a.title.toLowerCase().contains('dark machine')).toList();final found=<Map<String,String>>[];for(final card in cards){for(final url in {card.url,...card.alternatives}){found.add({'title':card.title,'url':url,'provider':Uri.parse(url).host.contains('animeav1')?'AnimeAV1':'JKAnime'});}}await File('tool/dark_machine_sources.json').writeAsString(const JsonEncoder.withIndent('  ').convert(found));stdout.writeln(jsonEncode(found));if(found.length<2)exitCode=1;}finally{api.close();}}
