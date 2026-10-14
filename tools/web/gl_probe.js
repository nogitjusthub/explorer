// Зонд WebGL для замеров веб-сборки (tools/scripts/web_bench.mjs подмешивает его до загрузки страницы через
// CDP Page.addScriptToEvaluateOnNewDocument). Считает программы шейдеров и сколько времени главный поток
// стоял на их компиляции и линковке (в WebGL2 Godot проверяет линковку сразу — это и есть зависание),
// какие программы так ни разу и не привязались (useProgram) — лишние, длительности кадров
// requestAnimationFrame и долгие задачи. Этап берётся из window.__exPhase — его ставит DevTools.mark().
// Итоги — window.__glProbe.summary(); исходники шейдеров — __glProbe.sources() (для прекомпиляции).
(() => {
	if (window.__glProbe) return;
	const t0 = performance.now();
	const P = {
		t0,
		info: {},
		programs: [],          // {id, phase, t, compileMs, linkMs, statusMs, bound, draws, firstDrawPhase, key}
		frames: [],            // {t, gap, js, gl, progs, phase}
		longtasks: [],         // {t, ms, phase}
		phase: () => window.__exPhase || 'boot',
	};
	window.__glProbe = P;
	const now = () => performance.now() - t0;
	let frameGl = 0;           // мс блокирующих вызовов GL в текущем кадре
	let frameProgs = 0;
	const sources = new Map(); // ключ вершинный+фрагментный → {vs, fs}

	const proto = WebGL2RenderingContext.prototype;
	const timed = (name, after) => {
		const orig = proto[name];
		proto[name] = function (...a) {
			const s = performance.now();
			const r = orig.apply(this, a);
			const d = performance.now() - s;
			frameGl += d;
			if (after) after(a, d, r);
			return r;
		};
	};
	const passthrough = (name, before) => {
		const orig = proto[name];
		proto[name] = function (...a) {
			before(a);
			return orig.apply(this, a);
		};
	};
	passthrough('shaderSource', (a) => { a[0].__src = a[1]; });
	passthrough('attachShader', (a) => { (a[0].__shaders ||= []).push(a[1]); });
	timed('compileShader', (a, d) => { a[0].__compileMs = (a[0].__compileMs || 0) + d; });
	timed('getShaderParameter', (a, d) => { a[0].__compileMs = (a[0].__compileMs || 0) + d; });
	timed('linkProgram', (a, d) => {
		const prog = a[0];
		const shaders = prog.__shaders || [];
		const vs = shaders[0] && shaders[0].__src || '';
		const fs = shaders[1] && shaders[1].__src || '';
		const key = vs.length + ':' + fs.length + ':' + hash(vs + '\u0000' + fs);
		if (!sources.has(key)) sources.set(key, { vs, fs });
		const rec = {
			id: P.programs.length, phase: P.phase(), t: now(), key,
			compileMs: shaders.reduce((m, s) => m + (s.__compileMs || 0), 0),
			linkMs: d, statusMs: 0, bound: 0, draws: 0, firstDrawPhase: null,
		};
		prog.__rec = rec;
		P.programs.push(rec);
		frameProgs++;
	});
	timed('getProgramParameter', (a, d) => { if (a[0] && a[0].__rec) a[0].__rec.statusMs += d; });
	// Привязку Godot делает и сразу после линковки (слоты текстур) — «нужность» программы считаем по отрисовкам.
	passthrough('useProgram', (a) => {
		const rec = a[0] && a[0].__rec;
		if (rec) rec.bound++;
	});
	for (const name of ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced', 'drawRangeElements']) {
		if (!proto[name]) continue;
		const orig = proto[name];
		proto[name] = function (...a) {
			const prog = this.getParameter(this.CURRENT_PROGRAM);
			const rec = prog && prog.__rec;
			if (rec) {
				if (!rec.draws) rec.firstDrawPhase = P.phase();
				rec.draws++;
			}
			return orig.apply(this, a);
		};
	}

	function hash(s) {
		let h = 2166136261 >>> 0;
		for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619) >>> 0;
		return h.toString(16);
	}

	// Контекст: GPU (не SwiftShader/WARP — иначе цифры ни о чём), расширения.
	const getContext = HTMLCanvasElement.prototype.getContext;
	HTMLCanvasElement.prototype.getContext = function (type, ...rest) {
		const ctx = getContext.call(this, type, ...rest);
		if (ctx && type === 'webgl2' && !P.info.renderer) {
			const dbg = ctx.getExtension('WEBGL_debug_renderer_info');
			P.info = {
				renderer: dbg ? ctx.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : ctx.getParameter(ctx.RENDERER),
				vendor: dbg ? ctx.getParameter(dbg.UNMASKED_VENDOR_WEBGL) : ctx.getParameter(ctx.VENDOR),
				parallelCompile: !!ctx.getExtension('KHR_parallel_shader_compile'),
				extensions: ctx.getSupportedExtensions(),
				userAgent: navigator.userAgent,
				contextAt: now(),
			};
			console.log('[probe] webgl2: ' + P.info.renderer + ' | KHR_parallel_shader_compile=' + P.info.parallelCompile);
		}
		return ctx;
	};

	// Кадры: промежуток между кадрами и время самого кадра (в нём — блокирующий GL).
	const raf = window.requestAnimationFrame.bind(window);
	let lastStart = 0;
	window.requestAnimationFrame = (cb) => raf((ts) => {
		const s = performance.now();
		const gap = lastStart ? s - lastStart : 0;
		lastStart = s;
		cb(ts);
		const e = performance.now();
		P.frames.push({ t: s - t0, gap, js: e - s, gl: frameGl, progs: frameProgs, phase: P.phase() });
		frameGl = 0;
		frameProgs = 0;
	});

	try {
		new PerformanceObserver((list) => {
			for (const e of list.getEntries()) P.longtasks.push({ t: e.startTime - t0, ms: e.duration, phase: P.phase() });
		}).observe({ type: 'longtask', buffered: true });
	} catch (e) { /* нет longtask — не страшно */ }

	P.sources = () => Array.from(sources.values());
	P.sourcesFor = (keys) => keys.map((k) => ({ key: k, ...(sources.get(k) || {}) }));

	P.summary = () => {
		const byPhase = {};
		let neverBound = 0;
		let neverBoundMs = 0;
		let blocking = 0;
		for (const p of P.programs) {
			const ms = p.compileMs + p.linkMs + p.statusMs;
			blocking += ms;
			if (!p.draws) { neverBound++; neverBoundMs += ms; }
			const g = byPhase[p.phase] ||= { programs: 0, ms: 0, neverBound: 0 };
			g.programs++;
			g.ms += ms;
			if (!p.draws) g.neverBound++;
		}
		const marks = performance.getEntriesByType('mark').filter((m) => m.name.startsWith('ex:'))
			.map((m) => ({ name: m.name.slice(3), t: Math.round(m.startTime - t0) }));
		const res = {};
		for (const r of performance.getEntriesByType('resource')) {
			const name = r.name.split('/').pop().split('?')[0];
			if (/\.(wasm|pck|js)$/.test(name)) res[name] = { start: Math.round(r.startTime - t0), end: Math.round(r.responseEnd - t0), bytes: r.transferSize };
		}
		const slow = P.frames.filter((f) => f.gap > 50).map((f) => ({ t: Math.round(f.t), gap: Math.round(f.gap), js: Math.round(f.js), gl: Math.round(f.gl), progs: f.progs, phase: f.phase }));
		return {
			info: { renderer: P.info.renderer, vendor: P.info.vendor, parallelCompile: P.info.parallelCompile, userAgent: P.info.userAgent, contextAt: Math.round(P.info.contextAt || 0) },
			programs: P.programs.length, neverBound, neverBoundMs: Math.round(neverBoundMs), blockingMs: Math.round(blocking), uniqueSources: sources.size,
			byPhase, marks, resources: res, frames: P.frames.length, slowFrames: slow,
			longtasks: P.longtasks.map((l) => ({ t: Math.round(l.t), ms: Math.round(l.ms), phase: l.phase })),
		};
	};
})();
