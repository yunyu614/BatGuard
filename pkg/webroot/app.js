// BatGuard WebUI v0.2
const $ = (id) => document.getElementById(id);
const C = 327;

document.querySelectorAll('.tab').forEach((b) => {
  b.onclick = () => {
    document.querySelectorAll('.tab').forEach((x) => x.classList.remove('active'));
    document.querySelectorAll('.page').forEach((x) => x.classList.remove('active'));
    b.classList.add('active');
    $(b.dataset.t).classList.add('active');
    if (b.dataset.t === 'history') drawHistory();
  };
});

async function jget(f) {
  try { const r = await fetch(f + '?t=' + Date.now()); return await r.json(); }
  catch (e) { return null; }
}
async function tget(f) {
  try { const r = await fetch(f + '?t=' + Date.now()); return await r.text(); }
  catch (e) { return ''; }
}

function ring(pct) {
  const v = Math.max(0, Math.min(100, pct || 0));
  const el = $('ringFill');
  el.style.strokeDashoffset = C - (C * v) / 100;
  el.style.stroke = v >= 80 ? 'var(--warn)' : v <= 20 ? 'var(--bad)' : 'var(--accent)';
}

const ST = { Charging: '充电中', Discharging: '放电中', Full: '已充满', 'Not charging': '已停充', Unknown: '未知' };

function renderDetect(d) {
  const box = $('detect');
  if (!d || !d.items || !d.items.length) { box.textContent = '还没有探测结果'; return; }
  box.innerHTML = d.items.map((i) => {
    const cls = i.result === 'ok' ? 'ok' : 'bad';
    const txt = i.result === 'ok' ? '可用' : i.result === 'node_only' ? '可写但状态未变' : '不可写';
    return `<span class="${cls}">${i.result === 'ok' ? '✔' : '✘'}</span> ${i.name} — ${txt}`;
  }).join('<br>');
}

async function loadStatus() {
  const d = await jget('data.json');
  if (!d) { $('sub').textContent = '暂无数据（守护未运行）'; return; }
  $('cap').textContent = d.cap; ring(d.cap);
  $('w').textContent = d.w;
  $('status').textContent = ST[d.status] || d.status;
  $('a').textContent = d.a; $('v').textContent = d.v;
  $('peak').textContent = d.peak_w;
  $('temp').textContent = d.temp; $('ctemp').textContent = d.charger_temp;
  $('health').textContent = d.health; $('capmAh').textContent = d.cf; $('cycles').textContent = d.cycles;
  $('thermal').textContent = d.thermal === -1 ? '默认' : d.thermal;
  $('limit').textContent = d.limit; $('resume').textContent = d.resume;
  $('method').textContent = d.method || '未探测';
  $('mnode').textContent = d.method_node || '--';
  $('totalMah').textContent = (d.total_mah || 0) + ' mAh';
  $('sessions').textContent = (d.sessions || 0) + ' 次';
  $('time').textContent = d.time;
  $('sub').textContent = `设计 ${d.cfd}mAh · 均功率 ${d.avg_w}W · 上限 ${d.limit}%`;
  renderDetect(d.detect);
  if (!touched) {
    $('inLimit').value = d.limit; $('inResume').value = d.resume;
    $('inThermal').value = d.thermal; $('inEnabled').checked = !!d.enabled;
  }
}

function line(points, w, h, color) {
  if (!points.length) return '';
  const max = Math.max(...points), min = Math.min(...points), span = max - min || 1;
  const d = points.map((v, i) => {
    const x = (i / Math.max(1, points.length - 1)) * w;
    const y = h - ((v - min) / span) * (h - 10) - 5;
    return `${i ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)}`;
  }).join('');
  return `<path d="${d}" fill="none" stroke="${color}" stroke-width="2"/>`;
}

async function drawHistory() {
  const box = $('charts');
  const txt = await tget('samples.jsonl');
  const rows = txt.trim().split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean);
  if (!rows.length) { box.textContent = '暂无采样数据'; return; }
  const W = 320, H = 82;
  box.innerHTML = `
    <div class="caph">电量 %</div>
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${line(rows.map(r => r.cap), W, H, '#4ade80')}</svg>
    <div class="caph">功率 W</div>
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${line(rows.map(r => +r.w || 0), W, H, '#60a5fa')}</svg>
    <div class="caph">温度 °C</div>
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${line(rows.map(r => +r.temp || 0), W, H, '#f59e0b')}</svg>`;
  const s = await tget('sessions.jsonl');
  const ss = s.trim().split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean).reverse().slice(0, 12);
  if (ss.length) {
    $('sessList').innerHTML = ss.map((x) =>
      `<div class="row"><span>${x.from}% → ${x.to}%</span><b>${x.min}分 · ${x.mah}mAh · 峰${x.peak_w}W</b></div>`).join('');
  }
}

let touched = false;
['inLimit', 'inResume', 'inSample', 'inThermal', 'inEnabled'].forEach((id) => {
  const el = $(id);
  el.addEventListener('input', () => { touched = true; });
  el.addEventListener('change', () => { touched = true; });
});

function sh(cmd) {
  const k = window.ksu || window.Ksu;
  if (!k || !k.exec) return Promise.resolve(false);
  return new Promise((res) => { try { k.exec(cmd, '{}', () => res(true)); } catch (e) { res(false); } });
}
const CFG = '/data/adb/modules/BatGuard/config/config.conf';

$('save').onclick = async () => {
  const lim = +$('inLimit').value, res = +$('inResume').value,
        th = +$('inThermal').value, sp = +$('inSample').value;
  if (!(lim >= 40 && lim <= 100)) return ($('saveHint').textContent = '上限需 40–100');
  if (res >= lim) return ($('saveHint').textContent = '回落阈值必须小于上限');
  if (th < -1 || th > 10) return ($('saveHint').textContent = '温控档位 -1~10');
  const cmd = [
    `sed -i "s|^limit=.*|limit=${lim}|" ${CFG}`,
    `sed -i "s|^resume=.*|resume=${res}|" ${CFG}`,
    `sed -i "s|^thermal_level=.*|thermal_level=${th}|" ${CFG}`,
    `sed -i "s|^sample_charging=.*|sample_charging=${sp}|" ${CFG}`,
    `sed -i "s|^enabled=.*|enabled=${$('inEnabled').checked ? 1 : 0}|" ${CFG}`,
  ].join('; ');
  const ok = await sh(cmd);
  $('saveHint').textContent = ok ? '已保存，守护下一轮生效' : '当前环境不支持写配置，请用终端改 config.conf';
  if (ok) { touched = false; setTimeout(loadStatus, 1500); }
};

$('probe').onclick = async () => {
  $('detect').textContent = '探测中…（每个方法停充 4 秒后自动恢复）';
  const ok = await sh('pkill -f BatGuard/bin/daemon.sh; sleep 1; nohup /system/bin/sh /data/adb/modules/BatGuard/bin/daemon.sh >/dev/null 2>&1 &');
  setTimeout(loadStatus, 3000);
};

loadStatus();
setInterval(loadStatus, 15000);
