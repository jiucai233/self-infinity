// Records the front page's three.js robot (web/landing3d) for a phone, one frame per
// 0.04 of the scroll, with where the orb is: app/assets/landing/phone/ (via webp).
//   cd app/web && python3 -m http.server 8765 &
//   node tool/record_robot_frames.js "http://127.0.0.1:8765/landing3d/index.html?p=0" OUT 390 844 2.5 0.04
// then convert OUT/f_NNN.png to robot_NNN.webp (quality 80) and copy track.json.
// Needs puppeteer-core and Google Chrome.
const puppeteer = require('puppeteer-core');
const fs = require('fs');
const [,, url, out, W, H, DPR, STEP] = process.argv;
(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: 'new',
    args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: +W, height: +H, deviceScaleFactor: +DPR });
  await page.evaluateOnNewDocument(() => {
    window.__orb = null;
    addEventListener('message', (e) => { if (e.data && e.data.type === 'orb') window.__orb = e.data; });
  });
  page.on('console', (m) => { if (m.type() === 'error') console.log('page:', m.text()); });
  await page.goto(url, { waitUntil: 'networkidle0', timeout: 120000 });
  await page.waitForFunction(() => document.documentElement.dataset.ready === 'true', { timeout: 120000 });
  const step = +STEP, orb = [];
  let i = 0;
  for (let p = 0; p <= 5 + 1e-9; p += step, i++) {
    const pp = Math.min(5, +p.toFixed(4));
    await page.evaluate((v) => postMessage({ source: 'self-infinity-page', p: v }, '*'), pp);
    await new Promise((r) => setTimeout(r, i === 0 ? 1500 : 450));
    const o = await page.evaluate(() => window.__orb);
    orb.push(o ? [o.x / +W, o.y / +H, o.r / +H] : null);
    await page.screenshot({ path: `${out}/f_${String(i).padStart(3, '0')}.png` });
  }
  fs.writeFileSync(`${out}/track.json`, JSON.stringify({ frames: i, aspect: +W / +H, step, orb }));
  console.log('frames', i);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
