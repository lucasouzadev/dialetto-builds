// Tripwire: the logged-in workflow must stay artifact-free and secret-safe,
// because this repository (and therefore its logs) is public.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const wf = readFileSync(new URL('../.github/workflows/logged-in-ux-quality.yml', import.meta.url), 'utf8');
const probe = readFileSync(new URL('./logged-in-ux-probe.mjs', import.meta.url), 'utf8');
for (const [name, pattern] of [
  ['artifact publishing', /upload-artifact|gh\s+release|actions\/cache/i],
  ['dangerous PR trigger', /pull_request(_target)?\s*:/i],
  ['private checkout', /repository:\s*lucasouzadev\/dialetto\b|checkout-source/i],
  ['service role key', /SUPABASE_SERVICE_ROLE/i],
  ['literal credentials', /admin@admin|12345678/i],
]) assert(!pattern.test(wf + probe), 'Unsafe logged-in UX workflow: ' + name);
for (const [name, pattern] of [
  ['screenshots, video or trace', /\.screenshot\s*\(|recordVideo|\.video\s*\(|tracing\./i],
  ['DOM content in output', /console\.(log|error)\s*\([^\n]*(innerHTML|textContent|outerHTML)/i],
  ['exception text in output', /console\.(log|error)\s*\([^\n]*\b(e|err|error)\.(message|stack)/i],
]) assert(!pattern.test(probe), 'Unsafe logged-in UX probe: ' + name);
assert(wf.includes('permissions:\n  contents: read'), 'Require least-privilege GITHUB_TOKEN');
assert(wf.includes('secrets.QA_EMAIL') && wf.includes('secrets.QA_PASSWORD'), 'Credentials must come from secrets');
console.log('PASS: logged-in QA privacy guardrails');
