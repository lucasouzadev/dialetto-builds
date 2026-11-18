// Seeds the E2E test account with ONE neutral track, the same way the app uploads one
// (frontend/src/api/media.ts uploadTrack): rows first, then the file, whose arrival fires
// the worker's transcode. Idempotent: does nothing when the track already exists.
// Fixture: synthetic speech (espeak-ng, invented neutral text, spoken intro), see
// docs/qa/2026-11-18-lyrics-calibration.md in the private repo.
// Env: E2E_EMAIL, E2E_PASSWORD. Prints no token, e-mail or id.
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

const URL_ = 'https://ohcgrtaultutxmcpoicl.supabase.co';
const KEY = 'sb_publishable_y8X6t-Es_w8D5d4a6qy84g_fP5ClLKp'; // public key, same as the app build
const here = new URL('./fixtures/', import.meta.url);

const { E2E_EMAIL: email, E2E_PASSWORD: password } = process.env;
if (!email || !password) { console.log('seed: no account, skipped'); process.exit(0); }

const call = async (path, init = {}, token) => {
  const res = await fetch(`${URL_}${path}`, { ...init, headers: { apikey: KEY, ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(init.headers ?? {}) } });
  const text = await res.text();
  if (!res.ok) throw new Error(`seed: ${init.method ?? 'GET'} ${path.split('?')[0]} -> ${res.status}`);
  return text ? JSON.parse(text) : null;
};
const json = (body, extra = {}) => ({ body: JSON.stringify(body), headers: { 'Content-Type': 'application/json', ...extra } });

const session = await call('/auth/v1/token?grant_type=password', { method: 'POST', ...json({ email, password }) });
const token = session.access_token;
const uid = session.user.id;
const meta = JSON.parse(await readFile(new URL('qa-e2e-letra.json', here), 'utf8'));

const existing = await call(`/rest/v1/tracks?select=id&user_id=eq.${uid}&title=eq.${encodeURIComponent(meta.title)}`, {}, token);
if (existing.length > 0) { console.log('seed: track already there, skipped'); process.exit(0); }

const audio = await readFile(new URL('qa-e2e-letra.m4a', here));
const storagePath = `${uid}/${randomUUID()}.m4a`;
const ret = { Prefer: 'return=representation' };
const [track] = await call('/rest/v1/tracks', { method: 'POST', ...json({ user_id: uid, project_id: null, title: meta.title }, ret) }, token);
try {
  const [version] = await call('/rest/v1/track_versions', { method: 'POST', ...json({ track_id: track.id, version_name: 'v1' }, ret) }, token);
  await call('/rest/v1/track_files', { method: 'POST', ...json({ version_id: version.id, quality: 'source', storage_path: storagePath, file_size: audio.length, format: 'm4a', transcoding_status: 'pending' }) }, token);
  await call(`/rest/v1/tracks?id=eq.${track.id}`, { method: 'PATCH', ...json({ active_version_id: version.id }) }, token);
  await call(`/storage/v1/object/audio/${storagePath}`, { method: 'POST', body: audio, headers: { 'Content-Type': 'audio/mp4', 'x-upsert': 'false' } }, token);
} catch (error) {
  await call(`/rest/v1/tracks?id=eq.${track.id}`, { method: 'DELETE' }, token).catch(() => {});
  throw error;
}
await call('/rest/v1/track_lyrics', { method: 'POST', ...json({ track_id: track.id, lines: meta.lines, enabled: true, language: meta.language }) }, token);
// Wait for the worker's transcode (best effort: the flows only need the lyric).
for (let i = 0; i < 24; i++) {
  const files = await call(`/rest/v1/track_files?select=transcoding_status&storage_path=eq.${encodeURIComponent(storagePath)}`, {}, token);
  const status = files[0]?.transcoding_status;
  if (status === 'completed' || status === 'failed') { console.log(`seed: track created, transcode ${status}`); process.exit(0); }
  await new Promise((r) => setTimeout(r, 5000));
}
console.log('seed: track created, transcode still pending');
