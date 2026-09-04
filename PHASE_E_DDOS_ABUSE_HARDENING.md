# Phase E — DDoS / Abuse Hardening

## Goal

Protect Story Relay without exposing the user's other GitHub Pages sites to Story Relay traffic risk.

Target architecture:

`GitHub = source control`  
`Cloudflare Pages = public Story Relay frontend`  
`Supabase = authenticated backend/data plane`

The current GitHub Pages deployment remains available only during migration. It must not be unpublished until the Cloudflare deployment, OAuth redirect, and core product flow have all been verified.

---

## E1 — Move Story Relay frontend off GitHub Pages

### Repository preparation

- Keep the existing GitHub Pages workflow unchanged during migration so the current production URL remains a fallback.
- Add `pnpm run build:cloudflare` in `story-relay/package.json`.
- Cloudflare build must use root base `/`, not the GitHub Pages subpath.
- Static output directory is `dist/public` relative to `story-relay`.
- Supabase URL and publishable key remain build-time environment variables. Never place service-role credentials in Cloudflare or the browser bundle.

### Cloudflare Pages Git integration settings

- Repository: `wu33000-design/collaborative-storytelling`
- Production branch: `main`
- Root directory: `story-relay`
- Build command: `pnpm run build:cloudflare`
- Build output directory: `dist/public`
- Required environment variables:
  - `VITE_SUPABASE_URL`
  - `VITE_SUPABASE_PUBLISHABLE_KEY`

Cloudflare Pages Git integration is preferred so normal pushes to `main` produce deployments directly from the repository.

### E1 acceptance

Before touching GitHub Pages:

1. Cloudflare deployment succeeds.
2. Root page loads from the Cloudflare Pages hostname.
3. Google OAuth login succeeds and returns to the Cloudflare hostname.
4. Existing session/auth gate works.
5. User can enter an activity code on the home page and join.
6. StoryRoom loads, Realtime updates work, and submission works.
7. Host can create/manage an activity.
8. Platform-admin page remains authorization-gated.
9. Supabase allowed redirect URLs include the Cloudflare Pages production URL.

Only after all acceptance checks pass:

- Unpublish Story Relay's GitHub Pages site / disable its Pages deployment.
- Do not alter Pages configuration for any other repository.

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
