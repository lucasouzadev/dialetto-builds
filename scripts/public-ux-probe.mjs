// Public-source-only responsive probe. Never checks out private code, authenticates,
// captures screenshots, emits DOM text, or uploads artifacts.
// Operates strictly on public login/signup routes served by the published website.
import { chromium } from 'playwright';

const ORIGIN = 'https://dialetto.club';
const routes = ['/login', '/signup'];
const widths = [320, 360, 375, 390, 428, 768, 1024, 1440, 1920];
const schemes = ['light', 'dark'];
const locales = ['pt-BR', 'en-US'];
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
let passes = 0;
let failures = 0;

try {
  for (const width of widths) for (const scheme of schemes) for (const locale of locales) {
    const context = await browser.newContext({
      viewport: { width, height: width < 600 ? 844 : 900 },
      colorScheme: scheme,
      locale,
      reducedMotion: 'reduce',
      isMobile: width < 600,
      hasTouch: width < 600,
    });
    const page = await context.newPage();
    for (const route of routes) {
      const reasons = [];
      try {
        const requested = new URL(route, ORIGIN);
        const response = await page.goto(requested.href, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await page.waitForTimeout(1200);
        const current = new URL(page.url());
        if (current.origin !== ORIGIN) reasons.push('unexpected cross-origin navigation');
        if (!response || response.status() >= 400) reasons.push('HTTP error');
        const metrics = await page.evaluate(() => {
          const width = window.innerWidth;
          const html = document.documentElement;
          const root = document.querySelector('#app');
          const contentReady = (root?.textContent ?? '').trim().length > 15;
          const inputs = Array.from(document.querySelectorAll('input'))
            .filter(el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el);
              return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
            });
          const interactive = Array.from(document.querySelectorAll('button, a, input, textarea, select, [role=button]'))
            .filter(el => {
              const box = el.getBoundingClientRect();
              const style = getComputedStyle(el);
              return box.width >= 8 && box.height >= 8 && box.top < innerHeight &&
                box.bottom > 0 && box.right > 0 && box.left < width &&
                style.display !== 'none' && style.visibility !== 'hidden';
            });
          const cut = interactive.some(el => {
            const box = el.getBoundingClientRect();
            return box.left < -3 || box.right > width + 3;
          });
          return {
            overflow: html.scrollWidth > width + 3,
            clippedControls: cut,
            contentReady, visibleInputs: inputs.length,
          };
        });
        if (metrics.overflow) reasons.push('horizontal overflow');
        if (metrics.clippedControls) reasons.push('clipped interactive control');
        if (!metrics.contentReady || metrics.visibleInputs === 0) reasons.push('login/signup form not visibly rendered');
      } catch (_) {
        // Never echo exception messages, URLs, HTML, user content or credentials into public logs.
        reasons.push('navigation/browser exception');
      }
      if (reasons.length) {
        failures++;
        console.error(`FAIL: ${route} ${width}px ${scheme} ${locale}: ${reasons.join(', ')}`);
      } else {
        passes++;
      }
    }
    await context.close();
  }
} finally {
  await browser.close();
}
console.log(`Source-free public UX probe: PASS=${passes} FAIL=${failures}`);
if (failures) process.exitCode = 1;
