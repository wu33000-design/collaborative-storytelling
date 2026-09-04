# Story Relay 完整開發紀錄

**紀錄封存日期：2026-09-04**  
**Repository：** `wu33000-design/collaborative-storytelling`  
**主要應用目錄：** `story-relay/`  
**目前公開網址：** `https://story-relay.wu33000.workers.dev`  
**目前狀態：** 約 100 人課堂 MVP 與 Phase E DDoS / abuse hardening 均完成驗收；本階段開發告一段落。

---

# 1. 文件目的

這份文件是 Story Relay 本階段的完整工程與產品紀錄，目的是讓未來的人類開發者或 AI agent 在不依賴既有對話記憶的情況下，可以從 GitHub repository 直接理解：

1. 產品要解決什麼問題。
2. 哪些產品規則已經定案。
3. 現行系統架構與安全邊界。
4. 已完成的資料庫、前端與部署工作。
5. 每個開發階段如何驗收。
6. 哪些限制是刻意保留，而不是 bug。
7. 未來重新開發時應從哪裡開始。

Git history 仍是逐檔、逐 commit 的最細粒度事實來源；本文件提供的是可閱讀、可交接的完整脈絡。

---

# 2. 產品定位

Story Relay 是一個課堂協作敘事工具。主持人建立活動後，學生加入活動並在小組故事中輪流接棒寫作。每一輪只有目前作者可以提交段落；完成後由系統根據候選資格、提名與等待權重選出下一位作者。

產品核心不是排名、競爭或遊戲化積分，而是：

> 讓一群學生能在透明、可追蹤且公平輪替的流程中，共同完成一個故事。

本階段的明確交付上限是：

> 一個主持人可在單一課堂中讓約 100 名登入使用者穩定加入、分組、輪流投稿、查看故事，並由主持人與平台管理者完成必要操作。

不是企業級 SaaS，也沒有為上千人、多租戶組織、跨區域災難復原或大型商業流量做保證。

---

# 3. 已確定的產品規則

## 3.1 身分與角色

現行前端文字使用「主持人」，資料庫歷史欄位仍保留 `teacher_id` 等名稱。

主要角色：

- **主持人**：建立活動、監控自己活動、停止活動、跳過無法完成的 round、下載活動 CSV、刪除自己活動。
- **參與者**：加入活動、讀取自己有權限的小組內容、目前作者投稿、非目前作者可志願、目前作者可提名。
- **平台管理者**：跨活動唯讀檢視內容、刪除／恢復活動、管理平台管理者，以及使用進階分組設定。
- **Writer 0**：虛擬故事起始內容，不是實際登入者。

同一個登入帳號可以同時是某活動的主持人並加入自己的活動成為參與者。建立活動本身不會自動把主持人加入 group。

## 3.2 活動設定

主持人可設定的欄位原則上都是 optional：

- 名稱
- prompt
- Writer 0 / initial text
- 每輪秒數
- 最短長度
- 最長長度
- 所需段落數
- deadline

空白限制的語義是「真正不限」，不是套用隱藏預設值。

## 3.3 Group 決策

`groups`、多 group 配置、cross-group RLS、Realtime isolation、dashboard support 都完整保留。

但產品決策為：

- 一般主持人現階段 **不看到也不能設定有限 group size**。
- 一般主持人建立活動時 `group_size = NULL`，底層使用單一 unlimited Group。
- 有限 group size / 多組自動配置被視為 **進階版功能**，只有平台管理者可以看到與使用。
- 既有多 group 資料不刪除、不轉換。
- SQL Editor / migration 等 trusted DB context 仍可建立多 group fixture 供測試。

後端有實際 trigger enforcement，不是只做 UI hiding。

## 3.4 加入與 late join

只要活動仍 active 且 deadline 未到，學生可以 late join。

新加入者：

- `waiting_rounds = 0`
- `selection_weight = 1`
- 只參與未來 round selection
- 不改寫既有歷史

## 3.5 選人與接力

主要規則：

- 每輪只有 `current_writer_id` 可以 submit。
- 目前作者可以提名下一位候選人。
- 有有效提名時，候選池縮小到被提名且仍 eligible 的參與者。
- 無有效提名時，從所有 eligible writers 中選擇。
- selection 使用 `selection_weight` 加權隨機。
- 寫完的人 `waiting_rounds` 歸零、`selection_weight` 回到 1。
- 其他仍 eligible 的人等待輪次與權重增加。
- 志願只表達意願，目前不改變 selection weight。
- 多人組中，剛寫完的人不會立即再次被選中。
- 若整組只剩唯一 eligible writer，允許 single-writer fallback 連續寫作。

## 3.6 故事與歷史

- `segments` 是 append-only 的核心語義；已提交段落不由一般流程覆寫。
- stopped / completed story 都可唯讀查看完整內容。
- Writer 0 與真實學生投稿在 UI 中清楚區分。
- rename activity 會保留 immutable `activity_name_history`，且 story title 同步更新。

## 3.7 Stop / delete / restore

主持人可隨時 stop 自己的活動。

Stop：

- 保留所有 stories / segments。
- activity 轉 closed。
- active stories 關閉。
- active rounds expire。
- 阻止後續 join / submit / round start。

每位主持人最多有 **3 個未刪除活動**；active 與 stopped 都計入。soft-deleted 不計入。

Soft delete：

- 保留 30 天 restore window。
- 主持人看不到自己已刪除的活動。
- 只有平台管理者可 restore。
- restore 時仍受每主持人最多 3 個未刪除活動限制。

## 3.8 Deadline 與每輪秒數

這兩個概念必須分開：

### Activity deadline

已實作 server-side finalization：

- deadline 到達後禁止 join / submit / round start。
- active activity 轉 closed，`closed_reason='deadline'`。
- active story 關閉。
- active round expire。
- 寫入 `activity_deadline_reached` event。
- finalizer 是 idempotent。

### Per-round time limit

已實作 UI countdown：

- 基於 `relay_rounds.started_at + activities.time_limit_seconds`。
- 前端每秒本地更新，不會每秒打 Supabase。
- >60 秒顯示 `MM:SS`。
- <=60 秒進入醒目狀態。
- 0 秒顯示「本輪時間已到」。

**刻意未實作：每輪歸零後自動 expire / 自動換棒。**

目前逾時 round 由主持人既有 `skip_relay_round` 機制處理。這是本階段 MVP scope boundary，不是遺漏。

---

# 4. 最終技術架構

```text
GitHub repository
    │
    │ source control + Cloudflare connected build
    ▼
Cloudflare Workers (workers.dev)
    │
    │ static React/Vite frontend + automatic edge DDoS mitigation
    ▼
Browser
    │
    ├── Supabase Auth (Google OAuth)
    ├── Supabase PostgreSQL
    ├── PostgreSQL RLS
    ├── SECURITY DEFINER RPC
    └── Supabase Realtime
```

現行生產網址：

`https://story-relay.wu33000.workers.dev`

Supabase project URL：

`https://nesldgerjowpnwxuxxzw.supabase.co`

前端技術：

- React 19
- Vite
- Tailwind 4
- shadcn/ui 元件
- `@supabase/supabase-js`

Backend 不維護獨立 Node API；核心 authoritative mutations 在 PostgreSQL RPC / RLS 中完成。

---

# 5. Supabase Auth / OAuth

Google OAuth 已設定並完成 Cloudflare production smoke。

Supabase callback：

`https://nesldgerjowpnwxuxxzw.supabase.co/auth/v1/callback`

Cloudflare migration 後，Supabase Auth URL Configuration 已改為以 Cloudflare hostname 為 production Site URL，並加入 Cloudflare redirect allowlist。

重要原則：

- browser bundle 只使用 Supabase URL 與 publishable/anon key。
- `service_role`、Google Client Secret、DB password 不可進 repo 或前端。
- `client/src/lib/supabase.ts` 若缺 `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY` 會直接 throw，因此 Cloudflare 必須在 **build-time environment variables** 提供這兩個值。

Cloudflare connected build：

- repo：`wu33000-design/collaborative-storytelling`
- production branch：`main`
- root directory：`/story-relay`
- build：`pnpm install --frozen-lockfile && pnpm run build:cloudflare`
- deploy：`npx wrangler deploy --assets ./dist/public`
- Worker name：`story-relay`
- static output：`dist/public`

`story-relay/wrangler.jsonc` 保存 Worker name 與 compatibility date。

---

# 6. 核心資料模型

主要 tables：

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
- `rpc_rate_limit_state`（Phase E3）

重要 helper / RPC 包括：

- `is_group_member(uuid)`
- `is_activity_teacher(uuid)`
- `shares_group_with(uuid)`
- `create_activity(...)`
- `join_activity_by_code(text)`
- `start_relay_round(uuid)`
- `submit_segment(uuid,text)`
- `volunteer_for_round(uuid)`
- `nominate_candidate(uuid,uuid)`
- `skip_relay_round(uuid)`
- `stop_activity(uuid)`
- `rename_activity(uuid,text)`
- `get_teacher_activity_dashboard(uuid)`
- `get_teacher_activity_csv(uuid)`
- `finalize_activity_deadline(uuid)`
- platform admin stats/content/delete/restore RPCs
- `sync_my_login_identity`
- `get_classroom100_admin_audit(integer)`

SECURITY DEFINER 相關函式應維持明確 schema qualification / hardened search path，不要因後續重構而把授權依賴移回前端。

---

# 7. 安全模型

## 7.1 RLS

核心原則：

- 參與者只能讀自己 group 可見的 stories / segments / rounds / members。
- 知道其他 group UUID 也不能繞過。
- Realtime payload 同樣受 RLS 邊界限制。
- host 只能控制自己主持的活動。
- platform admin 的跨活動內容能力透過 explicit read-only RPC，而不是全面放寬一般 RLS。
- participant 不可直接改 `writer_states`、`relay_rounds`、`segments` 或 `platform_admins`。

## 7.2 平台管理權限

平台管理者具備：

- 平台統計
- 活動內容唯讀檢視
- soft delete / restore
- 平台管理者管理
- 進階 group size / multi-group 設定

`admin_audit_log` 保存至少：

- admin_added
- admin_removed
- activity_deleted
- activity_restored
- expired_activity_purged

一般 authenticated client 不可直接寫入 audit log。

## 7.3 XSS

已完成實際 smoke：

- activity name
- prompt
- display name
- segment

都只以文字呈現。

掃描未找到 application 使用 `dangerouslySetInnerHTML` / `innerHTML`。

測試結果：

- payload side effects = 0
- unexpected script nodes = 0
- unexpected img/svg nodes = 0

---

# 8. 開發階段與驗收紀錄

# Phase A — 供應鏈與部署基線

目標：建立可重現、可安全建置的 frontend dependency baseline。

主要工作：

- 移除 application 未使用的 Axios dependency。
- 同步 `pnpm-lock.yaml`。
- frozen lockfile install。
- Node / pnpm build baseline。
- production dependency audit high severity 問題清理。

這一階段完成後才進入資料權限與容量驗證。

---

# Phase B — 高權限資料面最小加固

目標：先把真正 destructive / cross-platform 的權限邊界收緊，而不是重寫整個資料庫。

主要工作：

- 平台管理 RPC 授權檢查。
- `platform_admins` / identity table client-write boundary。
- admin audit log。
- 高影響 SECURITY DEFINER hardening。
- join / submit / stop / rename 等 authoritative mutation 邊界檢查。

主要 migration：

`story-relay/supabase/migrations/20260903_classroom100_security_hardening.sql`

---

# Phase C — 100 人課堂安全與容量驗證

**結果：PASS（2026-09-04）**

## C1 Cross-group / role security

驗證角色：

1. anon
2. Group A participant
3. Group B participant
4. activity host
5. platform admin

完成：

- SQL cross-group RLS PASS。
- Realtime cross-group isolation PASS。
- host / platform-admin / participant mutation boundary PASS。

Realtime isolation 驗證採 unfiltered probes 配合 RLS：

- own-group positive event 能收到。
- other-group negative event 收不到。

## C2 100-person capacity smoke

完成真實容量 smoke：

- 100 participants。
- group size 5 fixture → 20 groups。
- 100 次真實 segment submits。
- 100 completed rounds。
- 20 next rounds。
- host dashboard 20 group summaries。

Realtime browser probe：

- 200 / 200 events received。
- duplicates = 0。
- max heartbeat drift = 2 ms。
- receive duration = 1745 ms。

這是 100 人課堂 smoke，不是 DDoS / enterprise load test。

## C3 XSS

四類輸入均 PASS，且臨時 probe route/page 完成後已移除。

Phase C completion commit：

`99aafb858d1da045ee614e4913c778c573aca7fc`

---

# Phase D — 課堂功能完成

# D1 主持人 skip / 接力異常處理

新增：

`skip_relay_round(uuid)`

規則：

- 只有活動主持人可操作。
- 被跳過 round 保留為 `expired`。
- 不產生 segment。
- 不增加 `times_written`。
- 有其他 eligible writer 時依既有候選 / weight 規則選下一棒。
- 只剩一位時 single-writer fallback。
- 寫入 `relay_round_skipped` event。

Rollback test：

`story-relay/supabase/tests/classroom100_phase_d1_skip_round.sql`

結果：

`CLASSROOM_100 D1 host skip relay round passed`

實際 UI smoke 亦驗證 round 進位與 current writer UUID 切換。

主要 commits：

- `0bf80af7` Add D1 host relay round skip recovery
- `f6769446` Add D1 host skip round rollback test
- `61f6ccbb` Add D1 host skip control to dashboard
- `2a158c13` Mark D1 relay exception handling complete

---

# D2 完成 / 停止故事唯讀狀態

完成：

- completed story 唯讀。
- closed / stopped story 唯讀。
- Writer 0 與實際 segments 正確呈現。
- completion 與 stop UI 文案不再混淆。

主要 commit：

`f0d1201d8a61565ac4624cd25ed85d05cdab54d6`

---

# D3 主持人 CSV

新增 RPC：

`get_teacher_activity_csv(uuid)`

CSV 設計：

- 每個 activity 一份。
- 位於主持人活動卡片。
- UTF-8 BOM。
- 正確 CSV escaping。
- spreadsheet formula injection 防護。
- 不包含故事全文。
- 不包含平台登入 Email。

Rollback test：

`story-relay/supabase/tests/classroom100_phase_d3_teacher_csv.sql`

結果：

`CLASSROOM_100 D3 teacher CSV passed`

主要 commits：

- `eb589022` Add D3 teacher activity CSV stats RPC
- `2dbc597e` Add D3 teacher CSV authorization and stats test
- `cad54d2e` Add D3 teacher CSV export to dashboard
- `f302b037` Place D3 CSV export on activity cards

---

# D4 Activity deadline + per-round countdown

## Activity deadline

新增：

`finalize_activity_deadline(uuid)`

Migration：

`story-relay/supabase/migrations/20260904_d4_activity_deadline_finalize.sql`

Rollback test：

`story-relay/supabase/tests/classroom100_phase_d4_activity_deadline.sql`

結果：

`CLASSROOM_100 D4 activity deadline passed`

前端 StoryRoom 與主持人監控頁都有 deadline watcher / finalizer 行為。

## Per-round countdown root cause repair

實際 smoke 發現某 active round 的 `started_at = NULL`，使 UI 無法計算倒數。

修正 migration：

`story-relay/supabase/migrations/20260904_d4_relay_round_started_at.sql`

行為：

- `relay_rounds.started_at default now()`。
- migration 當下只回填 open/writing 且 `started_at IS NULL` 的 active rounds。
- 不替歷史 completed / expired rows 虛構時間。

Rollback test：

`story-relay/supabase/tests/classroom100_phase_d4_round_started_at.sql`

結果：

`CLASSROOM_100 D4 relay round started_at passed`

實際 UI smoke 確認倒數可見。

主要 commits：

- `48443749` Add D4 automatic activity deadline finalization
- `e60cfbaa` Record D4 deadline finalizer trigger actor
- `0d3e2e14` Add D4 deadline finalization rollback test
- `6d58ee68` Add D4 deadline state to host dashboard
- `0f350673` Add D4 deadline watcher to story room
- `944c675c` Use per-round countdown in story room
- `1d74ab23` Ensure relay rounds always record start time
- `e0c08ba6` Add D4 relay round start-time smoke test

---

# Start page join flow simplification

獨立 `/join` page 已移除。

目前首頁 / Start page 直接提供 activity-code join form。

主要 commits：

- `27268eaa` Move activity code join form to start page
- `28dd81cb` Remove standalone join route
- `d4cab4d7` Remove standalone join page

---

# D5 端到端驗收

Rollback-only E2E：

`story-relay/supabase/tests/classroom100_phase_d5_end_to_end.sql`

涵蓋：

1. host create
2. participant join
3. start round
4. submit
5. host skip
6. host stop
7. host CSV
8. platform admin soft delete
9. restore
10. round `started_at` non-null

結果：

`CLASSROOM_100 D5 end-to-end acceptance passed`

Commit：

`f0d3ab70200cc9777fe4f1817429c7dcd88560f1`

整體 100 人課堂 MVP completion：

`b55455e31505299b91f40707de727c2ab4b7f661`

---

# 9. Platform-admin advanced grouping

產品決策：group 功能完整保留，但一般主持人暫不使用。

Migration：

`story-relay/supabase/migrations/20260904_platform_admin_advanced_grouping.sql`

前端：

`story-relay/client/src/pages/CreateActivity.tsx`

規則：

- `group_size = NULL`：允許所有主持人。
- logged-in user 若要有限 `group_size`：必須是 `platform_admins`。
- trusted SQL / migration context `auth.uid() IS NULL` 允許建立 fixture。
- normal host UI 不顯示每組人數。
- platform admin UI 顯示「平台管理者 · 進階分組」。

主要 commits：

- `945335d9` initial grouping guard
- `e4ef741d` trusted SQL fixture compatibility
- `fa71618f` CreateActivity advanced grouping UI

---

# 10. Phase E — DDoS / abuse hardening

完整規格：

`PHASE_E_DDOS_ABUSE_HARDENING.md`

## E1 Frontend 從 GitHub Pages 遷移到 Cloudflare

使用者的 GitHub 帳號還有其他 repo Pages，因此明確要求 Story Relay 公開流量不要再由 GitHub Pages 承擔。

最終選擇：

- GitHub = source control only。
- Cloudflare Workers = public Story Relay frontend。
- Supabase = backend/data plane。

Cloudflare first deploy 曾因缺少 Wrangler `compatibility_date` 失敗；build 本身成功。

修正：

`story-relay/wrangler.jsonc`

Commit：

`10886a5baf4b80f5fc269a4b4ac4a08d7ffdc4cc`

第二個 runtime 問題是 Cloudflare build 起初沒有 `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY`，前端初始化會直接 throw。加入 Cloudflare build variables 後正常。

接著 Supabase Auth 的 Site URL / Redirect URL 從舊 GitHub Pages 改為 Cloudflare production hostname，Google OAuth 登入成功回到 Cloudflare。

Cloudflare production smoke：

- Google login PASS。
- create activity PASS。
- 測試 activity code：`SR-798715`。
- join activity PASS。
- StoryRoom load PASS。
- current-writer state PASS。
- 30-second countdown PASS。
- segment submit PASS。
- next round PASS。

Migration smoke record commit：

`5034d704e3d016397dff3544774506b378d97db1`

Cloudflare 驗證完成後才手動 unpublish **這個 repository** 的 GitHub Pages；其他 repo Pages 完全不動。

為避免下一次 push 又把 Pages 自動打開，最後刪除：

`.github/workflows/deploy-pages.yml`

Commit：

`8a13a7eb78484d057c502d253bb57a5223060b3d`

## E2 Cloudflare edge protection

目前使用免費 `workers.dev`，使用者不打算購買 custom domain。

策略：

- 使用 Cloudflare automatic DDoS mitigation。
- 不加入 Cloudflare Access，避免學生多一道登入 gate。
- 不做 aggressive IP rate limiting，避免校園同一 NAT / egress IP 的 100 人被一起誤傷。
- custom WAF / zone-level rate-limit 留待日後有實際 evidence 且有 custom domain 時再做。

對目前 classroom MVP，E2 判定 PASS。

## E3 Supabase application-layer RPC throttling

因攻擊者可以繞過 Cloudflare frontend，直接呼叫 Supabase，核心 mutation 需要 server-side user-aware rate limit。

Migration：

`story-relay/supabase/migrations/20260904_e3_rpc_abuse_rate_limits.sql`

Rollback-only test：

`story-relay/supabase/tests/classroom100_phase_e3_rpc_abuse_rate_limits.sql`

Per authenticated user / action limits：

- `join_activity_by_code`: 20 / 60 sec
- `start_relay_round`: 20 / 60 sec
- `submit_segment`: 8 / 60 sec
- `nominate_candidate`: 60 / 60 sec
- `volunteer_for_round`: 20 / 60 sec

設計：

- bucket 以 authenticated user + action 為 key。
- 不使用 browser-provided IP 當 authorization data。
- 不是全班共享 quota，因此 100 人同時正常使用不互相消耗額度。
- 原 RPC implementation 保存為 internal unthrottled function。
- `authenticated` 不可 execute internal bypass。
- `authenticated` 不可直接執行 rate-limit bucket helper。
- public wrapper 才是 browser 可呼叫入口。

Rollback test 實際結果：

`CLASSROOM_100 E3 RPC abuse rate limits passed`

主要 commits：

- `ba19fa11` Add E3 per-user RPC abuse rate limits
- `f60d1083` Add E3 rollback-only RPC rate-limit test
- `a72474ca` Fix E3 independent bucket test through public wrapper
- `4d82998a` Mark Phase E hardening complete

---

# 11. 最終驗收摘要

以下均已實際完成，不只是設計文件：

| 項目 | 結果 |
|---|---|
| 100-person join / group / relay smoke | PASS |
| Cross-group SELECT RLS | PASS |
| Cross-group Realtime isolation | PASS |
| Role/mutation boundary | PASS |
| XSS smoke | PASS |
| Host skip round | PASS |
| Completed/stopped story read-only | PASS |
| Host CSV | PASS |
| Activity deadline finalizer | PASS |
| Relay round started_at | PASS |
| Per-round countdown UI | PASS |
| D5 end-to-end rollback test | PASS |
| Cloudflare deploy | PASS |
| Google OAuth on Cloudflare | PASS |
| Create/join/submit on Cloudflare | PASS |
| GitHub Pages cutover | PASS |
| Per-user RPC abuse throttling | PASS |

已知的重要 SQL PASS strings：

- `CLASSROOM_100 C1 cross-group RLS passed`
- `CLASSROOM_100 C1 role/mutation RLS passed`
- `CLASSROOM_100 D1 host skip relay round passed`
- `CLASSROOM_100 D3 teacher CSV passed`
- `CLASSROOM_100 D4 activity deadline passed`
- `CLASSROOM_100 D4 relay round started_at passed`
- `CLASSROOM_100 D5 end-to-end acceptance passed`
- `CLASSROOM_100 E3 RPC abuse rate limits passed`

---

# 12. 目前公開與部署狀態

Production frontend：

`https://story-relay.wu33000.workers.dev`

GitHub Pages：

- `collaborative-storytelling` repo Pages 已人工 unpublish。
- repo 內原 `deploy-pages.yml` 已刪除，未來 push 不會自動 re-enable。
- 使用者其他 repositories 的 Pages 未修改。

Cloudflare connected build 會從 GitHub `main` 取得 source。

因此：

```text
public traffic → Cloudflare
source/build trigger → GitHub
application data/auth/realtime → Supabase
```

---

# 13. 現階段刻意不做的事情

以下不是待修 bug，而是本階段明確 scope boundary：

- 不保證 >100 人正式容量。
- 不做 enterprise SSO / domain allowlist。
- 不做 multi-region HA / DR。
- 不做 SIEM / dedicated observability stack。
- 不做 Redis / dedicated API gateway。
- 不做 synthetic DDoS flood testing。
- 不購買 custom domain。
- 不加入 Cloudflare Access。
- 不做 aggressive per-IP edge rate limit。
- 不做每輪 countdown 到 0 自動 expire / auto-advance。
- 不讓一般主持人使用 finite group size / multi-group UI。
- 不新增排行榜、XP、徽章、競賽分數等 gamification。
- 不把故事全文放進主持人統計 CSV。

---

# 14. 重要 repository 文件

未來接手前應至少讀：

1. `STORY_RELAY_DEVELOPMENT_RECORD.md` — 本文件，完整現況與歷史。
2. `CLASSROOM_100_DEVELOPMENT_PLAN.md` — 100 人課堂 A–D 開發與驗收細節。
3. `PHASE_E_DDOS_ABUSE_HARDENING.md` — Cloudflare / abuse hardening。
4. `SECURITY_AUDIT_REPORT.md` — security review 歷史。
5. `SECURITY_AGENT_HANDOFF_PROMPT.md` — security agent context。
6. `story-relay/AGENT_HANDOFF_PLAN.md` — 早期產品與資料模型交接；注意其中部分「下一階段」敘述已是歷史，應以本文件與現行 repo 為準。
7. `story-relay/ideas.md` — UI / visual language。
8. `story-relay/supabase/migrations/` — authoritative migration history。
9. `story-relay/supabase/tests/` — rollback-only acceptance tests。

---

# 15. 未來重新開發時的正確起點

下一個 agent / developer 不應重新設計既有架構。開始前：

1. 先讀本文件。
2. 讀 `CLASSROOM_100_DEVELOPMENT_PLAN.md` 與 `PHASE_E_DDOS_ABUSE_HARDENING.md`。
3. 以 GitHub `main` 最新 commit 為唯一 code baseline。
4. 盤點最新 migration 後再修改 SECURITY DEFINER RPC；不要只看最早定義，因後續 migration 可能 `create or replace`。
5. 不要改動既有 RLS / authorization boundary，除非有 rollback test 證明等價或更嚴格。
6. 任何 DB mutation 行為改動都應新增 rollback-only SQL test。
7. 任何公開 deployment 變更先驗證 Cloudflare，再改 production routing。
8. 不要重新啟用 GitHub Pages 作為 Story Relay production frontend。
9. 不要提交 service-role key、OAuth secret、DB password。
10. 不要把 100-person capacity smoke 描述成 DDoS / enterprise load test。

如果未來要繼續，最可能的合理方向是：

- 依真實課堂使用回饋修 UX。
- 量測 Cloudflare / Supabase 實際 quota 與 bottleneck。
- 視需要決定是否把 advanced grouping 開放為產品方案。
- 若真的需要每輪硬 timeout，再設計 server-authoritative round expiry，而不是只在前端 timer 上加 auto-submit/auto-skip。
- 若有 custom domain 再評估 zone-level WAF / edge rate limiting。

---

# 16. 2026-09-04 關鍵 commit chronology

以下不是全部 Git history，但涵蓋本日完成 MVP 與 Phase E 的主要里程碑：

| Commit | 意義 |
|---|---|
| `99aafb85` | Mark Phase C classroom security and capacity complete |
| `0bf80af7` | Add D1 host relay round skip recovery |
| `f6769446` | Add D1 host skip round rollback test |
| `61f6ccbb` | Add D1 host skip control to dashboard |
| `f0d1201d` | Clarify completed and stopped story states |
| `eb589022` | Add D3 teacher activity CSV stats RPC |
| `2dbc597e` | Add D3 teacher CSV authorization and stats test |
| `f302b037` | Place D3 CSV export on activity cards |
| `48443749` | Add D4 automatic activity deadline finalization |
| `0d3e2e14` | Add D4 deadline finalization rollback test |
| `6d58ee68` | Add D4 deadline state to host dashboard |
| `0f350673` | Add D4 deadline watcher to story room |
| `27268eaa` | Move activity code join form to start page |
| `28dd81cb` | Remove standalone join route |
| `d4cab4d7` | Remove standalone join page |
| `944c675c` | Use per-round countdown in story room |
| `1d74ab23` | Ensure relay rounds always record start time |
| `e0c08ba6` | Add D4 relay round start-time smoke test |
| `f0d3ab70` | Add D5 end-to-end classroom acceptance test |
| `b55455e3` | Mark classroom 100 MVP acceptance complete |
| `9e0e5cb0` | Add Cloudflare frontend build |
| `1cd68d22` | Add Phase E DDoS and abuse hardening plan |
| `10886a5b` | Configure Cloudflare Worker deployment |
| `5034d704` | Mark Cloudflare migration smoke test passed |
| `ba19fa11` | Add E3 per-user RPC abuse rate limits |
| `f60d1083` | Add E3 rollback-only RPC rate-limit test |
| `a72474ca` | Fix E3 independent bucket test through public wrapper |
| `8a13a7eb` | Remove obsolete GitHub Pages deployment workflow |
| `4d82998a` | Mark Phase E hardening complete |

---

# 17. 封存狀態

截至 2026-09-04：

> **Story Relay 的「約 100 人課堂可用 MVP」已完成；Cloudflare frontend migration、OAuth、GitHub Pages cutover、Supabase application-layer abuse throttling 也已完成。**

本階段不再需要為了「完成 MVP」繼續增加功能。之後的新工作應由新的真實使用需求、課堂回饋或量測結果驅動，而不是繼續擴張架構。
