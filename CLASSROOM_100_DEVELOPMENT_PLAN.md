# Story Relay：100 人課堂可用版開發計畫

**整體狀態：完成（2026-09-04）。** A → B → C → D1 → D2 → D3 → D4 → D5 均已完成驗收。

## 目標

本專案的交付目標不是企業級多租戶平台，而是：

> 一個主持人可在單一課堂中讓約 100 名登入使用者穩定加入、分組、輪流投稿、查看故事，並由平台管理者進行必要維運。

所有後續開發以「100 人課堂可用」為範圍上限。除非實際需求出現，暫不加入企業級 SSO、複雜 RBAC、一次性邀請 token、多區域容錯、完整 SIEM、專用後端服務或大型壓測平台。

## 必須達成的產品能力

1. 約 100 名參與者可登入並加入同一活動。
2. 可依 group size 自動分組；未設定 group size 時可維持單一群組。
3. 每組可持續接力投稿，包含單人組 fallback。
4. 提名、志願、加權選人正常運作。
5. 主持人可進入活動、監控、停止、刪除自己主持的活動。
6. 每個帳號最多主持 3 個未刪除活動；停止中的活動仍計入。
7. 平台管理者可查看所有活動內容、刪除／恢復活動與管理平台管理者。
8. 已刪除活動保留 30 天後才可永久清除。
9. 跨組資料不可被一般參與者讀取或透過 Realtime 收到。
10. 使用者輸入的活動名稱、提示、顯示名稱與故事內容不執行 HTML/JS。

## 不做或延後

- 企業級組織帳號驗證與 domain allowlist。
- 複雜一次性邀請 token。
- 多區域 HA / DR。
- 專用 observability stack、SIEM 或 WAF。
- 大於 100 人的正式容量保證。
- 自動化滲透測試平台。
- 全面重寫既有 migration 歷史；只修正會影響乾淨部署或安全邊界的問題。
- 每輪秒數歸零後自動 expire / 換棒；目前 MVP 顯示倒數與「本輪時間已到」，由主持人既有 skip 機制處理逾時 round。

---

# Phase A — 供應鏈與部署基線

## A1 移除未使用 Axios

- 再次確認 application code 無 Axios import。
- 從 `story-relay/package.json` 移除 Axios。
- 同步更新 `pnpm-lock.yaml`。
- `pnpm audit --prod --audit-level high` 不應再因 Axios 回報 high advisory。

## A2 可重現安裝

- `pnpm-lock.yaml` 與 `package.json` 同步後，Pages workflow 改為 `pnpm install --frozen-lockfile`。
- Node 固定 20；pnpm 固定 10.4.1。
- Pages build 成功才算完成。

### 驗收

- GitHub Pages deployment 成功。
- production dependency audit 無未處理 high severity。
- frozen lockfile install 成功。

---

# Phase B — 高權限資料面最小加固

只處理真正具有全站或 destructive 權限的 RPC，不全面翻修所有函式。

## B1 平台管理者邊界

盤點並測試：

- `is_platform_admin`
- `add_platform_admin_by_email`
- `remove_platform_admin`
- `get_platform_activity_content`
- `get_platform_deleted_activities`
- `delete_platform_activity`
- `restore_platform_activity`
- `purge_expired_platform_activities`
- 會員 Email / identity 相關 RPC

要求：

- 一般 authenticated user 不可執行管理者操作。
- 平台管理者新增／移除必須由既有平台管理者觸發。
- 前端傳入的 user id / email 不可自行形成授權依據。
- `platform_admins` 與 identity table 不提供一般 client 直接寫入。

## B2 最小 audit log

新增不可由一般 client 直接寫入的管理操作紀錄，至少記錄：

- actor_id
- action
- target_type
- target_id
- created_at
- minimal metadata

第一版只記錄：

- admin_added
- admin_removed
- activity_deleted
- activity_restored
- expired_activity_purged

不做完整使用者行為追蹤。

## B3 SECURITY DEFINER

只優先加固上述高權限函式，以及：

- `stop_activity`
- `rename_activity`
- `join_activity_by_code`
- `submit_segment`

採 schema-qualified object name；若改為空 `search_path` 會增加 migration 風險，先逐函式驗證，不做全 repo 文字替換。

### 驗收

- 一般使用者無法取得平台管理資料或 destructive 權限。
- 管理員變更與刪除／恢復皆留下 audit record。
- 現有 UI 功能無 regression。

---

# Phase C — 100 人課堂安全與容量驗證

**狀態：完成（2026-09-04）**

## C1 五角色權限矩陣

**結果：PASS。** SQL cross-group RLS、Realtime cross-group isolation、host/platform-admin/participant mutation boundary 均完成動態驗證。

角色：

1. anon
2. Group A participant
3. Group B participant
4. activity host
5. platform admin

至少驗證：

- Group B 不可直接 SELECT Group A 的 story / segment / round / member。
- Group B 即使知道 Group A UUID，也不可讀取。
- Group B 不可收到 Group A Realtime payload。
- host 只能控制自己主持的活動。
- platform admin 可唯讀查看所有活動內容，但不因此成為 group member 或 current writer。
- participant 不可直接修改 writer_states、relay_rounds、segments 或 platform_admins。

## C2 100 人容量 smoke test

**結果：PASS。** 100 人 join → 20 組（group size 5）、100 次真實 segment submit + next-writer selection、20 組 host dashboard summary 均一致；Realtime probe 收到 200/200 events、0 duplicate，burst 期間最大 heartbeat drift 2 ms。

不是企業級 load test；只驗證典型課堂峰值：

- 100 個 join request 分批／短時間進入同一活動。
- group size = 5 時最後應形成約 20 組，沒有超額組員。
- 每組建立／啟動 story 狀態一致。
- 模擬至少 100 次 segment submit + next-writer selection。
- Realtime 不造成明顯重複事件或 UI freeze。
- host dashboard 可讀取所有 group summary。

若免費 Supabase quota 或 Realtime 限制成為瓶頸，先量測再決定是否升級方案，不預先加入複雜架構。

## C3 XSS smoke test

**結果：PASS。** activity name、prompt、display name、segment 四類輸入皆以純文字呈現；payload side effect 0、unexpected script nodes 0、unexpected img/svg nodes 0。Repo 靜態掃描亦未找到 `dangerouslySetInnerHTML` 或 `innerHTML` 使用。

用下列類型輸入活動名稱、prompt、display name、segment：

- `<script>alert(1)</script>`
- `<img src=x onerror=alert(1)>`
- HTML entity / quote payload

要求：只顯示為文字，不執行。

### 驗收

- 五角色權限矩陣全部符合預期。
- 100 人 join/submit smoke test 無資料錯亂。
- 使用者內容不執行 HTML/JS。

---

# Phase D — 完成課堂產品功能

完成安全基線後依序：

## D1 接力異常處理

**狀態：完成（2026-09-04）。**

**結果：PASS。** `skip_relay_round(uuid)` 僅允許活動主持人操作；被跳過的 active round 保留並標記為 `expired`，不增加 `times_written`；多人組排除被跳過 writer 後依既有 nomination / selection weight 選下一位，單人組沿用 fallback；寫入 activity events 供 dashboard / Realtime 更新。Rollback SQL 測試通過，且真實 UI smoke test 已確認 Round 6 → Round 7 並實際把 current writer 切換至另一位同名成員。

- current writer 離線／無法完成。
- 主持人可手動 expire / skip 當前 round。
- 保留歷史，不刪除既有 round／segment。
- 若有其他 eligible writer，依既有候選與權重機制選下一位。
- 若只有一位 eligible writer，沿用 single-writer fallback。
- 參與者離開後 future candidate pool 排除，但歷史保留。

每輪秒數的自動 timeout 不納入本次 100 人課堂 MVP；D4 處理的是活動整體 deadline 自動截止。每輪秒數本身仍在 StoryRoom 顯示倒數，逾時後顯示「本輪時間已到」。

## D2 完成故事頁

**狀態：完成（2026-09-04）。**

**結果：PASS。** `completed` 與 `closed/stopped` story 皆可唯讀查看完整內容；Writer 0 與所有提交段落清楚呈現。一般參與者仍受 group RLS 限制，host 僅讀自己活動，platform admin 走獨立的唯讀 content RPC。另修正 non-active 狀態文案，使完成與停止不再混淆。

- completed / stopped story 可讀。
- 清楚呈現 Writer 0 與所有提交段落。
- 參與者只能讀自己有權限的故事；host 可讀自己活動；platform admin 走 admin content RPC。

## D3 主持人 CSV

**狀態：完成（2026-09-04）。**

**結果：PASS。** 主持人專用 `get_teacher_activity_csv(uuid)` rollback test 通過；CSV 已以「每個活動一份」放在主持人區各活動卡片內。實際下載以試算表開啟後中文與欄位正常。CSV 不包含故事全文或平台登入 Email，並處理 UTF-8 BOM、CSV escaping 與試算表公式注入前綴。

只匯出該活動所需的課堂紀錄：

- participant identity
- group
- selected rounds
- segments written
- character count
- timestamps

預設不把故事全文放入成員統計 CSV。

## D4 自動截止

**狀態：完成（2026-09-04）。**

**結果：PASS。** `finalize_activity_deadline(uuid)` 為 idempotent finalizer；deadline 到期時將 active Activity 標記 `closed_reason='deadline'`、active Story 關閉、active Round 標記 `expired`，並留下 `activity_deadline_reached` event。既有 `join_activity_by_code`、`submit_segment`、`start_relay_round` 均已有 deadline boundary。Rollback SQL 測試 `CLASSROOM_100 D4 activity deadline passed`。

前端 StoryRoom 與主持人活動監控頁會在載入時執行 finalizer；已開啟頁面也會依 deadline 設定 timer，在時間到達時立即收斂狀態並轉唯讀。主持人監控頁會明確顯示「已截止」與截止原因。

本階段另完成每輪秒數的可視化。實際 UI smoke 發現 `activities.time_limit_seconds` 已正確保存，但既有 `relay_rounds.started_at` 為 NULL，造成前端無法計算倒數。已以 `20260904_d4_relay_round_started_at.sql` 將 `relay_rounds.started_at` 設為 `default now()`，並只回填仍為 open/writing 且 started_at 為 NULL 的 active Round；rollback test `CLASSROOM_100 D4 relay round started_at passed`。StoryRoom 目前會依 `started_at + time_limit_seconds` 每秒顯示本輪倒數，真實 UI smoke 已確認可見。

- deadline 到期後停止新 join／submit／round start。
- 對 active round 使用明確 expired 狀態。
- host dashboard 顯示截止原因。
- 每輪秒數可在「下一段」右上角顯示倒數；歸零後顯示「本輪時間已到」，不在本 MVP 自動換棒。

同時完成入口流程簡化：首頁「加入活動」區塊直接輸入活動代碼並進入 StoryRoom；獨立 `#/join` route 與 `JoinActivity.tsx` 已移除。

## D5 最終課堂驗收

**狀態：完成（2026-09-04）。**

**結果：PASS。** rollback-only 測試 `classroom100_phase_d5_end_to_end.sql` 實際透過目前 RPC 走完核心生命週期，結果為 `CLASSROOM_100 D5 end-to-end acceptance passed`。測試涵蓋：主持人建立活動、參與者加入、啟動 relay round、投稿並建立下一輪、主持人 skip、停止活動、主持人 CSV、平台管理者 soft delete 與 restore，並驗證新 Round `started_at` 不再為 NULL。測試結束全部 rollback，不留下測試資料。

100 人 join / group capacity / Realtime burst 不在 D5 重跑，因 C2 已獨立完成 100 人容量驗證；D5 用於確認 D1–D4 後整體產品生命週期無 regression。

---

# 執行順序與停止條件

固定順序：

`A → B → C → D1 → D2 → D3 → D4 → D5`

**目前全部完成。** 若未來新增功能，應另開新的 development phase / backlog，不再把新需求回填為本次 100 人課堂 MVP 的未完成項目。

專案已達到以下「100 人課堂可用版」完成條件：

- 100 人容量 smoke test 通過。
- 跨組 RLS / Realtime 隔離通過。
- 高權限 RPC authorization 通過。
- 故事內容 XSS smoke test 通過。
- 主持人能處理卡住的 round。
- 完整活動流程可從建立走到完成／停止／匯出／刪除／恢復。