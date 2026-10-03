// Render an animated demo: frames of player.html in headless Chrome, the
// narration laid end to end, sound effects on the cues, an optional music bed
// ducked under the voice, all joined by ffmpeg (Docker image when not installed).
//
//   node render.mjs DIR [-o demo.mp4] [--only FROM-TO] [--fps 30]   (--only writes preview.mp4)
//
// The source is DIR/steps.json (optional), DIR/scenes/*.svg, DIR/shots/NN.*
// and DIR/audio/NN.{txt,mp3,words.json}. Frames are computed from time alone
// and sounds are synthesised with fixed seeds, so unchanged sources render
// the same video every time.
import { chromium } from 'playwright-core';
import { existsSync, readFileSync, readdirSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, basename } from 'node:path';
import { availableParallelism } from 'node:os';

const here = dirname(new URL(import.meta.url).pathname);
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const die = m => { console.error(`rec-animate: ${m}`); process.exit(1); };
const dir = resolve(argv.find((a, i) => !a.startsWith('-') && !['-o', '--only', '--fps'].includes(argv[i - 1])) || '.');
const out = opt('-o', opt('--only') ? 'preview.mp4' : 'demo.mp4');
if (out.includes('/') || out.startsWith('.')) die('-o takes a file name inside the demo folder');
const FPS = +opt('--fps', 30), TAIL = 0.8;

// ---- the spec: steps.json, or every narrated step as a plain screenshot ----
const file = `${dir}/steps.json`;
let spec = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
if (Array.isArray(spec)) spec = { steps: spec };
if (!spec.steps) spec.steps = readdirSync(`${dir}/audio`).filter(f => /^\d{2,3}\.txt$/.test(f)).sort()
  .map(f => ({ n: basename(f, '.txt') }));
if (!spec.steps.length) die(`no steps: write ${file} or narrate with rec-step`);
spec = { width: 1600, height: 900, capH: 100, captions: true, progress: true, sfx: true, music: null,
         musicVolume: 0.12, sfxVolume: 0.5, accent: '#2563eb', highlight: '#f59e0b', ...spec };

let off = 0;
for (const s of spec.steps) {
  s.n = String(s.n).padStart(2, '0');
  const a = `${dir}/audio/${s.n}`;
  if (!existsSync(`${a}.mp3`)) die(`step ${s.n}: no audio/${s.n}.mp3 (narrate it with rec-step)`);
  if (!existsSync(`${a}.words.json`)) die(`step ${s.n}: no audio/${s.n}.words.json (narrate it again with rec-step)`);
  s.words = JSON.parse(readFileSync(`${a}.words.json`, 'utf8'));
  s.text = readFileSync(`${a}.txt`, 'utf8').trim();
  s.kind ||= s.title ? 'title' : s.svg ? 'scene' : 'shot';
  if (s.kind === 'scene') s.svgText = readFileSync(`${dir}/${s.svg}`, 'utf8');
  if (s.kind === 'shot') {
    s.img ||= [`shots/${s.n}.png`, `shots/${s.n}.jpg`].find(p => existsSync(`${dir}/${p}`));
    if (!s.img || !existsSync(`${dir}/${s.img}`)) die(`step ${s.n}: no screenshot shots/${s.n}.jpg or .png`);
    s.imgUrl = `file://${dir}/${s.img}`;
  }
  if (s.chapter && !s.chapterNo) s.chapterNo = s.n;
  s.dur = (s.words.at(-1)?.end ?? 1) + (s.hold ?? TAIL);
  s.off = off; off += s.dur;
}
spec.total = off;
const [from, to] = opt('--only', `0-${off}`).split('-').map(Number);

// ---- frames ----
const chrome = [process.env.REC_CHROME, '/usr/bin/google-chrome', '/opt/google/chrome/chrome',
  '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].find(p => p && existsSync(p));
const seg = `${dir}/seg`, frames = `${seg}/frames`;
rmSync(frames, { recursive: true, force: true }); mkdirSync(frames, { recursive: true });
const list = [];
for (let f = Math.round(from * FPS); f < Math.min(to, off) * FPS; f++) list.push(f);

const browser = await chromium.launch(chrome ? { executablePath: chrome } : {});
const workers = Math.max(1, Math.min(8, availableParallelism() - 1));
const t0 = Date.now();
let events = [];
await Promise.all([...Array(workers).keys()].map(async w => {
  const page = await browser.newPage({ viewport: { width: spec.width, height: spec.height } });
  let err = null; page.on('pageerror', e => { err = e; });
  await page.goto(`file://${here}/player.html`);
  try {
    const ev = await page.evaluate(sp => init(sp), JSON.parse(JSON.stringify(spec)));
    if (w === 0) events = ev;
  } catch (e) { die(String(e.message).split('\n')[0].replace(/^.*Error: /, '')); }
  for (let i = w; i < list.length; i += workers) {
    await page.evaluate(T => seek(T), list[i] / FPS);
    if (err) die(`page error: ${err.message}`);
    await page.screenshot({ path: `${frames}/${String(i).padStart(5, '0')}.jpg`, type: 'jpeg', quality: 92 });
  }
}));
await browser.close();
console.error(`rec-animate: ${list.length} frames in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

// ---- sound: effects and the music bed, synthesised with fixed seeds ----
const SFX = {
  whoosh: 'anoisesrc=d=0.7:c=pink:a=0.7:seed=7,bandpass=f=900:w=1400,afade=t=in:d=0.45:curve=exp,afade=t=out:st=0.45:d=0.25',
  rise:   'anoisesrc=d=1.4:c=pink:a=0.5:seed=3,highpass=f=500,afade=t=in:d=1.1:curve=exp,afade=t=out:st=1.1:d=0.3',
  click:  "aevalsrc='0.9*exp(-t*400)*sin(2*PI*2200*t)+0.5*exp(-t*250)*sin(2*PI*900*t)':d=0.08",
  tick:   "aevalsrc='0.35*exp(-t*90)*sin(2*PI*1320*t)':d=0.15",
  pop:    "aevalsrc='0.5*exp(-t*35)*sin(2*PI*(520+500*t)*t)':d=0.22",
};
const PAD = `aevalsrc='0.10*(sin(2*PI*110*t)+0.6*sin(2*PI*164.81*t)+0.45*sin(2*PI*220*t)+0.3*sin(2*PI*277.18*t+sin(2*PI*0.07*t)))*(0.8+0.2*sin(2*PI*0.11*t))':d=${off.toFixed(2)},lowpass=f=900`;
const image = process.env.REC_FFMPEG_IMAGE || 'jrottenberg/ffmpeg:6.1-alpine';
let local = true;
try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' }); } catch { local = false; }
const ffmpeg = args => {
  const base = ['-hide_banner', '-loglevel', 'error', '-y', ...args];
  if (local) execFileSync('ffmpeg', base, { cwd: dir, stdio: 'inherit' });
  else execFileSync('docker', ['run', '--rm', '-u', `${process.getuid()}:${process.getgid()}`, '-v', `${dir}:${dir}`, '-w', dir,
    image, ...base], { stdio: 'inherit' });
};

const used = spec.sfx ? [...new Set(events.map(e => e.type))] : [];
mkdirSync(`${seg}/sfx`, { recursive: true });
for (const k of used) ffmpeg(['-f', 'lavfi', '-i', SFX[k], '-ar', '44100', '-ac', '1', `seg/sfx/${k}.wav`]);
let music = null;
if (spec.music === 'pad') { ffmpeg(['-f', 'lavfi', '-i', PAD, '-ar', '44100', '-ac', '1', 'seg/sfx/pad.wav']); music = 'seg/sfx/pad.wav'; }
else if (spec.music) { if (!existsSync(`${dir}/${spec.music}`)) die(`music file ${spec.music} not found`); music = spec.music; }

const ins = ['-framerate', String(FPS), '-i', 'seg/frames/%05d.jpg'];
const g = [];
spec.steps.forEach((s, k) => {
  ins.push('-i', `audio/${s.n}.mp3`);
  g.push(`[${k + 1}:a]aresample=44100,aformat=channel_layouts=mono,apad,atrim=end=${s.dur.toFixed(3)},asetpts=N/SR/TB[n${k}]`);
});
g.push(spec.steps.map((_, k) => `[n${k}]`).join('') + `concat=n=${spec.steps.length}:v=0:a=1[nar]`);
let idx = spec.steps.length + 1;
const mix = [];
if (used.length) {
  const fx = [];
  for (const k of used) {
    const at = events.filter(e => e.type === k);
    ins.push('-i', `seg/sfx/${k}.wav`);
    g.push(`[${idx}:a]asplit=${at.length}` + at.map((_, j) => `[${k}${j}]`).join(''));
    at.forEach((e, j) => { g.push(`[${k}${j}]adelay=${Math.round(e.t * 1000)}:all=1[${k}d${j}]`); fx.push(`[${k}d${j}]`); });
    idx++;
  }
  g.push(`${fx.join('')}amix=inputs=${fx.length}:normalize=0,volume=${spec.sfxVolume}[fx]`);
  mix.push('[fx]');
}
if (music) {
  ins.push('-stream_loop', '-1', '-i', music);
  g.push(`[${idx}:a]aresample=44100,aformat=channel_layouts=mono,atrim=end=${off.toFixed(3)},volume=${spec.musicVolume},` +
         `afade=t=in:d=1.5,afade=t=out:st=${Math.max(0, off - 2).toFixed(3)}:d=2[mus]`);
  g.push('[nar]asplit=2[nar][key]');
  g.push('[mus][key]sidechaincompress=threshold=0.02:ratio=6:attack=30:release=600[bed]');
  mix.push('[bed]');
  idx++;
}
g.push(`[nar]${mix.join('')}amix=inputs=${1 + mix.length}:normalize=0:duration=first,alimiter=limit=0.95,atrim=start=${from},asetpts=N/SR/TB[a]`);

ffmpeg([...ins, '-filter_complex', g.join(';'), '-map', '0:v', '-map', '[a]',
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-threads', '4',
  '-c:a', 'aac', '-b:a', '160k', '-shortest', out]);
rmSync(frames, { recursive: true, force: true });

// Subtitles too, one cue per step, as rec-build writes them.
const ts = x => new Date(Math.max(0, x) * 1000).toISOString().slice(11, 23).replace('.', ',');
writeFileSync(`${dir}/${out.replace(/\.mp4$/, '')}.srt`, spec.steps.map((s, k) =>
  `${k + 1}\n${ts(s.off)} --> ${ts(s.off + s.dur)}\n${s.text}\n`).join('\n'));
writeFileSync(`${seg}/timeline.json`, JSON.stringify({ total: off, steps: spec.steps.map(({ n, kind, off, dur }) => ({ n, kind, off, dur })), events }, null, 1));
console.log(`${dir}/${out}`);
