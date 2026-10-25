// Logged-in responsive probe for the QA account (sub-project 46, Task 8b).
// Reads QA_EMAIL / QA_PASSWORD from the environment ONLY in the login step.
// Never captures screenshots, video or traces, never prints DOM text, URLs with
// query strings or exception messages: the repository is public, so the log is too.
import { chromium } from 'playwright';

const ORIGIN = 'https://dialetto.club';
const email = process.env.QA_EMAIL;
const password = process.env.QA_PASSWORD;
if (!email || !password) {
  console.error('SKIP: QA_EMAIL/QA_PASSWORD are not configured as repository secrets.');
  process.exit(0);
}

const routes = ['/library', '/pastas', '/faixas', '/profile', '/notificacoes'];
// Phones (portrait + sideways), tablet, laptop, desktop.
const viewports = [
  { w: 320, h: 568, touch: true }, { w: 390, h: 844, touch: true },
  { w: 844, h: 390, touch: true }, { w: 768, h: 1024, touch: true },
  { w: 1280, h: 800 }, { w: 1920, h: 1080 },
];
const MIN_TARGET = 40; // px; the hit-area utilities reach ~44.

const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
let passes = 0;
let failures = 0;
let pageErrors = 0;

try {
  for (const vp of viewports) {
    const context = await browser.newContext({
      viewport: { width: vp.w, height: vp.h },
      locale: 'pt-BR',
      reducedMotion: 'reduce',
      isMobile: Boolean(vp.touch) && vp.w < 900,
      hasTouch: Boolean(vp.touch),
    });
    const page = await context.newPage();
    page.on('pageerror', () => { pageErrors++; });

    let loggedIn = false;
    try {
      await page.goto(`${ORIGIN}/login`, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.locator('input:not([type="password"])').first().fill(email);
      await page.locator('input[type="password"]').first().fill(password);
      await page.locator('input[type="password"]').first().press('Enter');
      await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 });
      loggedIn = true;
    } catch (_) {
      // Never echo the exception: it can carry the typed value.
    }
    if (!loggedIn) {
      failures++;
      console.error(`FAIL: login ${vp.w}x${vp.h}: could not sign in`);
      await context.close();
      continue;
    }

    for (const route of routes) {
      const reasons = [];
      const warnings = [];
      try {
        await page.goto(`${ORIGIN}${route}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await page.waitForTimeout(2500);
        const m = await page.evaluate((min) => {
          const html = document.documentElement;
          const visible = Array.from(document.querySelectorAll('button, a, input, [role=button]'))
            .filter((el) => {
              const b = el.getBoundingClientRect();
              const s = getComputedStyle(el);
              return b.width >= 8 && b.height >= 8 && b.top < innerHeight && b.bottom > 0 &&
                s.display !== 'none' && s.visibility !== 'hidden';
            });
          return {
            overflow: html.scrollWidth > innerWidth + 3,
            // Controls inside a horizontal scroller (tab carousels) are meant to
            // sit past the edge, so they are not "clipped".
            clipped: visible.some((el) => {
              const b = el.getBoundingClientRect();
              if (b.left >= -3 && b.right <= innerWidth + 3) return false;
              for (let n = el.parentElement; n; n = n.parentElement) {
                const o = getComputedStyle(n).overflowX;
                if ((o === 'auto' || o === 'scroll') && n.scrollWidth > n.clientWidth) return false;
              }
              return true;
            }),
            // Buttons only: inline text links legitimately sit below 40px.
            small: visible.filter((el) => el.tagName === 'BUTTON').filter((el) => {
              const b = el.getBoundingClientRect();
              return Math.max(b.width, b.height) < min;
            }).length,
            ready: (document.body.textContent ?? '').trim().length > 15,
          };
        }, MIN_TARGET);
        if (new URL(page.url()).pathname.startsWith('/login')) reasons.push('bounced to login');
        if (!m.ready) reasons.push('page not visibly rendered');
        if (m.overflow) reasons.push('horizontal overflow');
        if (m.clipped) reasons.push('clipped interactive control');
        if (vp.touch && m.small > 0) warnings.push(`${m.small} button(s) under ${MIN_TARGET}px`);
      } catch (_) {
        reasons.push('navigation/browser exception');
      }
      // Small targets are reported, not failed: they are a backlog to burn down,
      // and a daily red run nobody can act on teaches people to ignore the check.
      if (warnings.length) console.warn(`WARN: ${route} ${vp.w}x${vp.h}: ${warnings.join(', ')}`);
      if (reasons.length) {
        failures++;
        console.error(`FAIL: ${route} ${vp.w}x${vp.h}: ${reasons.join(', ')}`);
      } else {
        passes++;
      }
    }
    await context.close();
  }
} finally {
  await browser.close();
}
console.log(`Logged-in UX probe: PASS=${passes} FAIL=${failures} PAGE_ERRORS=${pageErrors}`);
if (failures || pageErrors) process.exitCode = 1;
