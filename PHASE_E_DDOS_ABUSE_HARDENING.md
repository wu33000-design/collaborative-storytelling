# Phase E — DDoS / Abuse Hardening

## Goal

Protect Story Relay without exposing the user's other GitHub Pages sites to Story Relay traffic risk.

Target architecture:

`GitHub = source control`  
`Cloudflare Workers = public Story Relay frontend`  
`Supabase = authenticated backend/data plane`

The current GitHub Pages deployment remains available only during migration. It must not be unpublished until the Cloudflare deployment, OAuth redirect, and core product flow have all been verified.

---

## E1 — Move Story Relay frontend off GitHub Pages

**狀態：Cloudflare migration PASS；待取消此 repo 的 GitHub Pages（2026-09-04）。**

### Repository preparation

- Keep the existing GitHub Pages workflow unchanged during migration so the current production URL remains a fallback.
- Add `pnpm run build:cloudflare` in `story-relay/package.json`.
- Cloudflare build must use root base `/`, not the GitHub Pages subpath.
- Static output directory is `dist/public` relative to `story-relay`.
- Supabase URL and publishable key remain build-time environment variables. Never place service-role credentials in Cloudflare or the browser bundle.
- Add `story-relay/wrangler.jsonc` with Worker name `story-relay` and compatibility date so connected builds deploy deterministically.

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
8. Core authenticated Supabase RPC/data path therefore works from the Cloudflare deployment.

Remaining E1 cutover action:

- Unpublish Story Relay's GitHub Pages site / disable this repository's Pages deployment.
- Do not alter Pages configuration for any other repository.
- After unpublishing, verify that Story Relay continues to function only from the Cloudflare production URL.

---

## E2 — Cloudflare edge protection

After E1 is stable:

- Keep Cloudflare DDoS protection as the public network edge.
- Add conservative WAF/rate-limit rules only after normal classroom traffic is measured.
- Do not use rules that risk blocking a legitimate burst of ~100 classroom users.
- Prefer protections against obvious automated abuse over aggressive global limits.
- If a custom domain is later added, keep it proxied through Cloudflare and avoid exposing an alternate public frontend origin.

### E2 acceptance

- Normal 100-person classroom flow remains unaffected.
- Static frontend requests are served by Cloudflare, not GitHub Pages.
- No public Story Relay GitHub Pages fallback remains after cutover.

---

## E3 — Supabase application-layer abuse protection

Cloudflare protecting the frontend does not protect Supabase from clients that call the Supabase endpoint directly. Add lightweight application-layer controls for expensive mutation paths.

Priority RPCs:

1. `join_activity_by_code`
2. `start_relay_round`
3. `submit_segment`
4. `nominate_candidate`
5. `volunteer_for_round`
6. deadline/finalizer endpoints only if evidence shows abuse value

Requirements:

- Rate limits must be keyed primarily by authenticated user/session or another trustworthy server-side identity boundary.
- Do not treat browser-provided IP/user identifiers as authorization data.
- Preserve idempotency and existing row locks.
- Return a clear throttling error without corrupting round/story state.
- Keep limits loose enough for legitimate classroom bursts.
- Add rollback-only SQL tests for throttle boundaries before enabling production enforcement.

### E3 acceptance

- Repeated abusive mutation calls are throttled.
- Ordinary classroom usage remains unaffected.
- RLS/authorization behavior remains unchanged.
- No new secret is exposed to the client.

---

## Scope boundary

This phase is abuse hardening for the current ~100-person classroom product. It does not add enterprise DDoS appliances, dedicated API gateways, Redis, SIEM, multi-region failover, or synthetic flood testing unless real operational evidence later justifies them.
