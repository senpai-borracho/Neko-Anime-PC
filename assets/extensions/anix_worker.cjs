'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const readline = require('node:readline');
const zlib = require('node:zlib');
const { stripTypeScriptTypes } = require('node:module');
const { TextDecoder, TextEncoder } = require('node:util');
const catalog = require.main === module ? JSON.parse(fs.readFileSync(process.argv[2], 'utf8')) : {plugins: []};
const plugins = new Map(catalog.plugins.filter(p => p.language === 'javascript' && typeof p.payload === 'string').map(p => [p.id, p]));
const runtime = new Map();
const CryptoJS = require('./crypto-js.cjs');
async function seanimeResponse(response) {
  const chunks = []; let size = 0;
  if (response.body) for await (const chunk of response.body) {
    size += chunk.length;
    if (size > 8 * 1024 * 1024) throw Error('Respuesta de la extensión demasiado grande');
    chunks.push(chunk);
  }
  const bytes = Buffer.concat(chunks);
  const text = bytes.toString('utf8').replace(/^\uFEFF/, '');
  const fields = Object.fromEntries(response.headers);
  const headers = new Proxy(fields, {get(target, key) {
    if (key in target) return target[key];
    const value = response.headers[key];
    return typeof value === 'function' ? value.bind(response.headers) : value;
  }});
  return {ok: response.ok, status: response.status, statusText: response.statusText,
    url: response.url, redirected: response.redirected, headers,
    contentType: response.headers.get('content-type') || '',
    text: () => text, json: () => JSON.parse(text),
    arrayBuffer: () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)};
}
function createProvider(p) {
  const store = new Map();
  const context = vm.createContext({
    fetch: async (url, opts = {}) => {
      const parsed = new URL(String(url));
      if (parsed.protocol !== 'https:') throw Error('Solo se permite HTTPS');
      const response = await fetch(parsed, { ...opts, signal: AbortSignal.timeout(18000) });
      return p.compatibility === 'seanime' ? seanimeResponse(response) : response;
    },
    console: {log() {}, info() {}, warn() {}, error() {}, debug() {}},
    URL, URLSearchParams, TextDecoder, TextEncoder, atob, btoa,
    ...(p.compatibility === 'seanime' ? {CryptoJS} : {}),
    setTimeout, clearTimeout, Uint8Array, ArrayBuffer,
    $store: {get: key => store.get(key), set: (key, value) => store.set(key, value), delete: key => store.delete(key)},
    $anilili: {
      fetchBytes: async (url, opts = {}) => {
        const response = await fetch(String(url), { ...opts, signal: AbortSignal.timeout(18000) });
        if (!response.ok) throw Error('HTTP ' + response.status);
        return Array.from(new Uint8Array(await response.arrayBuffer()));
      },
      xor: (bytes, key) => {
        const input = Uint8Array.from(bytes);
        const secret = typeof key === 'string' ? Buffer.from(key) : Uint8Array.from(key);
        return Array.from(input.map((v, i) => v ^ secret[i % secret.length]));
      },
      gunzip: bytes => Array.from(zlib.gunzipSync(Buffer.from(bytes))),
    },
  });
  vm.runInContext(p.payload + '\n;globalThis.__nekoProvider = new Provider();', context, { timeout: 1500, filename: p.id + '.js' });
  const instance = context.__nekoProvider;
  for (const method of ['getSettings', 'search', 'findEpisodes', 'findEpisodeServer']) {
    if (typeof instance[method] !== 'function') throw Error('La extensión no implementa ' + method);
  }
  return instance;
}
function load(id) {
  if (!plugins.has(id)) throw Error('Extensión JS no disponible: ' + id);
  if (!runtime.has(id)) runtime.set(id, createProvider(plugins.get(id)));
  return runtime.get(id);
}
function httpsUrl(value, base) {
  const url = new URL(value, base);
  if (url.protocol !== 'https:' || url.username || url.password) throw Error('La extensión requiere una URL HTTPS válida');
  return url;
}
async function downloadText(value, limit) {
  let url = httpsUrl(value);
  const signal = AbortSignal.timeout(15000);
  for (let redirects = 0; redirects <= 5; redirects++) {
    const res = await fetch(url, {redirect: 'manual', signal});
    if ([301,302,303,307,308].includes(res.status)) {
      await res.body?.cancel();
      url = httpsUrl(res.headers.get('location'), url);
      continue;
    }
    if (!res.ok) { await res.body?.cancel(); throw Error('Descarga HTTP ' + res.status); }
    if (Number(res.headers.get('content-length')) > limit) { await res.body?.cancel(); throw Error('Archivo demasiado grande'); }
    const chunks = []; let size = 0;
    for await (const chunk of res.body) {
      size += chunk.length;
      if (size > limit) { throw Error('Archivo demasiado grande'); }
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8').replace(/^\uFEFF/, '');
  }
  throw Error('Demasiadas redirecciones');
}
async function prepareEntry(entry, fetchText = downloadText) {
  if (!entry || typeof entry.id !== 'string' || typeof entry.manifestURI !== 'string') throw Error('Falta el manifiesto de la extensión');
  const manifestUrl = httpsUrl(entry.manifestURI).href;
  const remote = JSON.parse(await fetchText(manifestUrl, 256 * 1024));
  if (remote.id !== entry.id) throw Error('El identificador del manifiesto no coincide con la extensión');
  if (remote.type !== 'onlinestream-provider') throw Error('El manifiesto no es una extensión de streaming');
  if (!['javascript', 'typescript'].includes(remote.language)) throw Error('Lenguaje de extensión no admitido: ' + remote.language);
  if (typeof remote.payloadURI !== 'string') throw Error('El manifiesto no incluye payloadURI');
  const payloadUrl = httpsUrl(remote.payloadURI, manifestUrl).href;
  let payload = await fetchText(payloadUrl, 2 * 1024 * 1024);
  if (remote.language === 'typescript') payload = stripTypeScriptTypes(payload, {mode: 'transform', sourceUrl: entry.id + '.ts'});
  const prepared = {...entry, ...remote, id: entry.id, language: 'javascript', originalLanguage: remote.language, compatibility: 'seanime', manifestURI: manifestUrl, payloadURI: payloadUrl, payload};
  const provider = createProvider(prepared);
  const settings = provider.getSettings();
  if (settings && typeof settings.then === 'function') throw Error('getSettings debe ser síncrono');
  if (!prepared.languages) {
    const langs = Array.isArray(prepared.lang) ? prepared.lang : typeof prepared.lang === 'string' ? [prepared.lang] : [];
    prepared.languages = {sub: langs, dub: settings?.supportsDub ? langs : []};
  }
  return prepared;
}
async function dispatch(req) {
  if (req.op === 'list') return catalog.plugins.map(({id, name, description, language, version, languages, manifestURI, lang}) => ({id,name,description,language,version,languages,manifestURI,lang, supported: plugins.has(id), downloadable: !plugins.has(id) && typeof manifestURI === 'string'}));
  if (req.op === 'prepare') return prepareEntry(req.entry);
  const p = load(req.plugin);
  if (req.op === 'settings') return p.getSettings();
  if (req.op === 'search') return p.search(req.options || {});
  if (req.op === 'episodes') return p.findEpisodes(req.animeId);
  if (req.op === 'server') return p.findEpisodeServer(req.episode, req.server || 'default');
  throw Error('Operación desconocida');
}
if (require.main === module) {
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on('line', async line => {
    let id;
    try {
      const req = JSON.parse(line); id = req.id;
      let timer; let result;
      try {
        result = await Promise.race([dispatch(req), new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Tiempo de espera agotado (35 s)')), 35000); })]);
      } finally { clearTimeout(timer); }
      process.stdout.write(JSON.stringify({ id, ok: true, result }) + '\n');
    } catch (error) {
      process.stdout.write(JSON.stringify({ id, ok: false, error: String(error?.message || error) }) + '\n');
    }
  });
}
module.exports = {prepareEntry, createProvider, seanimeResponse};
