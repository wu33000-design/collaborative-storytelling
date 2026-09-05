# Safari bootstrap hardening

Date: 2026-09-06

## Incident

A user reported that the Story Relay production homepage rendered as a completely blank page in mobile Safari on iOS 26.6.1. Because no AuthGate loading state or React ErrorBoundary UI appeared, the failure was treated as a pre-render/bootstrap failure rather than an OAuth or ordinary component-rendering issue.

## Initial diagnosis

The incident was narrowed in stages:

1. The problem occurred immediately on the homepage, before Google OAuth, so OAuth redirect/session handling was deprioritized.
2. The device was running iOS 26.6.1, so old-Safari support for Vite 7 / Tailwind 4 was not considered a likely primary cause.
3. The browser showed a completely blank page rather than the AuthGate loading UI or React ErrorBoundary. This strongly suggested that the production JavaScript module failed before React mounted, or that the browser received stale/missing assets.
4. Repository inspection also found several production-unnecessary prototype artifacts: `vitePluginManusRuntime()`, JSX-location instrumentation, Manus debug/storage plugins, and unresolved analytics placeholders in `index.html`.

## Hardening applied

1. Production Vite builds now include only the React and Tailwind build plugins. Manus runtime, JSX-location instrumentation, debug collection, and the Manus storage proxy remain development-only.
2. The unresolved Manus analytics placeholders were removed from the production HTML.
3. `main.tsx` now has a bootstrap-level fallback for synchronous React startup failures.
4. `index.html` now has a dependency-free startup watchdog. If the module bundle does not render anything into `#root` within 12 seconds, users see a reload/recovery message instead of a permanent blank page.

Primary patch commit:

`48f3f1c39aa8f9b828687aa83bc3c9d6fd297869`

## Deployment discovery

After the patch was pushed to GitHub `main`, Cloudflare did not create a new build or deployment. The Cloudflare dashboard showed only one-day-old deployments and recent builds, even though the GitHub repository had newer commits.

This revealed a second operational issue: the Cloudflare Workers project had become disconnected from GitHub, so the Safari hardening patch had not actually reached production.

The GitHub connection was re-established in Cloudflare, and a new build/deployment was started from `main`.

## Resolution

After Cloudflare was reconnected to GitHub and the new build was deployed, the same iPhone Safari device that had previously shown a completely blank homepage was tested again against:

`https://story-relay.wu33000.workers.dev`

Result: **PASS — the homepage rendered normally.**

Therefore the incident is considered resolved in production.

## Root-cause assessment

The evidence supports a combined operational/frontend-hardening conclusion:

- The immediate reason the first attempted fix appeared ineffective was confirmed: Cloudflare was disconnected from GitHub, so the new code had not deployed.
- The original blank-page trigger itself was not isolated to one single JavaScript statement or cache response after deployment, because the problem disappeared once the hardened build actually reached production.
- The removed production-only prototype/runtime artifacts and new bootstrap fallback materially reduce the chance of an opaque white-screen failure recurring and make any future bootstrap failure visible to the user.

Accordingly, do not describe one specific Manus plugin, Safari cache entry, or Supabase call as the proven sole root cause. What is proven is that the pre-render blank-page symptom was resolved after the production bootstrap hardening was actually deployed, and that the deployment pipeline had been disconnected during diagnosis.

## Operational lesson

When a future production fix is pushed to `main`, do not assume Cloudflare connected build is still active. Verify all three layers:

1. GitHub `main` contains the intended commit.
2. Cloudflare Build History contains a corresponding new build.
3. Cloudflare Deployments shows the new version as active before asking users to retest.

A successful GitHub commit alone is not evidence that `workers.dev` is serving that revision.

## Scope

This patch does not change Story Relay product behavior, routing, Supabase authentication, RLS, RPCs, or classroom data. It is production bootstrap and deployment-pipeline hardening only.

## Acceptance

Completed on 2026-09-06:

- mobile Safari on the original affected iPhone: **PASS**;
- production homepage no longer stays blank;
- Cloudflare GitHub connection restored and build performed from `main`;
- future pre-React bootstrap failures now have a visible HTML-level fallback rather than an empty document.
