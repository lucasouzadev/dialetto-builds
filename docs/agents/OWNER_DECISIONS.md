# OWNER_DECISIONS — dialetto-builds

Dated log of the owner's standing instructions (format: `docs/agents/standard/OWNER-DECISIONS-TEMPLATE.md`). Newest first; never delete, mark `SUPERSEDED`. The current one-line rule lives in `AGENTS.md`.

## 2026-11-08 — Canary per session, early compaction, security/performance skills (agent-kit 1.1.0)
Rule: the owner gives the form of address at the start of each session; agents use it in every reply, keep it only in the conversation, never store it. Auto-compaction at a 200k-token window (`autoCompactWindow`), statusline shows context use; handoff from 70 %. Security/performance skills: `security-core`, `identity-session`, `data-privacy`, `supply-chain`, `performance-core`, `platform-security` (CI repos: the security subset). Kit source: `lucasouzadev/agent-kit-skill`.

## 2026-11-08 — Agent docs standard
Rule: this repo follows agent-kit 1.0.0 (English agent docs, caveman replies in Portuguese, private-name canary in every chat reply, never stored in files).

## 2026-10-14 — Public-builds privacy boundary
Rule: only source-free, anonymous probes of already published pages run in public jobs. Private-source Playwright, RLS A/B, migrations, worker security and benchmarks stay off this repo; missing private evidence is `BLOCKED`. Source: private `docs/agents/QUALITY_GATES_2026-10-14.md`.

## 2026-10-07 — Builds, E2E and manual deploys move here
Rule: the private repo ran out of Actions quota; public repos spend no minutes. Build, E2E (Maestro), Supabase deploy, Worker deploy and OTA verify/redeploy live here, all `workflow_dispatch`, cloning the private repo with a read deploy key.

## 2026-10-05 — Native builds only on explicit order
Rule: never dispatch TestFlight/APK/iOS check builds on the agent's initiative; each build e-mails the owner and testers. OTA (merge to private `main`) is free.
