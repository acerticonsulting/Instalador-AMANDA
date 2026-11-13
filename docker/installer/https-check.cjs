// Self-contained: serialized into the backend container. Never bypass TLS trust.
async function inspectHttps(targets, options = {}, adapters = {}) {
  const dns = adapters.dns || require('node:dns').promises;
  const request = adapters.request || ((url, address, family) => new Promise((resolve, reject) => {
    const https = require('node:https');
    const req = https.get(url, { servername: new URL(url).hostname,
      lookup: (_host, opts, cb) => opts.all ? cb(null, [{ address, family }]) : cb(null, address, family) }, res => {
      const cert = res.socket.getPeerCertificate();
      resolve({ status: res.statusCode, issuer: cert.issuer?.O, validFrom: cert.valid_from, validTo: cert.valid_to });
      res.resume();
    });
    const timer = setTimeout(() => req.destroy(Object.assign(Error('Timeout HTTPS'), { code: 'ETIMEDOUT' })), 8000);
    req.on('close', () => clearTimeout(timer)); req.on('error', reject);
  }));
  const results = [];
  for (const target of targets) {
    const hostname = new URL(target.url).hostname;
    const row = { hostname, addresses: [], checks: [], failures: [] };
    for (const [method, family] of [['resolve4', 4], ['resolve6', 6]]) {
      try { for (const address of await dns[method](hostname)) row.addresses.push({ address, family }); }
      catch (e) { if (!['ENODATA', 'ENOTFOUND'].includes(e.code)) row.failures.push({ kind: 'DNS', code: e.code || 'DNS_ERROR' }); }
    }
    if (!row.addresses.length) row.failures.push({ kind: 'DNS', code: 'ENOTFOUND' });
    for (const { address, family } of row.addresses) {
      if(options.connectivity){
        const tcp=adapters.tcp||((port)=>new Promise(resolve=>{
          const socket=require('node:net').connect({host:address,port,family});
          socket.setTimeout(3000);socket.once('connect',()=>{socket.destroy();resolve('connected');});
          socket.once('timeout',()=>{socket.destroy();resolve('ETIMEDOUT');});socket.once('error',e=>resolve(e.code));
        }));
        row.checks.push({address,family,httpPort80:await tcp(80)});
      }
      if (options.expectedAddresses?.length && !options.expectedAddresses.includes(address)) {
        row.failures.push({ kind: 'DNS', code: 'UNEXPECTED_ADDRESS', address, family }); continue;
      }
      try {
        const check = await request(target.url, address, family);
        row.checks.push({ address, family, ...check });
        if (target.exact ? check.status !== 200 : check.status < 200 || check.status >= 500)
          row.failures.push({ kind: 'HTTP', code: 'HTTP_' + check.status, address, family });
      } catch (e) {
        const code = String(e.code || e.cause?.code || 'HTTPS_ERROR');
        row.failures.push({ kind: /CERT|TLS|SSL|SELF_SIGNED|UNABLE_TO_VERIFY|UNABLE_TO_GET_ISSUER/.test(code) ? 'TLS' : 'REDE', code, address, family,
          ...(e.cert?{certificate:{san:e.cert.subjectaltname,issuer:e.cert.issuer?.O,validFrom:e.cert.valid_from,validTo:e.cert.valid_to}}:{}) });
      }
    }
    results.push(row);
  }
  return { ok: results.every(r => !r.failures.length), results };
}

async function awaitHttps({ probe, caddy, emit, timeoutMs = 120000, now = Date.now,
  sleep = ms => new Promise(r => setTimeout(r, ms)) }) {
  const deadline = now() + timeoutMs;
  let attempt = 0;
  while (true) {
    const report = await probe();
    for (const row of report.results) emit(JSON.stringify(row) + '\n');
    if (report.ok) return report;
    const logs = await caddy();
    const failures = report.results.flatMap(r => r.failures);
    const fatalAcme = /rateLimited|rate limit|urn:ietf:params:acme:error:(?:unauthorized|rejectedIdentifier|caa)|no valid A records|challenge failed/i.test(logs);
    const issuing = /obtaining certificate|trying to solve challenge|waiting on internal rate limiter|certificate obtain|obtaining.*lock/i.test(logs);
    const transient = failures.every(f => ['ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT', 'ERR_SSL_TLSV1_ALERT_INTERNAL_ERROR', 'ERR_SSL_SSLV3_ALERT_HANDSHAKE_FAILURE', 'EAI_AGAIN'].includes(f.code));
    const hints=require('./edge-diagnostics.cjs').acmeHints(logs);
    for(const hint of hints)emit(hint+'\n');
    if (fatalAcme || hints.length) throw Error('ACME: validação recusada. '+(hints.join(' ')||'Consulte logs do Caddy (CAA, desafio, autorização ou limite de emissão).'));
    if (!issuing || !transient || now() >= deadline) {
      throw Error('HTTPS público pendente: ' + report.results.flatMap(r => r.failures.map(f => `${r.hostname} ${f.kind} ${f.code}${f.address ? ' (' + f.address + ')' : ''}`)).join('; ') + (now() >= deadline ? '; timeout da validação' : '') + '. Revise DNS A/AAAA, firewall e logs do Caddy.');
    }
    const delay = Math.min(2000 * 2 ** Math.min(attempt++, 3), 15000, deadline - now());
    emit(`HTTPS pendente; Caddy apresenta atividade de emissão. Tentativa ${attempt}, nova verificação em ${delay} ms.\n`);
    await sleep(delay);
  }
}
module.exports = { inspectHttps, awaitHttps };
