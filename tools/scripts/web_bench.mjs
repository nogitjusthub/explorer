// Замер веб-сборки без окон: свой сервер build/web, headless Chrome (или Edge) со свежим профилем (холодный
// кэш программ шейдеров) или прежним (повторный визит), зонд tools/web/gl_probe.js подмешивается до загрузки
// страницы, сценарий задаётся параметрами адреса (release на 127.0.0.1 принимает все — DevTools.release_filter).
// Итоги — build/web_runs/<время>-<сценарий>-<n>/: console.log, probe.json, summary.txt, gpu.txt, histograms.txt.
//
// Запуск (из корня репозитория, Node 22+ — без npm):
//   node tools/scripts/web_bench.mjs --scenario load|hangar|nohangar|full [--runs N] [--profile fresh|keep]
//        [--browser chrome|edge] [--seed N] [--gzip] [--timeout S] [--extra "a=1&b"] [--assert]
//        [--web DIR] [--tag NAME] [--keys q,d,a] (свои нажатия после загрузки) [--keys-delay S] (…и ещё через S секунд)
//        [--snaps 2,6,12] (снимки страницы на этих секундах) [--trace] (трейс Chrome → trace.json)
//        [--sources N] (исходники программ после загрузки и N самых дорогих → shader_sources.json)
//        [--query "seed=7&select&press=pause@3&shots=2" --after S] (свой адрес; ждём загрузки и ещё S секунд)
//        [--events "acid@1,tornado@3"] [--spawn X,Z] (события и точка старта сценария events)
//
// Сценарии (часы сценария — от конца загрузки):
//   load    трюм, без действий: до конца прогрева и готовности мира;
//   hangar  то же + переключение машин (D, D, A) — прогрев света трюма;
//   nohangar без трюма (сразу игра, мир грузится синхронно), до конца прогрева;
//   full    трюм → «Высадка» (сразу) → посадка → машина стоит до 120 с игры (бенчмарк);
//   results трюм → «Высадка» без десанта → челнок на площадке старта → «вернуться на орбиту» → экран итога
//           (портрет машины) → имя → «Заново» → экран загрузки → забег;
//   events  трюм → «Высадка» без десанта → за 10 с все существа, землетрясение, смерч, водоворот, молния →
//           до 60 с (гибель машины — экран итога); seed EVENTS_SEED, старт EVENTS_SPAWN у озера: рядом песок,
//           зыбун, мелкая и глубокая вода. Погода — по одной за раз: --events "acid@1,tornado@3" и т. п.;
//   map     без трюма, автопилот ездит → на 35-й секунде карта мира [M], на 39-й поворот камеры; снимки игры
//           (shot_*.png) каждые 3 с — карта на последних трёх (сам снимок — кадр ~50 мс: читается картинка).
// После загрузки не должно быть ни компиляций, ни кадров дольше 50 мс; окна повторной загрузки («Заново»,
// «Выход» — от restart_* до следующего loading_done) считаются отдельно.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import zlib from 'node:zlib';
import { spawn, spawnSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..', '..');
const PROBE = fs.readFileSync(path.join(ROOT, 'tools', 'web', 'gl_probe.js'), 'utf8');
const BROWSERS = {
	chrome: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
	edge: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};

const opts = parseArgs(process.argv.slice(2));
const WEB = path.resolve(ROOT, opts.web || path.join('build', 'web'));   // --web build/web_variants/x — A/B-сборки
const scenario = opts.scenario || 'load';
const runs = Number(opts.runs || 1);
const EVENTS_SEED = '16';
const EVENTS_SPAWN = '33,35';
const EVENTS = 'ray@1,shark@2,nessie@3,worm@4,hoppers@5,shellback@6,quake@7,tornado@8,whirlpool@9,strike@10';
const seed = opts.seed || (opts.scenario === 'events' ? EVENTS_SEED : '52821');
const spawnAt = opts.spawn || (opts.scenario === 'events' && seed === EVENTS_SEED ? EVENTS_SPAWN : '');
const spawnArg = spawnAt ? `&spawn=${spawnAt}` : '';
const timeoutS = Number(opts.timeout || 600);

const SCENARIOS = {
	load: { query: `seed=${seed}&select&idle&log-slow=50`, until: (s) => s.has('loading_done'), after: 3 },
	hangar: { query: `seed=${seed}&select&idle&log-slow=50`, until: (s) => s.has('loading_done'), after: 2, keys: ['d', 'd', 'a'] },
	nohangar: { query: `seed=${seed}&idle&log-slow=50`, until: (s) => s.has('warmup_done'), after: 3 },
	full: { query: `seed=${seed}&select&idle&press=radio@1&bench=120&log-slow=50`, until: (s) => s.has('bench_done'), after: 1 },
	results: { query: `seed=${seed}&select&idle&no-drop&shuttle-in=3&shuttle-dist=0&press=radio@1,radio@14,radio@22,restart@25&log-slow=50`, until: (s, n) => (n.loading_done || 0) >= 2, after: 5 },
	map: { query: `seed=${seed}&autopilot&press=map@35,cam_right@39&shots=14&shot-every=3&log-slow=50`, until: (s) => s.has('warmup_done'), after: 55 },
	events: { query: `seed=${seed}${spawnArg}&select&idle&no-drop&press=radio@1&event=${opts.events || EVENTS}&bench=60&log-slow=50`, until: (s) => s.has('bench_done'), after: 1 },
};
// --query "seed=7&select&press=pause@3&shots=2" — свой сценарий: ждём конца загрузки и ещё --after секунд.
if (opts.query) SCENARIOS.custom = { query: String(opts.query), until: (s) => s.has('loading_done') || s.has('warmup_done'), after: Number(opts.after || 10) };
const sc = SCENARIOS[opts.query ? 'custom' : scenario];
if (!sc) die(`unknown scenario ${scenario}`);

const stamp = new Date().toISOString().replace(/[:T]/g, '-').slice(0, 19);
const keepProfile = path.join(os.tmpdir(), 'explorer-bench-profile');
const results = [];
for (let n = 1; n <= runs; n++) {
	const dir = path.join(ROOT, 'build', 'web_runs', `${stamp}-${opts.tag || scenario}-${n}`);
	fs.mkdirSync(dir, { recursive: true });
	const profile = opts.profile === 'keep' ? keepProfile : fs.mkdtempSync(path.join(os.tmpdir(), 'explorer-bench-'));
	console.log(`run ${n}/${runs}: ${scenario}, profile ${opts.profile === 'keep' ? 'kept' : 'fresh'} → ${dir}`);
	const r = await runOnce(dir, profile);
	results.push(r);
	console.log(summaryLine(r));
	if (opts.profile !== 'keep') {
		await sleep(1500);                 // Chrome отпускает файлы профиля не сразу
		try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 }); } catch (e) { console.log(`  (profile left: ${profile})`); }
	}
}
if (opts.assert) {
	const bad = results.filter((r) => r.slowAfterLoad > 0 || r.progsAfterLoad > 0);
	if (bad.length) die(`assert failed: ${bad.length} run(s) with frames > 50 ms or compiles after loading`);
}
process.exit(0);

// ------------------------------------------------------------------------------------------------------

async function runOnce(dir, profile) {
	const server = await serve(dir);
	const port = server.address().port;
	const exe = BROWSERS[opts.browser || 'chrome'];
	const args = [
		'--headless=new', `--user-data-dir=${profile}`, '--remote-debugging-port=0', '--no-first-run',
		'--no-default-browser-check', '--ignore-gpu-blocklist', '--enable-gpu', '--use-angle=d3d11',
		'--autoplay-policy=no-user-gesture-required', '--mute-audio', '--window-size=960,640', '--disable-background-timer-throttling',
		'--disable-renderer-backgrounding', 'about:blank',
	];
	const browser = spawn(exe, args, { windowsHide: true, stdio: 'ignore' });
	const log = fs.createWriteStream(path.join(dir, 'console.log'));
	let wsPort = 0;
	try {
		wsPort = await waitFile(path.join(profile, 'DevToolsActivePort'), 15000);
		const page = await connectPage(wsPort);
		const seen = new Set();
		const counts = {};                     // сколько раз была метка (loading_done после «Заново» — второй)
		const t0 = Date.now();
		page.on('Runtime.consoleAPICalled', (p) => {
			const text = p.args.map((a) => a.value ?? a.description ?? '').join(' ');
			log.write(`${((Date.now() - t0) / 1000).toFixed(3)} ${text}\n`);
			const m = text.match(/^mark (\S+)/);
			if (m) { seen.add(m[1]); counts[m[1]] = (counts[m[1]] || 0) + 1; }
			if (text.startsWith('bench: objects')) seen.add('bench_done');
		});
		page.on('Runtime.exceptionThrown', (p) => log.write(`EXCEPTION ${JSON.stringify(p.exceptionDetails).slice(0, 500)}\n`));
		await page.send('Runtime.enable');
		await page.send('Page.enable');
		await page.send('Page.addScriptToEvaluateOnNewDocument', { source: PROBE });
		// --trace: трейс Chrome (Perfetto / chrome://tracing) — что делает браузер в долгих кадрах.
		const traceChunks = [];
		if (opts.trace) {
			page.on('Tracing.dataCollected', (p) => traceChunks.push(...p.value));
			await page.send('Tracing.start', { transferMode: 'ReportEvents', traceConfig: { includedCategories: ['toplevel', 'blink', 'v8', 'gpu', 'disabled-by-default-devtools.timeline', 'devtools.timeline', 'webaudio', 'audio'] } });
		}
		const extra = opts.extra ? `&${opts.extra}` : '';
		await page.send('Page.navigate', { url: `http://127.0.0.1:${port}/index.html?${sc.query}${extra}` });
		for (const at of String(opts.snaps || '').split(',').filter(Boolean)) {
			setTimeout(async () => {
				try {
					const shot = await page.send('Page.captureScreenshot', { format: 'png' });
					fs.writeFileSync(path.join(dir, `page_${String(at).padStart(3, '0')}s.png`), Buffer.from(shot.data, 'base64'));
				} catch (e) { /* страница занята — пропускаем */ }
			}, Number(at) * 1000);
		}
		// Ждём сценарий; нажатия — после прогрева (клавиши по CDP, окно не нужно).
		const deadline = Date.now() + timeoutS * 1000;
		while (!sc.until(seen, counts) && Date.now() < deadline) await sleep(250);
		const keys = opts.keys ? String(opts.keys).split(',') : sc.keys;   // --keys q,d,a — свои нажатия
		if (keys && opts['keys-delay']) await sleep(Number(opts['keys-delay']) * 1000);
		if (keys) {
			for (const k of keys) { await key(page, k); await sleep(700); }
		}
		await sleep(sc.after * 1000);
		const timedOut = !sc.until(seen, counts);
		if (opts.trace) {
			const done = new Promise((r) => page.on('Tracing.tracingComplete', r));
			await page.send('Tracing.end');
			await withTimeout(done, 60000);
			fs.writeFileSync(path.join(dir, 'trace.json'), JSON.stringify({ traceEvents: traceChunks }));
		}
		const summary = (await page.send('Runtime.evaluate', { expression: 'JSON.stringify(window.__glProbe && window.__glProbe.summary())', returnByValue: true })).result.value;
		const sum = summary ? JSON.parse(summary) : {};
		const programs = (await page.send('Runtime.evaluate', { expression: 'JSON.stringify(window.__glProbe && window.__glProbe.programs)', returnByValue: true })).result.value;
		fs.writeFileSync(path.join(dir, 'probe.json'), JSON.stringify({ summary: sum, programs: programs ? JSON.parse(programs) : [] }, null, 1));
		if (opts.sources) {
			// Исходники самых дорогих программ (все сразу — десятки МБ строкой через CDP).
			const progs = programs ? JSON.parse(programs) : [];
			const ldMark = (sum.marks || []).find((m) => m.name === 'loading_done')?.t ?? Infinity;
			const late = progs.filter((p) => p.t > ldMark).map((p) => p.key);   // скомпилированные после загрузки — все
			const keys = [...new Set([...late, ...progs.slice().sort((a, b) => cost(b) - cost(a)).slice(0, Number(opts.sources) || 40).map((p) => p.key)])];
			// Страница сама шлёт их POST-ом на наш сервер (большая строка через CDP не проходит).
			await withTimeout(page.send('Runtime.evaluate', { expression: `fetch('/sources', {method: 'POST', body: JSON.stringify(window.__glProbe.sourcesFor(${JSON.stringify(keys)}))}).then(() => 1)`, awaitPromise: true }), 60000);
		}
		fs.writeFileSync(path.join(dir, 'gpu.txt'), await withTimeout(pageText(wsPort, 'chrome://gpu'), 20000) || '(timeout)');
		fs.writeFileSync(path.join(dir, 'histograms.txt'), await withTimeout(pageText(wsPort, 'chrome://histograms/GPU'), 20000) || '(timeout)');
		const r = analyze(sum, programs ? JSON.parse(programs) : [], timedOut, Date.now() - t0);
		fs.writeFileSync(path.join(dir, 'summary.txt'), report(r, sum));
		page.close();
		return r;
	} finally {
		log.end();
		await closeBrowser(wsPort, profile);
		browser.kill();
		server.close();
	}
}

function analyze(sum, progs, timedOut, wallMs) {
	const marks = sum.marks || [];
	const mark = (n) => marks.find((m) => m.name === n)?.t ?? null;
	const loadEnd = mark('loading_done') ?? Math.max(mark('warmup_done') ?? 0, mark('world_ready') ?? 0);
	// Повторные загрузки («Заново», «Выход»): от restart_* до следующего loading_done — там экран загрузки.
	const reloads = [];
	for (const m of marks) {
		if (!m.name.startsWith('restart_')) continue;
		const end = marks.find((e) => e.name === 'loading_done' && e.t > m.t)?.t ?? Infinity;
		reloads.push({ name: m.name, from: m.t, to: end });
	}
	const inReload = (t) => reloads.some((w) => t >= w.from && t <= w.to);
	const afterLoad = (sum.slowFrames || []).filter((f) => f.t > loadEnd && !inReload(f.t));
	const late = progs.filter((p) => p.t > loadEnd && !inReload(p.t));
	return {
		timedOut, wallMs, renderer: sum.info?.renderer, parallel: sum.info?.parallelCompile,
		programs: sum.programs ?? 0, neverBound: sum.neverBound ?? 0, neverBoundMs: sum.neverBoundMs ?? 0, blockingMs: sum.blockingMs ?? 0,
		uniqueSources: sum.uniqueSources ?? 0,
		wasmEnd: sum.resources?.['index.wasm']?.end ?? null, context: sum.info?.contextAt ?? null,
		mainReady: mark('main_ready'), hangarReady: mark('hangar_ready'), worldReady: mark('world_ready'),
		warmupDone: mark('warmup_done'), loadingDone: mark('loading_done'), runStart: mark('run_start'),
		slowAfterLoad: afterLoad.length, progsAfterLoad: late.length,   // по списку программ (кадры зонда их не видят)
		worstAfterLoad: afterLoad.reduce((m, f) => Math.max(m, f.gap), 0),
		late: late.map((p) => ({ t: Math.round(p.t), phase: p.phase, ms: Math.round(cost(p)) })),
		reloads: reloads.map((w) => ({ name: w.name, ms: Math.round(w.to - w.from), programs: progs.filter((p) => p.t >= w.from && p.t <= w.to).length })),
	};
}

function summaryLine(r) {
	const s = (v) => (v == null ? '—' : (v / 1000).toFixed(1) + ' s');
	const rl = r.reloads.map((w) => ` | ${w.name}: loading ${s(w.ms)}, ${w.programs} programs`).join('');
	return `  ${r.timedOut ? 'TIMEOUT ' : ''}wasm ${s(r.wasmEnd)}, context ${s(r.context)}, main ${s(r.mainReady)}, world ${s(r.worldReady)}, warmup ${s(r.warmupDone)}, loaded ${s(r.loadingDone)}, run ${s(r.runStart)} | programs ${r.programs} (never drawn ${r.neverBound}, ${s(r.neverBoundMs)}), blocking GL ${s(r.blockingMs)} | after load: ${r.slowAfterLoad} frames > 50 ms (worst ${r.worstAfterLoad} ms, ${r.progsAfterLoad} programs)${rl} | ${r.renderer}`;
}

function report(r, sum) {
	const lines = [summaryLine(r), '', 'by phase (programs / never bound / blocking ms):'];
	const phases = Object.entries(sum.byPhase || {}).sort((a, b) => b[1].ms - a[1].ms);
	for (const [ph, g] of phases) lines.push(`  ${ph.padEnd(28)} ${String(g.programs).padStart(4)} ${String(g.neverBound).padStart(4)} ${String(Math.round(g.ms)).padStart(8)}`);
	lines.push('', 'programs after loading (t, phase, ms):');
	for (const p of r.late) lines.push(`  ${String(p.t).padStart(7)} ${p.phase.padEnd(28)} ${String(p.ms).padStart(6)}`);
	lines.push('', 'marks (ms from navigation):');
	for (const m of sum.marks || []) lines.push(`  ${m.name.padEnd(28)} ${m.t}`);
	lines.push('', 'frames > 50 ms (t, gap, gl, programs, phase):');
	for (const f of (sum.slowFrames || []).slice().sort((a, b) => b.gap - a.gap).slice(0, 40)) lines.push(`  ${String(f.t).padStart(7)} ${String(f.gap).padStart(6)} ${String(f.gl).padStart(6)} ${String(f.progs).padStart(4)}  ${f.phase}`);
	return lines.join('\n') + '\n';
}

// --- CDP ------------------------------------------------------------------------------------------------

// Закрыть Chrome целиком: Browser.close по CDP, потом добить процессы с этим профилем по PID. Chrome на старте
// перезапускает себя — PID из spawn уже не тот, и kill() оставлял браузер жить (со звуком, GPU, рендерерами).
async function closeBrowser(wsPort, profile) {
	if (wsPort) {
		try {
			const v = await (await withTimeout(fetch(`http://127.0.0.1:${wsPort}/json/version`), 5000)).json();
			const b = await cdp(v.webSocketDebuggerUrl);
			await withTimeout(b.send('Browser.close'), 5000);
		} catch (e) { /* уже закрыт */ }
		await sleep(1000);
	}
	const ps = `Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*${path.basename(profile)}*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`;
	spawnSync('powershell', ['-NoProfile', '-Command', ps], { windowsHide: true, stdio: 'ignore' });
}

async function connectPage(port) {
	const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
	const target = list.find((t) => t.type === 'page');
	return cdp(target.webSocketDebuggerUrl);
}

async function pageText(port, url) {
	try {
		const t = await (await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' })).json();
		const c = await cdp(t.webSocketDebuggerUrl);
		await c.send('Runtime.enable');
		await sleep(2500);
		const v = (await c.send('Runtime.evaluate', { expression: 'document.body ? document.body.innerText : ""', returnByValue: true })).result.value;
		c.close();
		return v || '';
	} catch (e) {
		return `(failed: ${e.message})`;
	}
}

function cdp(url) {
	return new Promise((resolve, reject) => {
		const ws = new WebSocket(url);
		let id = 0;
		const pending = new Map();
		const handlers = new Map();
		ws.onmessage = (ev) => {
			const msg = JSON.parse(ev.data);
			if (msg.id && pending.has(msg.id)) {
				const { res, rej } = pending.get(msg.id);
				pending.delete(msg.id);
				msg.error ? rej(new Error(msg.error.message)) : res(msg.result);
			} else if (msg.method && handlers.has(msg.method)) {
				for (const h of handlers.get(msg.method)) h(msg.params);
			}
		};
		ws.onerror = (e) => reject(new Error('cdp socket error'));
		ws.onopen = () => resolve({
			send: (method, params = {}) => new Promise((res, rej) => {
				const i = ++id;
				pending.set(i, { res, rej });
				ws.send(JSON.stringify({ id: i, method, params }));
			}),
			on: (method, h) => { if (!handlers.has(method)) handlers.set(method, []); handlers.get(method).push(h); },
			close: () => ws.close(),
		});
	});
}

async function key(page, k) {
	const code = 'Key' + k.toUpperCase();
	const vk = k.toUpperCase().charCodeAt(0);
	await page.send('Input.dispatchKeyEvent', { type: 'keyDown', key: k, code, windowsVirtualKeyCode: vk, text: k });
	await sleep(80);
	await page.send('Input.dispatchKeyEvent', { type: 'keyUp', key: k, code, windowsVirtualKeyCode: vk });
}

// --- сервер -----------------------------------------------------------------------------------------------

function serve(dir) {
	const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
	const gz = new Map();
	const server = http.createServer((req, res) => {
		const url = decodeURIComponent(req.url.split('?')[0]);
		if (req.method === 'POST') {
			const chunks = [];
			req.on('data', (c) => chunks.push(c));
			req.on('end', () => {
				const body = Buffer.concat(chunks);
				if (url === '/log') fs.appendFileSync(path.join(dir, 'web_log.txt'), body.toString() + '\n');
				else if (url === '/sources') fs.writeFileSync(path.join(dir, 'shader_sources.json'), body);
				else if (url === '/shot') fs.writeFileSync(path.join(dir, `shot_${Date.now()}.png`), body);
				res.end('ok');
			});
			return;
		}
		const file = path.join(WEB, url === '/' ? 'index.html' : url);
		if (!file.startsWith(WEB) || !fs.existsSync(file)) { res.statusCode = 404; res.end(); return; }
		const ext = path.extname(file);
		res.setHeader('Content-Type', types[ext] || 'application/octet-stream');
		res.setHeader('Cache-Control', 'no-store');
		let data = fs.readFileSync(file);
		if (opts.gzip && /gzip/.test(req.headers['accept-encoding'] || '') && ext !== '.png') {
			if (!gz.has(file)) gz.set(file, zlib.gzipSync(data, { level: 6 }));
			data = gz.get(file);
			res.setHeader('Content-Encoding', 'gzip');
		}
		res.end(data);
	});
	return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// --- мелочи ------------------------------------------------------------------------------------------------

async function waitFile(file, ms) {
	const end = Date.now() + ms;
	while (Date.now() < end) {
		if (fs.existsSync(file)) {
			const port = fs.readFileSync(file, 'utf8').split('\n')[0].trim();
			if (port) return Number(port);
		}
		await sleep(100);
	}
	throw new Error('browser did not start (no DevToolsActivePort)');
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

function withTimeout(promise, ms) { return Promise.race([promise, sleep(ms).then(() => null)]); }

function cost(p) { return p.compileMs + p.linkMs + p.statusMs; }

function parseArgs(argv) {
	const o = {};
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (!a.startsWith('--')) continue;
		const k = a.slice(2);
		const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
		o[k] = v;
	}
	return o;
}

function die(msg) { console.error(msg); process.exit(1); }
