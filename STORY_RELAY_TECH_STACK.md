# Story Relay Tech Stack 與平台網址紀錄

**狀態：** 2026-09-04 開發階段封存版  
**適用範圍：** Story Relay 約 100 人課堂 MVP  
**排列方式：** 後端基礎設施 → 驗證 → 資料/API → 原始碼與建置 → Edge/部署 → 前端  

> 本文件只記錄實際採用或實際操作過的平台與技術。未使用的候選方案不列入正式 stack。

---

## 1. Supabase PostgreSQL — 核心後端資料庫

**角色：** Story Relay 的主要資料層與伺服器端狀態機。

### 使用內容

- PostgreSQL
- Row Level Security (RLS)
- PostgreSQL functions / RPC
- SECURITY DEFINER functions
- advisory locks
- triggers
- Realtime publication
- rollback-only SQL acceptance tests

### 專案資訊

- Supabase project ref: `nesldgerjowpnwxuxxzw`
- Project API base URL: `https://nesldgerjowpnwxuxxzw.supabase.co`
- Supabase Dashboard: `https://supabase.com/dashboard`
- Supabase 官方網站: `https://supabase.com/`
- Supabase 文件: `https://supabase.com/docs`

### Story Relay 主要資料表

- `profiles`
- `activities`
- `groups`
- `group_members`
- `stories`
- `segments`
- `writer_states`
- `relay_rounds`
- `nominations`
- `volunteers`
- `activity_events`
- `activity_name_history`
- `platform_admins`
- `platform_member_identities`
- `admin_audit_log`
- `rpc_rate_limit_state`

### 後端核心責任

- 使用者與活動資料持久化
- host / participant / platform-admin 權限邊界
- 跨組資料隔離
- 接力 round 狀態
- weighted next-writer selection
- nomination / volunteer intent
- activity deadline finalization
- host skip / expire round
- CSV 統計 RPC
- activity soft delete / restore
- per-user RPC abuse rate limiting

---

## 2. Supabase Auth — 應用程式驗證層

**角色：** Story Relay 的登入身分來源。

### 使用方式

- Supabase Auth
- Google OAuth provider
- 前端以 `@supabase/supabase-js` 取得 session
- PostgreSQL 使用 `auth.uid()` 作為伺服器端可信 user boundary

### 網址

- Supabase Auth project base: `https://nesldgerjowpnwxuxxzw.supabase.co`
- OAuth callback endpoint: `https://nesldgerjowpnwxuxxzw.supabase.co/auth/v1/callback`
- Supabase Dashboard: `https://supabase.com/dashboard`
- Supabase Auth 文件: `https://supabase.com/docs/guides/auth`

### Production redirect

目前 Supabase Authentication 的 production Site URL / Redirect URL 指向 Cloudflare frontend：

- `https://story-relay.wu33000.workers.dev`
- allowlist pattern: `https://story-relay.wu33000.workers.dev/**`

舊 GitHub Pages 網址已不再作為 production frontend。

---

## 3. Google Cloud / Google OAuth — Google 登入身分提供者

**角色：** 提供 Google Account OAuth 登入；Google 不承載 Story Relay 應用資料。

### 使用內容

- Google Cloud project
- OAuth consent screen
- OAuth 2.0 Web Application client
- scopes 僅使用登入所需範圍：
  - `openid`
  - `email`
  - `profile`

### 網址

- Google Cloud Console: `https://console.cloud.google.com/`
- Google Cloud APIs & Services: `https://console.cloud.google.com/apis`
- Google OAuth / Credentials 管理入口由 Google Cloud Console 的 APIs & Services → Credentials 進入
- Google OAuth 實際 authorized redirect URI: `https://nesldgerjowpnwxuxxzw.supabase.co/auth/v1/callback`

### 注意

Google OAuth 的 callback 仍然指向 Supabase，而不是直接指向 Cloudflare。流程為：

`Browser → Google → Supabase Auth callback → Cloudflare Story Relay frontend`

---

## 4. Supabase Realtime — 即時同步

**角色：** 將已授權的 StoryRoom 狀態變化即時同步到前端。

### 使用內容

- PostgreSQL Realtime publication
- RLS 作為資料可見性邊界
- Realtime 僅負責通知/刷新；不可取代伺服器端授權

### 網址

- Supabase project base: `https://nesldgerjowpnwxuxxzw.supabase.co`
- Supabase Realtime 文件: `https://supabase.com/docs/guides/realtime`

### 已驗證結果

C2 100 人課堂 probe：

- 200 / 200 events received
- duplicate events: 0
- max heartbeat drift: 2 ms

跨組 Realtime isolation 亦已通過動態測試。

---

## 5. GitHub — Source Control / 開發紀錄 / Cloudflare build source

**角色：** Story Relay 的唯一正式原始碼儲存庫，以及 Cloudflare connected build 的 source。

### Repository

- Repository: `wu33000-design/collaborative-storytelling`
- Repo URL: `https://github.com/wu33000-design/collaborative-storytelling`
- Default branch: `main`

### Story Relay 子目錄

- `story-relay/`

### 重要文件

- `STORY_RELAY_DEVELOPMENT_RECORD.md`
- `STORY_RELAY_TECH_STACK.md`（本文件）
- `CLASSROOM_100_DEVELOPMENT_PLAN.md`
- `PHASE_E_DDOS_ABUSE_HARDENING.md`
- `story-relay/AGENT_HANDOFF_PLAN.md`

### GitHub 在最終架構中的責任

- source control
- commit history
- migration / test source
- Cloudflare connected build source

### 已取消的責任

GitHub Pages 已不再承載 Story Relay production frontend。

本 repo 原先的 `.github/workflows/deploy-pages.yml` 已刪除，以避免未來 push 後重新啟用 Pages。

> 其他 GitHub repositories 的 Pages 設定不受此專案異動影響。

---

## 6. Node.js / pnpm — Build toolchain

**角色：** 前端依賴安裝與 production build。

### 版本/設定

- Node.js: build 環境使用 Node 20 時已完成 GitHub Pages 階段驗證；Cloudflare connected build 曾偵測 Node 24.x
- pnpm: `10.4.1`
- install: `pnpm install --frozen-lockfile`
- lockfile: `story-relay/pnpm-lock.yaml`

### 網址

- Node.js: `https://nodejs.org/`
- pnpm: `https://pnpm.io/`

### Cloudflare build script

`pnpm run build:cloudflare`

其核心為 Vite 使用 root base `/` 產生 production assets。

---

## 7. React — 前端 UI framework

**角色：** Story Relay application UI。

### 使用技術

- React 19
- TypeScript
- component-based UI
- client-side routing

### 網址

- React: `https://react.dev/`

### 主要頁面

- Start
- CreateActivity
- StoryRoom
- TeacherHub / Teacher dashboards
- Platform admin pages

---

## 8. Vite — Frontend bundler

**角色：** React frontend 的 development/build tool。

### 設定

- config: `story-relay/vite.config.ts`
- Cloudflare production base: `/`
- output: `story-relay/dist/public`

### 網址

- Vite: `https://vite.dev/`

---

## 9. Tailwind CSS + shadcn/ui — UI styling/component layer

**角色：** Story Relay 的 UI design system 與 reusable controls。

### 使用技術

- Tailwind CSS 4
- shadcn/ui component source
- React UI primitives

### 網址

- Tailwind CSS: `https://tailwindcss.com/`
- shadcn/ui: `https://ui.shadcn.com/`

### UI 原則

保留既有「紙上接力」視覺語言，並以故事內容、目前作者、接力狀態為主要資訊層級，不導入排行榜、XP 或競賽分數。

---

## 10. `@supabase/supabase-js` — Frontend ↔ Supabase client

**角色：** Browser 與 Supabase Auth / PostgreSQL RPC / Realtime 的 client SDK。

### 前端設定來源

Cloudflare build-time environment variables：

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

前端不得持有：

- Supabase `service_role` key
- Google OAuth client secret
- database password

### 網址

- Supabase JavaScript client 文件: `https://supabase.com/docs/reference/javascript/introduction`

---

## 11. Cloudflare Workers — Production edge / static frontend hosting

**角色：** Story Relay 最終 production frontend 與 public network edge。

### Production

- Worker name: `story-relay`
- Production URL: `https://story-relay.wu33000.workers.dev`
- Preview hostname pattern: `*-story-relay.wu33000.workers.dev`

### Cloudflare 平台

- Cloudflare Dashboard: `https://dash.cloudflare.com/`
- Cloudflare Workers: `https://workers.cloudflare.com/`
- Workers documentation: `https://developers.cloudflare.com/workers/`

### Repository 設定

- config: `story-relay/wrangler.jsonc`
- Worker name: `story-relay`
- compatibility date: `2026-09-03`

### Connected build

- GitHub repository: `wu33000-design/collaborative-storytelling`
- production branch: `main`
- root directory: `/story-relay`
- build command: `pnpm install --frozen-lockfile && pnpm run build:cloudflare`
- deploy command: `npx wrangler deploy --assets ./dist/public`

### Security responsibility

- public frontend edge
- Cloudflare automatic DDoS mitigation
- no Cloudflare Access for classroom users
- no aggressive shared-IP rate limit

直接打 Supabase API 的 authenticated abuse 則由 PostgreSQL RPC per-user throttling 處理。

---

# 最終資料流（後端 → 前端）

```text
Supabase PostgreSQL
  ↓
RLS / SECURITY DEFINER RPC / per-user rate limits
  ↓
Supabase Auth + Realtime
  ↑
Google OAuth
  ↓
@supabase/supabase-js
  ↓
React 19 + TypeScript
  ↓
Vite production build
  ↓
Cloudflare Workers / workers.dev
  ↓
Browser
```

Source/build control path：

```text
GitHub main
  ↓
Cloudflare connected build
  ↓
pnpm install --frozen-lockfile
  ↓
Vite build
  ↓
Wrangler deploy
  ↓
https://story-relay.wu33000.workers.dev
```

---

# 平台網址總表

| 順序 | 平台 / 服務 | 用途 | 網址 |
|---:|---|---|---|
| 1 | Supabase project | PostgreSQL / Auth / RPC / Realtime API | `https://nesldgerjowpnwxuxxzw.supabase.co` |
| 2 | Supabase Dashboard | 後端專案管理 | `https://supabase.com/dashboard` |
| 3 | Supabase OAuth callback | Google OAuth callback | `https://nesldgerjowpnwxuxxzw.supabase.co/auth/v1/callback` |
| 4 | Google Cloud Console | Google OAuth client / consent screen | `https://console.cloud.google.com/` |
| 5 | GitHub repository | source control / migrations / tests / build source | `https://github.com/wu33000-design/collaborative-storytelling` |
| 6 | Cloudflare Dashboard | Worker build/deploy 管理 | `https://dash.cloudflare.com/` |
| 7 | Cloudflare Workers platform | edge runtime | `https://workers.cloudflare.com/` |
| 8 | Story Relay production | 使用者正式入口 | `https://story-relay.wu33000.workers.dev` |

---

# 不再使用的 production URL

Story Relay 曾部署於 GitHub Pages：

`https://wu33000-design.github.io/collaborative-storytelling/story-relay/`

此網址已退役。該 repository 的 GitHub Pages 已手動取消發布，且自動 Pages deployment workflow 已從 repo 移除。

**未來不得把上述 GitHub Pages URL 恢復為 Story Relay production frontend，除非產品架構重新做出明確決策。**

---

# Secrets / 公開設定邊界

可以存在 browser bundle：

- Supabase project URL
- Supabase publishable / anon key

不得 commit、不得寫入本文件、不得放入 browser bundle：

- Supabase `service_role` key
- database password
- Google OAuth client secret
- 任何未來 server-side private credential

---

# 未來開發重新啟動時

新的人類或 AI agent 應依序閱讀：

1. `STORY_RELAY_DEVELOPMENT_RECORD.md`
2. `STORY_RELAY_TECH_STACK.md`
3. `CLASSROOM_100_DEVELOPMENT_PLAN.md`
4. `PHASE_E_DDOS_ABUSE_HARDENING.md`
5. 最新 `story-relay/supabase/migrations/`
6. 對應 `story-relay/supabase/tests/`

Repository 與 production state 永遠優先於舊交接文字；若兩者不一致，先查明差異後再修改。
