// Captures a screenshot of the running Shiny app for the README.
// Usage: node docs/capture-screenshot.js <url> <out.png>
// The Shiny app must already be running at <url>.
const { chromium } = require('playwright');

(async () => {
  const url = process.argv[2] || 'http://127.0.0.1:7391/';
  const out = process.argv[3] || 'docs/screenshot.png';
  const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;

  const browser = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
    args: ['--ignore-certificate-errors'],
    proxy: proxy ? { server: proxy, bypass: 'localhost,127.0.0.1' } : undefined,
  });
  const page = await browser.newPage({
    viewport: { width: 1280, height: 900 },
    ignoreHTTPSErrors: true,
  });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  // Wait for the Shiny plot images (boxplot + map) to render
  await page.waitForSelector('.shiny-plot-output img', { timeout: 30000 });
  await page.waitForTimeout(4000);
  await page.screenshot({ path: out, fullPage: false });
  console.log('screenshot saved to', out);
  await browser.close();
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
