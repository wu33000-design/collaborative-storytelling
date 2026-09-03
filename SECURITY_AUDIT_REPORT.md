# collaborative-storytelling 公開儲存庫資安檢查報告

**審查目標：** `wu33000-design/collaborative-storytelling`
**審查時間：** 2026-09-03
**審查性質：** 防禦性靜態檢查，不包含滲透測試、帳號登入、資料庫破壞性操作或秘密值驗證。
**目前驗證 HEAD：** `1f14e9c`（CLASSROOM_100 Phase A 依賴修補與 Phase B migration）；本報告仍不代表實際 Supabase staging 已完成資料庫驗證。

## 執行摘要

目前沒有在公開檔案或完整 git 歷史掃描中發現明顯的 API key、OAuth Client Secret、Supabase service-role key、私鑰或 GitHub token。GitHub Pages workflow 也已設定最小化的 `contents: read`、`pages: write` 與 `id-token: write` 權限，這部分沒有發現明顯的過度授權。

不過，檢查發現數項相依套件與 Supabase／資料庫 migration 有關的高影響設計風險。Axios 已移除，nanoid 已升級至 5.1.16；Express 已升級至 5.2.1、Recharts 至 3.10.1、Streamdown 至 2.6.0。重新執行 production audit 後目前已無 high，剩餘 1 項 moderate advisory，仍需在後續依賴更新時持續追蹤。[1] [4]

此外，數個 `SECURITY DEFINER` 函式使用 `set search_path = public`，而非更嚴格的空 search path；這會增加函式解析未限定名稱時的風險，尤其是未來有人新增同名物件或修改函式內容時。[2] 管理員 RPC 也依賴 `platform_admins` 表與 `auth.uid()`，必須持續確認只有可信 migration／伺服器流程能寫入管理員資料。

## 風險總覽

| 編號 | 風險 | 等級 | 狀態 | 主要位置 |
|---|---|---:|---|---|
| R-01 | production dependency audit 尚有 1 項 moderate advisory，無 high／critical | 中 | 已降低，持續追蹤 | `story-relay/package.json`、`pnpm-lock.yaml` |
| R-02 | 多個 `SECURITY DEFINER` 函式使用寬鬆的 `search_path = public` | 中 | 待加固 | `story-relay/supabase/migrations/*.sql` |
| R-03 | 平台管理員權限屬於高影響資料面，需確認 bootstrap 與寫入邊界 | 高 | 需人工確認 | `platform_admins`、平台管理 RPC migrations |
| R-04 | 公開活動代碼與公開頁面可能造成活動探索／內容暴露 | 中 | 設計風險 | `join_activity_by_code`、前端活動讀取流程 |
| R-05 | Realtime 訂閱擴大了資料即時曝光面，必須依賴正確 RLS 與 publication 管理 | 中 | 需測試 | `20260903_enable_story_room_realtime.sql`、`StoryRoom.tsx` |
| R-06 | 部分資料庫 migration 序列存在欄位／事件命名不一致跡象，可能造成安全政策失效或部署中斷 | 中 | 待驗證 | `activity_events`、`initial_text`、多個後續 migrations |
| R-07 | workflow 已改用 frozen install，但 pnpm workspace 設定與部分 CI 依賴仍需確認 | 低至中 | 部分修補 | `.github/workflows/deploy-pages.yml:40`、`story-relay/pnpm-workspace.yaml` |
| R-08 | 前端存在 `dangerouslySetInnerHTML`／`innerHTML`，目前內容看似靜態，但未來若混入使用者內容會變成 DOM XSS 入口 | 中 | 條件性風險 | `chart.tsx`、根目錄 `app.js` |

## 詳細發現

### R-01：production dependency audit

Phase A 已確認應用程式沒有使用 Axios，並已移除 direct dependency；nanoid 已升級至 5.1.16。為移除 Express／Recharts／Streamdown 的舊版依賴來源，已將 Express 升級至 5.2.1、Recharts 升級至 3.10.1、Streamdown 升級至 2.6.0，並修正 Express 5 的 SPA fallback 路由與 Recharts 3 chart adapter 型別。

目前 `pnpm audit --prod --audit-level high` 已無 high 或 critical，只有 1 項 moderate advisory。這不代表風險為零；後續仍應在依賴升級時檢查 `dompurify`、`mermaid` 與其他 production transitive packages 的版本與可達性。

**優先處理：中。** CLASSROOM_100 的 high／critical 供應鏈門檻已達成，但仍保留定期 audit 與依賴更新工作。

### R-02：SECURITY DEFINER 函式的 search_path 加固

多個管理與流程函式使用 `SECURITY DEFINER`。其中一部分明確寫成 `set search_path = public`，例如活動加入、管理員統計、軟刪除與平台管理流程。Supabase 官方安全建議是對 `SECURITY DEFINER` 函式設定明確且最小化的 search path，並使用完整 schema-qualified 名稱；使用空 search path 可降低名稱解析被影響的機會。[2]

建議將函式統一改為：

```sql
language plpgsql
security definer
set search_path = ''
```

並把所有非內建物件改為完整名稱，例如 `public.activities`、`public.platform_admins`、`auth.uid()`。對 `now()`、`gen_random_uuid()`、`hashtextextended()` 等函式，應確認其 schema 解析方式與當前 Supabase PostgreSQL 版本相容。修改後必須在 staging project 執行完整 migration 與 RPC 測試，不宜直接在 production 以文字取代方式修改。

**優先處理：中至高。** 這是權限提升函式的縱深防禦問題；若同時存在可被低權限使用者建立或控制的 shadow object，風險會提高。

### R-03：平台管理員資料面需要明確 bootstrap 邊界

平台管理頁面提供查詢統計、管理活動、加入／移除管理員等高影響功能。資料庫函式大多會以 `auth.uid()` 查詢 `platform_admins`，並對該表撤銷 `anon` 與 `authenticated` 的直接權限，這是正確方向；但第一位平台管理員如何建立、誰能執行新增管理員的 RPC，以及 migration 是否會在空表狀態下造成管理介面不可用，必須明確記錄。

建議採用一次性、人工執行且不放在公開前端的 bootstrap 流程。新增／移除管理員的 RPC 必須檢查目前使用者是既有管理員，並在同一 transaction 內寫入 audit event。任何「以 email 查詢帳號再授權」流程都應避免相信前端傳入的 user id 或 email；應由已驗證的伺服器端流程查詢 `auth.users` 或對應 identity table。

**優先處理：高。** 管理員權限一旦被繞過，影響範圍可能涵蓋全站活動與成員資料。

### R-04：活動代碼不是機密驗證機制

`join_activity_by_code` 以活動代碼加入活動。這種代碼適合做便利的課堂加入入口，但不應被視為強身分驗證。若活動代碼出現在截圖、投影畫面、瀏覽器歷史或公開分享頁面，任何取得代碼的人都可能嘗試加入。

建議活動代碼使用足夠長度與不可預測的隨機值，並搭配活動狀態、截止時間、加入限制、教師可關閉活動，以及必要時的邀請連結／一次性 token。錯誤訊息不要區分「活動不存在」與「活動存在但已關閉」，以減少活動枚舉。

**優先處理：中。** 這是產品授權邊界，而非傳統 SQL injection；需要依課堂使用情境決定安全強度。

### R-05：Realtime 與 RLS 的資料曝光面

`StoryRoom.tsx` 對 `segments`、`relay_rounds`、`stories`、`activities`、`group_members`、`nominations` 與 `volunteers` 建立 Realtime 訂閱。這能改善協作體驗，但也代表資料表變更會被即時推送到符合訂閱條件的客戶端。Supabase Realtime 的安全性仍依賴資料表 RLS、publication 設定與查詢條件，不應把前端 filter 當成授權機制。[3]

建議用兩個測試帳號驗證：帳號 A 只能看到自己所屬 group；帳號 B 不應因知道 story id、group id 或 round id 就收到 A 的活動事件。對不需要即時傳送的敏感表不要加入 publication；活動管理事件也應只推送必要欄位，避免把內部 payload 或 email 暴露給學生。

**優先處理：中。** 在沒有完成雙帳號與匿名請求測試前，不應宣稱 Realtime 權限已安全。

### R-06：Migration 欄位與事件命名不一致

靜態檢查發現 migration 序列中同時出現 `event_type` 與 `type` 的引用跡象，也看到不同事件值如 `student_joined`、`segment_submitted`、`writer_selected` 等。另有早期 schema 使用 `initial_story_text`、後續 migration 使用 `initial_text` 的版本演進跡象。這類不一致可能導致 migration 在特定順序下失敗，或讓 audit／RLS／dashboard 查詢沒有涵蓋所有事件。

這項發現目前標記為「待驗證」，因為僅憑公開檔案無法確定所有 migration 是否已在同一個 Supabase project 依正確順序執行。應在乾淨的 staging project 從第一個 migration 開始完整套用，並用 `information_schema.columns`、`pg_proc` 與 `pg_policies` 檢查最後 schema；不要只在現有 production database 執行最後一個 migration。

**優先處理：中。** Migration 失敗本身是可用性問題，但若欄位不一致導致 RLS policy 或管理 audit 沒有寫入，會升級為資安問題。

### R-07：GitHub Actions 使用非凍結安裝

Pages workflow 在 `story-relay` 目錄執行 `pnpm install --no-frozen-lockfile`。這允許 CI 在 lockfile 與 package manifest 不一致時重新解析依賴，降低每次部署的可重現性，也讓供應鏈變更更難被審查。

建議改成 `pnpm install --frozen-lockfile`，並使用明確的 Node／pnpm 版本、dependency review、Dependabot 或定期 `pnpm audit`。若 workflow 需要更新 lockfile，應在受控的開發提交中完成，而不是在部署時動態更新。

**優先處理：低至中。** workflow 已有合理的最小 permissions，這是加固建議而非目前已確認的可利用漏洞。

### R-08：HTML 注入與未來使用者內容

根目錄教學網站使用 `innerHTML` 建立由 repository 內固定內容組成的頁面；UI 元件中也存在 `dangerouslySetInnerHTML`。目前如果輸入只來自可信的靜態檔案，風險有限；但 Story Relay 的產品核心是學生提交故事段落。若未來把學生段落、活動名稱、教師提示或 profile 欄位直接傳給 `innerHTML`／`dangerouslySetInnerHTML`，就會形成儲存型 XSS。

建議 React 預設以文字節點渲染使用者內容，不使用 raw HTML。若確實要支援 Markdown，先以嚴格 allowlist sanitizer 處理，禁止 script、事件屬性、javascript URL、iframe 與任意 style；同時加入合理的 Content Security Policy。故事內容在資料庫中也應限制長度並記錄提交者，不要把 HTML 當成內容格式。

**優先處理：中。** 目前是條件性風險，但與產品未來功能高度相關，應在接入真實故事提交前修正。

## 未發現或未確認的項目

本次掃描沒有在 tracked files 或 git 歷史中找到常見格式的 GitHub token、Google API key、Supabase service-role key、OAuth secret 或私鑰。這不等同於保證沒有秘密：加密或非標準格式的秘密、已撤銷的秘密、外部 CI secrets 與 Supabase Dashboard 內的 secrets 無法由公開 repository 靜態掃描確認。

目前也沒有執行登入後測試、RLS 實際 query 測試、Supabase schema 連線測試、GitHub Pages 產出站點的動態 XSS 測試或正式 penetration test。因此 R-03、R-05、R-06 需要在 staging 環境完成驗證後才能關閉。

## 建議修補順序

第一階段應立即移除未使用的 Axios 或升級至已修補版本，將 CI 改成 frozen install，並在 pull request 中加入 dependency audit。第二階段應統一所有 `SECURITY DEFINER` 函式的 search path、完整檢查管理員 bootstrap 與高權限 RPC，並在乾淨 Supabase staging project 重跑所有 migrations。第三階段應執行雙帳號 RLS／Realtime 測試、活動代碼濫用測試與故事內容 XSS 測試。完成後再考慮開放更多平台管理與即時功能。

## 建議驗收標準

| 項目 | 通過條件 |
|---|---|
| 依賴 | `pnpm audit --prod --audit-level high` 不再回報未使用的高嚴重度 Axios advisory。 |
| CI | `pnpm install --frozen-lockfile` 可在乾淨 runner 成功完成；workflow permissions 維持最小化。 |
| RLS | 未登入者無法讀取活動；學生只能讀取自己小組；跨小組 id、story id、round id 查詢均不洩漏資料。 |
| RPC | 一般使用者不能直接修改 writer state、relay round、已提交 segment 或 platform_admins。 |
| Realtime | 非成員不會收到目標小組的即時事件；只公開必要欄位。 |
| Migration | 乾淨 staging project 可從頭到尾套用所有 migration，且欄位、函式與 policies 名稱一致。 |
| XSS | 故事內容、活動名稱、提示與顯示名稱以文字方式渲染；惡意 HTML 不會執行。 |

## 目前驗證紀錄

截至 CLASSROOM_100 Phase A 後續修補：`pnpm install --frozen-lockfile`、`pnpm check` 與 `pnpm build` 已成功；`pnpm audit --prod --audit-level high` 已無 high／critical，結果為 1 項 moderate、5 項 low。Phase A 的高嚴重度依賴門檻已達成；moderate／low 仍需持續追蹤。

Phase C 已新增唯讀 metadata smoke test：`story-relay/supabase/tests/classroom100_phase_c_metadata.sql`。它會檢查業務表 RLS、敏感表直接寫入權限、Realtime publication allowlist 與高影響 SECURITY DEFINER 函式的空 `search_path`。目前尚未在實際 Supabase staging project 執行，因此五角色 RLS、Realtime payload 隔離與 100 人容量仍屬未驗證項目。

## References

[1] [GitHub Advisory Database：Axios advisories](https://github.com/advisories?query=axios)

[2] [Supabase Database Functions：Security considerations](https://supabase.com/docs/guides/database/functions#security-definer-vs-invoker)

[3] [Supabase Realtime：Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)

[4] [pnpm 10 Settings：overrides](https://pnpm.io/10.x/settings#overrides)
