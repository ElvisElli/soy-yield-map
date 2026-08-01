// Capture two screenshots of the running Shiny app with different inputs.
// Usage: node docs/capture-two.js <baseUrl>
const { chromium } = require('playwright');

(async () => {
  const url = process.argv[2] || 'http://127.0.0.1:8412/';
  const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
  const browser = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
    args: ['--ignore-certificate-errors'],
    proxy: proxy ? { server: proxy, bypass: 'localhost,127.0.0.1' } : undefined,
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForSelector('.shiny-plot-output img', { timeout: 30000 });
  await page.waitForTimeout(4500);
  await page.screenshot({ path: 'docs/shot-1-default.png' });
  console.log('shot-1-default.png');

  // Setter that fires the events Shiny listens for
  async function setNumeric(id, val) {
    await page.fill(`#${id}`, String(val));
    await page.dispatchEvent(`#${id}`, 'change');
  }
  // Different field (NE Delta), a low reported yield (big gap), kg/ha units
  await setNumeric('lat', 35.6);
  await setNumeric('lon', -90.3);
  await setNumeric('myyield', 2600);
  await page.check('input[name="unit"][value="kg/ha"]');
  await page.waitForTimeout(4500);
  await page.screenshot({ path: 'docs/shot-2-alt.png' });
  console.log('shot-2-alt.png');

  await browser.close();
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
