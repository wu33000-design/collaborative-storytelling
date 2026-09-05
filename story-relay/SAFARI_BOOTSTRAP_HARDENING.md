# Safari bootstrap hardening

Date: 2026-09-06

## Incident

A user reported that the Story Relay production homepage rendered as a completely blank page in mobile Safari on iOS 26.6.1. Because no AuthGate loading state or React ErrorBoundary UI appeared, the failure is treated as a pre-render/bootstrap failure rather than an OAuth or ordinary component-rendering issue.

## Hardening applied

1. Production Vite builds now include only the React and Tailwind build plugins. Manus runtime, JSX-location instrumentation, debug collection, and the Manus storage proxy remain development-only.
2. The unresolved Manus analytics placeholders were removed from the production HTML.
3. `main.tsx` now has a bootstrap-level fallback for synchronous React startup failures.
4. `index.html` now has a dependency-free startup watchdog. If the module bundle does not render anything into `#root` within 12 seconds, users see a reload/recovery message instead of a permanent blank page.

## Scope

This patch does not change Story Relay product behavior, routing, Supabase authentication, RLS, RPCs, or classroom data. It is production bootstrap hardening only.

## Acceptance

After Cloudflare connected build finishes, verify:

- desktop production homepage still loads;
- mobile Safari production homepage no longer stays completely blank;
- Google sign-in still works;
- if bootstrap is intentionally broken in a controlled development test, the HTML-level fallback becomes visible rather than leaving an empty document.
