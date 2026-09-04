# Phase E — DDoS / Abuse Hardening

## Goal

Protect Story Relay without exposing the user's other GitHub Pages sites to Story Relay traffic risk.

Target architecture:

`GitHub = source control`  
`Cloudflare Workers = public Story Relay frontend`  
`Supabase = authenticated backend/data plane`

---

## E1 — Move Story Relay frontend off GitHub Pages

**狀態：PASS（2026-09-04）。**

### Repository preparation

- Add `pnpm run build:cloudflare` in `story-relay/package.json`.
- Cloudflare build uses root base `/`, not the former GitHub Pages subpath.
- Static output directory is `dist/public` relative to `story-relay`.
- Supabase URL and publishable key remain build-time environment variables. Never place service-role credentials in Cloudflare or the browser bundle.
- `story-relay/wrangler.jsonc` defines Worker name `story-relay` and compatibility date for deterministic connected deployments.

### Cloudflare connected build settings

- Repository: `wu33000-design/collaborative-storytelling`
- Production branch: `main`
- Root directory: `/story-relay`
- Build command: `pnpm install --frozen-lockfile && pnpm run build:cloudflare`
- Deploy command: `npx wrangler deploy --assets ./dist/public`
- Required build-time environment variables:
  - `VITE_SUPABASE_URL`
  - `VITE_SUPABASE_PUBLISHABLE_KEY`

### E1 acceptance

**結果：PASS。** Production URL: `https://story-relay.wu33000.workers.dev`

Verified on 2026-09-04:

1. Cloudflare connected build and deploy succeed.
2. Root page loads from the Cloudflare Workers hostname.
3. Google OAuth login succeeds and returns to the Cloudflare hostname after Supabase Site URL / Redirect URLs were updated.
4. Existing session/auth gate works.
5. Host created activity `SR-798715` from the Cloudflare deployment.
6. User joined `SR-798715` directly from the home-page activity-code form and entered StoryRoom.
7. Relay flow smoke passed: current-writer state appeared, the 30-second round countdown appeared, segment submission succeeded, and the next round loaded.
8. Core authenticated Supabase RPC/data path works from the Cloudflare deployment.
9. This repository's GitHub Pages site was manually unpublished.
10. The obsolete `.github/workflows/deploy-pages.yml` workflow was removed so future pushes cannot automatically re-enable this repository's Pages deployment.
11. No Pages configuration for any other repository was changed.

---

## E2 — Cloudflare edge protection

**狀態：PASS for current free `workers.dev` architecture（2026-09-04）。**

Current policy:

- Cloudflare Workers is the public frontend edge; GitHub Pages is no longer a Story Relay frontend origin.
- Keep Cloudflare's automatic DDoS mitigation as the network edge protection.
- Continue using the free `workers.dev` hostname; no custom domain is required for the current classroom MVP.
- Do not add aggressive IP-based limits that could block a legitimate classroom burst where many users share a school/network egress IP.
- Do not add Cloudflare Access because the classroom application already has its own authentication and students should not face an extra access gate.
- Add custom WAF/rate-limit rules only if later operational evidence shows a concrete need and a custom domain/zone configuration makes those controls appropriate.

### E2 acceptance

- Normal classroom smoke flow works through Cloudflare.
- Static frontend requests are served by Cloudflare, not GitHub Pages.
- No public Story Relay GitHub Pages fallback remains after cutover.
- Other GitHub repository Pages sites were not modified.

---

## E3 — Supabase application-layer abuse protection

**狀態：PASS（2026-09-04）。**

Cloudflare protecting the frontend does not protect Supabase from clients that call the Supabase endpoint directly. Lightweight server-side limits were therefore added around the main mutation RPCs.

Migration:

`story-relay/supabase/migrations/20260904_e3_rpc_abuse_rate_limits.sql`

Rollback-only test:

`story-relay/supabase/tests/classroom100_phase_e3_rpc_abuse_rate_limits.sql`

### Implemented limits

Rate-limit buckets are keyed by authenticated user and action, not by browser-provided IP or a classroom-wide counter:

- `join_activity_by_code`: 20 calls / 60 seconds / user
- `start_relay_round`: 20 calls / 60 seconds / user
- `submit_segment`: 8 calls / 60 seconds / user
- `nominate_candidate`: 60 calls / 60 seconds / user
- `volunteer_for_round`: 20 calls / 60 seconds / user

The pre-existing RPC implementations are preserved as internal unthrottled functions. Direct execution of those internal implementations and the rate-limit bucket helper is revoked from `authenticated`; browser clients can only call the public throttled wrappers.

This design keeps the limit independent for each logged-in participant, so legitimate simultaneous use by roughly 100 classroom users does not consume one shared quota.

### E3 acceptance

**結果：PASS。** Supabase SQL Editor returned:

`CLASSROOM_100 E3 RPC abuse rate limits passed`

Verified by the rollback-only test:

- the configured threshold permits valid calls up to the cap and blocks the next call;
- blocked calls return a clear `Too many requests` error;
- durable bucket state does not exceed the configured cap;
- separate authenticated users receive independent buckets;
- authenticated clients cannot bypass the wrapper through the internal implementation;
- authenticated clients cannot directly mutate rate-limit buckets;
- the test rolls back all fixture data.

---

## Phase E result

**Phase E is complete for the current ~100-person classroom MVP.**

Final public architecture:

`GitHub repository` → source control / Cloudflare connected builds  
`Cloudflare Workers (workers.dev)` → public frontend + automatic edge DDoS mitigation  
`Supabase Auth/PostgreSQL/RLS/RPC/Realtime` → authenticated backend with application-layer RPC throttling

## Scope boundary

This phase is abuse hardening for the current ~100-person classroom product. It intentionally does not add enterprise DDoS appliances, dedicated API gateways, Redis, SIEM, multi-region failover, purchased custom domains, or synthetic flood testing unless real operational evidence later justifies them.
