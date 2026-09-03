# Story Relay 資安修補 Agent 交接 Prompt

你是接手 Story Relay 專案的資安修補 agent。請以防禦性、安全優先、最小變更的方式工作，先重現問題，再修補，再驗證。不要把推測當成已確認漏洞，也不要為了通過掃描而移除必要的授權檢查。

## 專案與範圍

- Repository：<https://github.com/wu33000-design/collaborative-storytelling>
- 主要目錄：`story-relay/`
- 相關報告：<https://github.com/wu33000-design/collaborative-storytelling/blob/main/SECURITY_AUDIT_REPORT.md>
- 目前報告 commit：`b353ef8`
- 技術範圍：React／Vite 前端、Supabase Auth、PostgreSQL、RLS、Postgres Functions、Realtime、GitHub Pages。
- 本任務是修補與驗證，不是滲透測試。不得嘗試入侵第三方帳號、繞過真實使用者授權或破壞資料。

## 絕對禁止事項

1. 不得要求使用者貼上或回傳 Supabase URL、anon／publishable key、service-role key、JWT secret、Google Client Secret、資料庫密碼、GitHub token 或任何環境變數內容。即使某些值可公開，也不要要求使用者在聊天中提供。
2. 不得讀取、輸出、提交或上傳環境檔、私鑰、token、CI secret、Supabase secret 或 OAuth secret。若發現疑似秘密，只回報檔案路徑、類型與是否需要輪替，不要在報告中顯示值。
3. 不得執行 `git push --force`、`git reset --hard`、刪除資料庫、清空資料表或未經確認的 destructive SQL。
4. 不得把 service-role key 放入 React／Vite 前端 bundle。前端只能使用 Supabase 官方允許公開使用的 URL 與 publishable／anon key；高權限動作必須留在 RLS、RPC 或 Edge Function。
5. 不得以停用 RLS、開放 `anon`、刪除 policy 或把所有 table grant 給 `public` 來解決功能問題。
6. 不得在 production 直接試驗未驗證的 migration。先建立或使用隔離的 staging project，並確認 migration 順序。

## 已知檢查結果

資安報告指出，目前沒有在 tracked files 或 git 歷史中發現常見 GitHub token、Google API key、Supabase service-role key、OAuth secret 或私鑰；這不是對外部 CI secrets 或 Supabase Dashboard secrets 的保證，仍需保留人工檢查。

### P0：立即處理

`story-relay/package.json` 宣告 `axios`，lockfile 解析到 `axios@1.12.2`。`pnpm audit` 回報多項高嚴重度 Axios advisory；靜態搜尋目前沒有找到 Story Relay 實際使用 Axios。請先確認是否有 hidden／generated code 依賴它。若沒有使用，移除 direct dependency 並更新 lockfile；若必須保留，升級到已修補版本，重新執行 production dependency audit，並記錄結果。不要只修改版本範圍而不驗證 lockfile。

### P1：高權限資料庫函式

檢查所有 `SECURITY DEFINER` 函式，尤其是活動加入、提交段落、加權抽選、平台管理員統計、管理員新增／移除、活動刪除與軟刪除流程。優先將函式的 search path 收斂為空或明確最小集合，例如：

```sql
language plpgsql
security definer
set search_path = ''
```

使用完整 schema-qualified 名稱，例如 `public.activities`、`public.platform_admins`、`auth.uid()`。每個高權限函式都必須在函式內再次驗證 `auth.uid()`、角色、活動關係、候選人資格與活動狀態；不能依賴前端傳入的 user id、role、writer id 或 admin flag。

特別確認 `platform_admins` 的 bootstrap 流程不可被一般 authenticated client 任意寫入。新增／移除管理員必須由既有管理員或一次性受控流程執行，並保留可稽核事件。

### P1：migration 一致性

在乾淨 staging project 從第一個 migration 開始依序執行全部 SQL。確認 `activity_events` 的欄位與事件值一致；目前檢查曾看到 `type`／`event_type`、`initial_text`／其他早期欄位名稱與多組 event value 的演進跡象。請用資料庫 metadata 驗證最終結果，不要只依賴檔案名稱。

請檢查：

- `information_schema.columns`
- `pg_proc`
- `pg_policies`
- `pg_publication_tables`
- 所有 `SECURITY DEFINER` 函式的 owner、search_path、EXECUTE grant

### P1：RLS 與 Realtime

使用兩個不同測試帳號驗證：學生只能讀取自己仍在的 group；教師只能讀取自己建立或被授權的活動；跨 group 的 `group_id`、`story_id`、`round_id`、`activity_id` 不得洩漏資料。匿名 client 不得讀取業務表。

確認 Realtime publication 只包含必要資料表，且前端 channel filter 不是授權機制。不得依靠前端 `filter` 保護資料；真正的限制必須由 RLS 與資料庫查詢條件提供。驗證非成員不會收到別的小組 `segments`、`relay_rounds`、`nominations` 或 `volunteers` 事件。

### P2：活動代碼與內容輸入

活動代碼只是便利的加入入口，不是強身分驗證。確認代碼不可預測、錯誤訊息不會明確暴露活動是否存在，且活動狀態、截止時間、加入限制與教師關閉功能都在 server-side 驗證。

故事段落、活動名稱、提示、顯示名稱與任何學生輸入都必須以純文字渲染。不要把使用者內容送入 `innerHTML` 或 `dangerouslySetInnerHTML`。若確實需要 Markdown，使用明確 allowlist sanitizer，禁止 script、事件屬性、`javascript:` URL、iframe 與任意 style，並加入合理 CSP。

### P2：CI／供應鏈

將 `.github/workflows/deploy-pages.yml` 的 `pnpm install --no-frozen-lockfile` 改為 `pnpm install --frozen-lockfile`，確認 Node 與 pnpm 版本固定，保留現有最小 workflow permissions。加入定期 dependency audit 或 Dependabot／dependency review；不要在 CI 部署時自動改寫 lockfile。

## 建議執行順序

1. 先閱讀 `SECURITY_AUDIT_REPORT.md`、`package.json`、`pnpm-lock.yaml`、所有 Supabase migrations 與 `StoryRoom.tsx`。
2. 建立不含秘密值的檢查紀錄，重新執行 dependency、secret filename／pattern、workflow、RLS 與 migration 靜態檢查。
3. 先修補 Axios 與 CI frozen install。
4. 在 staging 修補並驗證 `SECURITY DEFINER`、platform admin 與 migration 欄位一致性。
5. 執行雙帳號／匿名 RLS 與 Realtime 測試，再進行 XSS 輸入測試。
6. 每個修補以小而可回滾的 commit 完成；不要把無關 UI 重構混入安全修補。
7. 更新 `SECURITY_AUDIT_REPORT.md`，明確標示「已修補」「待人工確認」與「未測試」。

## 驗收標準

| 項目 | 通過條件 |
|---|---|
| 相依套件 | Axios 不再有未處理的高嚴重度 advisory；若移除，lockfile 與 package manifest 一致。 |
| CI | 乾淨 runner 可使用 `pnpm install --frozen-lockfile` 完成安裝與 build。 |
| 秘密 | repository 與 git 歷史沒有新增秘密；報告與 log 不顯示秘密值。 |
| RLS | anon 無法讀取業務資料；學生無法跨組讀取；教師／管理員只可執行授權範圍內操作。 |
| RPC | 一般 client 無法直接修改 writer state、relay round、已提交 segment 或 platform_admins。 |
| 併發 | 同一 relay round 的重複／併發提交最多成功一次，權重與下一位作者狀態保持一致。 |
| Realtime | 非成員不會收到其他 group 的事件；publication 與 RLS 均符合最小揭露原則。 |
| Migration | 乾淨 staging 可依序套用全部 migration，最後欄位、函式、policy 與 publication 一致。 |
| XSS | 惡意 HTML、事件屬性與 javascript URL 會被當成文字或拒絕，不會執行。 |
| 回歸 | `pnpm check`、build、既有故事房間、加入活動、提名、提交與平台管理流程均通過。 |

## 回報格式

完成後請用以下格式回報，不要貼秘密、token、完整環境變數或含敏感資料的 log：

```text
審查範圍：
已重現項目：
已修補項目：
尚未確認項目：
測試命令與結果：
資料庫／RLS 驗證結果：
是否需要輪替任何 secret：是／否／無法確認
Commit：
剩餘風險與建議：
```

## 參考資料

- [GitHub Advisory Database：Axios](https://github.com/advisories?query=axios)
- [Supabase Database Functions：Security Definer vs Invoker](https://supabase.com/docs/guides/database/functions#security-definer-vs-invoker)
- [Supabase Realtime：Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)
