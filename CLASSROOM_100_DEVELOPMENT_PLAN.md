# Story Relay：100 人課堂可用版開發計畫

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

自動 timeout 不在此階段做，保留給 D4。

## D2 完成故事頁

- completed / stopped story 可讀。
- 清楚呈現 Writer 0 與所有提交段落。
- 參與者只能讀自己有權限的故事；host 可讀自己活動；platform admin 走 admin content RPC。

## D3 主持人 CSV

只匯出該活動所需的課堂紀錄：

- participant identity
- group
- selected rounds
- segments written
- character count
- timestamps

預設不把故事全文放入成員統計 CSV。

## D4 自動截止

- deadline 到期後停止新 join／submit。
- 對 active round 使用明確 expired 狀態。
- host dashboard 顯示截止原因。

## D5 最終課堂驗收

用一個完整活動做 end-to-end：

create → 100 joins → groups → relay → nomination → submissions → host intervention → completion/stop → CSV → delete → admin restore。

---

# 執行順序與停止條件

固定順序：

`A → B → C → D1 → D2 → D3 → D4 → D5`

若某階段發現 blocking security/data-integrity bug，先修 bug 再前進；純 UI polish 不阻擋後續階段。

專案達到以下條件即可視為「100 人課堂可用版」完成，不再繼續擴張架構：

- 100 人容量 smoke test 通過。
- 跨組 RLS / Realtime 隔離通過。
- 高權限 RPC authorization 通過。
- 故事內容 XSS smoke test 通過。
- 主持人能處理卡住的 round。
- 完整活動流程可從建立走到完成／停止／匯出／刪除／恢復。
