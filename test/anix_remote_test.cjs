const test = require('node:test');
const assert = require('node:assert/strict');
const {prepareEntry,createProvider} = require('../assets/extensions/anix_worker.cjs');
const entry={id:'fixture',name:'Fixture',manifestURI:'https://extensions.example/fixture/manifest.json',lang:'es'};
const ts='class Provider { private value: string = "ok"; getSettings(): any { return {supportsDub:true}; } async search(opts: any): Promise<any[]> { console.log("provider log"); return [{id:this.value,title:opts.query}]; } async findEpisodes(id: string): Promise<any[]> { return []; } async findEpisodeServer(ep: any): Promise<any> { return {}; } }';
const manifest={id:'fixture',type:'onlinestream-provider',language:'typescript',lang:'es',payloadURI:'provider.ts'};
test('relative payload, TypeScript compilation, settings and declared language',async()=>{
 const urls=[];const p=await prepareEntry(entry,async url=>{urls.push(url);return url.endsWith('.json')?JSON.stringify(manifest):ts});
 assert.deepEqual(urls,['https://extensions.example/fixture/manifest.json','https://extensions.example/fixture/provider.ts']);
 assert.equal(p.language,'javascript');assert.equal(p.originalLanguage,'typescript');assert.deepEqual(p.languages,{sub:['es'],dub:['es']});
 const results=await createProvider(p).search({query:'Naruto'});assert.equal(results[0].title,'Naruto');assert.equal(results[0].id,'ok');
});
test('reject mismatched manifest id before downloading code',async()=>{
 let calls=0;await assert.rejects(prepareEntry(entry,async()=>{calls++;return JSON.stringify({...manifest,id:'other'})}),/identificador/);assert.equal(calls,1);
});
test('reject HTTP manifests and payloads',async()=>{
 await assert.rejects(prepareEntry({...entry,manifestURI:'http://example.org/a'}),/HTTPS/);
 await assert.rejects(prepareEntry(entry,async()=>JSON.stringify({...manifest,payloadURI:'http://example.org/code'})),/HTTPS/);
});
test('reject incomplete provider without replacing the installed entry',async()=>{
 await assert.rejects(prepareEntry(entry,async url=>url.endsWith('.json')?JSON.stringify(manifest):'class Provider { getSettings(){return {}} }'),/no implementa search/);
 assert.equal(entry.payload,undefined);
});
test('foreign languages are preserved, not labelled Spanish',async()=>{
 const p=await prepareEntry(entry,async url=>url.endsWith('.json')?JSON.stringify({...manifest,lang:'fr'}):ts);
 assert.deepEqual(p.languages.sub,['fr']);
});
test('Seanime responses support sync and async reads and CryptoJS',async()=>{
 const {seanimeResponse}=require('../assets/extensions/anix_worker.cjs');
 const response=await seanimeResponse(new Response('{"answer":42}',{headers:{'content-type':'application/json'}}));
 assert.equal(response.json().answer,42);assert.equal((await response.json()).answer,42);
 assert.equal(response.text(),'{"answer":42}');assert.equal(response.headers.get('content-type'),'application/json');assert.equal(response.headers['content-type'],'application/json');
 const p=await prepareEntry(entry,async url=>url.endsWith('.json')?JSON.stringify(manifest):ts.replace('supportsDub:true','supportsDub:true,hash:CryptoJS.SHA256("test").toString()'));
 assert.equal(createProvider(p).getSettings().hash,'9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08');
});
