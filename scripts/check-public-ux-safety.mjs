// Contract check: public UX workflow must remain source-free and artifact-free.
// This is a tripwire, not a substitute for security review.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const wf = readFileSync(new URL('../.github/workflows/public-ux-quality.yml', import.meta.url), 'utf8');
const test = readFileSync(new URL('./public-ux-probe.mjs', import.meta.url), 'utf8');
for (const [name, pattern] of [
  ['secret reference', /secrets\./i],
  ['private checkout', /repository:\s*lucasouzadev\/dialetto|checkout-source/i],
  ['artifact publishing', /upload-artifact|gh\s+release|actions\/cache/i],
  ['dangerous PR trigger', /pull_request_target\s*:/i],
  ['secret test credentials', /E2E_(EMAIL|PASSWORD)|SUPABASE_SERVICE_ROLE/i],
]) {
  assert(!pattern.test(wf), 'Unsafe public UX workflow: ' + name);
}
for (const [name, pattern] of [
  ['screenshots or recordings', /\.screenshot\s*\(|recordVideo|\.video\s*\(/i],
  ['authenticated test traffic', /inputText\s*\(|\.fill\s*\(|Authorization|apikey/i],
  ['DOM content in output', /console\.(log|error)\s*\([^\n]*(innerHTML|textContent|outerHTML)/i],
]) {
  assert(!pattern.test(test), 'Unsafe public UX probe: ' + name);
}
assert(wf.includes('permissions:\n  contents: read'), 'Require least-privilege GITHUB_TOKEN');
assert(test.includes("const ORIGIN = 'https://dialetto.club'"), 'Public origin must be pinned');
console.log('PASS: source-free public QA privacy guardrails');
