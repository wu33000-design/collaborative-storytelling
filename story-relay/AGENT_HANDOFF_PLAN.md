# Story Relay Agent 開發交接計畫

**文件版本：** v1.0  
**文件目的：** 提供下一位 agent 一份可直接執行的產品與工程交接規格。  
**工作語言：** 繁體中文  
**目前專案：** `/home/ubuntu/story-relay`  
**目前前端狀態：** React 19 + Vite + Tailwind 4 的靜態 MVP  ️

---

## 1. 交接摘要

Story Relay 是一個讓學生小組以順序接力方式共同創作故事的平台。每位學生負責一個段落，完成後由目前作者提名候選人，系統再透過加權隨機選擇決定下一位作者。等待越久的學生，選擇權重越高；被選中的學生在完成後重設權重。產品的核心是「故事接下來會發生什麼」，不是排名、分數或競爭。

目前已有一個可互動的前端工作台，使用前端示範資料呈現故事、進度、目前作者、提名與段落提交流程。下一階段的任務是把示範資料替換為真實身分驗證、資料庫與安全的伺服器端接力流程。

> **交付目標：** 在不破壞現有「紙上接力」視覺風格的前提下，將靜態原型升級為可供教師與學生實際使用的 MVP。

---

## 2. 已確認的產品範圍

### 2.1 使用者角色

| 角色 | 能力 | 限制 |
|---|---|---|
| 教師 | 建立活動、設定故事參數、查看小組進度、查看完成故事、手動結束活動 | 不得修改學生已提交的段落 |
| 學生 | 加入活動、閱讀故事、自願成為下一棒、提名下一位作者、提交指定段落、查看小組進度 | 不得修改過往段落或其他學生內容 |
| Writer 0 | 虛擬故事種子，不是實際使用者 | 可由教師輸入、系統產生或留白 |

### 2.2 MVP 必備功能

MVP 必須包含教師建立活動、學生加入活動、小組建立、故事顯示、段落提交、提名流程、加權選擇演算法、進度儀表板與完成故事頁。

MVP 暫不包含通知、Email、Push、SMS、提醒、連續簽到、積分、XP、徽章、排行榜、競賽排名、AI 自動續寫、AI 改寫、教師修改學生作品、LMS 整合與 PDF 匯出。

### 2.3 活動完成條件

活動在以下任一條件成立時完成：所需段落數已達成、教師手動關閉活動，或截止時間已到。完成後必須停止新的段落提交，並保留完整故事、貢獻者清單與實際寫作順序。

---

## 3. 技術決策

### 3.1 首選後端方案

本計畫採用以下後端組合：

```text
Supabase Auth
Supabase PostgreSQL
PostgreSQL Row Level Security
PostgreSQL RPC 或 Supabase Edge Function
React + @supabase/supabase-js
```

Supabase Free Plan 目前包含 PostgreSQL、Auth、Social OAuth providers、Realtime 與 REST API；官方方案頁列出 500 MB 資料庫、50,000 月活躍使用者、1 GB 檔案儲存與 5 GB 流量等免費額度。[1] 這足以支援 Story Relay 的早期測試與小型校園活動，但免費專案閒置後可能暫停，正式使用前需要確認專案狀態。[1]

### 3.2 為什麼不先維護獨立 Node API

Story Relay 的初期流量與即時性需求不高。若一開始同時維護 Express、伺服器部署、資料庫、OAuth callback、WebSocket 與背景工作，會增加維護面積。Supabase 可以先提供託管資料庫、驗證、RLS、API 與函式執行環境，降低 MVP 維護成本。

若目前 Manus 專案必須使用 `web-db-user` full-stack 模板，則應在開工前做一次架構選擇：

| 選項 | 適用情境 | 注意事項 |
|---|---|---|
| A. Supabase 外部後端 | 優先追求免費、快速與低維護 | 前端管理 Supabase client；必須嚴格設定 RLS 與 secrets。 |
| B. Manus full-stack 原生資料層 | 優先追求單一平台與 tRPC 整合 | 使用模板的 `drizzle/schema.ts`、`server/db.ts`、`server/routers.ts`；不要再同時導入 Supabase。 |

**本交接文件預設採用選項 A。不要同時建立兩套資料庫或兩套驗證系統。**

### 3.3 Google OAuth 費用與範圍

Supabase Free Plan 已包含 Social OAuth providers；Google 登入本身通常不需要額外付費。Google OAuth Client ID 的建立與基本登入 scopes 通常不會產生帳單，但若未來使用 Calendar、Drive、Gmail 等 Google API，則應另行檢查個別服務的配額、驗證與費用規則。[2] [3]

Story Relay 第一版只要求以下 scopes：

```text
openid
email
profile
```

不要一開始要求 Google Calendar、Drive、Gmail 或其他與登入無關的權限。Supabase 官方 Google 登入文件要求先建立 Google Cloud project、OAuth consent screen、Web application client ID，並設定 authorized origins 與 Supabase callback URL。[2]

---

## 4. 現有前端與不可破壞事項

目前主要檔案如下：

| 檔案 | 現況 | 後端接入時的處理方式 |
|---|---|---|
| `client/src/pages/Home.tsx` | 故事工作台與示範互動集中於此 | 保留版面與互動語言，將示範資料替換成查詢與 mutation。 |
| `client/src/index.css` | 「紙上接力」設計系統 | 不改變暖紙白、墨綠、Relay Vermilion 與紙張肌理方向。 |
| `client/src/App.tsx` | 現有路由與 ThemeProvider | 後續加入登入、加入活動、教師管理與完成故事路由。 |
| `client/src/components/ui/*` | shadcn/ui 元件 | 優先重用，不重建相同基礎元件。 |
| `ideas.md` | 視覺設計決策 | 所有新增頁面需遵守此文件。 |
| `todo.md` | 尚待完成項目 | 每完成一個重要模組就更新核取狀態。 |

現有 UI 已包含以下前端示範流程：活動標頭、故事段落、進度儀表板、目前寫作者、志願登記、提名候選人、活動說明分頁、段落提交抽屜與提交後的畫面更新。

後端化時，必須保留「故事內容優先、進度透明、不呈現競爭分數」的產品語言。不要加入排行榜、作者分數、XP、徽章或通知入口。

---

## 5. 資料模型

### 5.1 建議資料表

| 資料表 | 重要欄位 | 設計說明 |
|---|---|---|
| `profiles` | `id`, `display_name`, `avatar_url`, `created_at` | 對應 Supabase Auth user；不要重複儲存密碼。 |
| `activities` | `id`, `teacher_id`, `code`, `name`, `prompt`, `initial_text`, `group_size`, `time_limit_seconds`, `min_words`, `max_words`, `required_segments`, `deadline`, `status` | 教師建立的活動設定。 |
| `groups` | `id`, `activity_id`, `name`, `created_at` | 活動中的小組。 |
| `group_members` | `group_id`, `user_id`, `role`, `joined_at`, `left_at` | `role` 至少包含 `teacher` 與 `student`。 |
| `stories` | `id`, `group_id`, `title`, `prompt`, `required_segments`, `status`, `completed_at` | 每個小組一個故事。 |
| `segments` | `id`, `story_id`, `sequence_no`, `author_id`, `content`, `word_count`, `submitted_at` | **append-only**；不得覆寫已提交內容。 |
| `writer_states` | `group_id`, `user_id`, `times_written`, `waiting_rounds`, `selection_weight`, `updated_at` | 每位學生目前的公平性狀態。 |
| `relay_rounds` | `id`, `story_id`, `round_no`, `current_writer_id`, `status`, `started_at`, `expires_at`, `completed_at` | 每個接力輪次的狀態。 |
| `nominations` | `id`, `round_id`, `nominated_by`, `candidate_id`, `created_at` | 目前作者對下一棒的提名。 |
| `volunteers` | `round_id`, `user_id`, `created_at` | 學生的「我想接著寫」登記；可合併到 nominations，但建議獨立保存意圖。 |
| `activity_events` | `id`, `activity_id`, `group_id`, `type`, `actor_id`, `payload`, `created_at` | 供進度同步、稽核與未來事件流使用。 |

### 5.2 必須建立的約束與索引

1. `activities.code` 必須唯一，並使用不可猜測或足夠長度的活動代碼。
2. `group_members(group_id, user_id)` 必須唯一，避免同一學生重複加入同一小組。
3. `segments(story_id, sequence_no)` 必須唯一，避免重複段落序號。
4. `writer_states(group_id, user_id)` 必須唯一。
5. `relay_rounds(story_id, round_no)` 必須唯一。
6. `nominations(round_id, candidate_id)` 必須唯一。
7. 為 `activities.status`、`groups.activity_id`、`segments.story_id`、`relay_rounds.story_id` 建立索引。
8. 已提交段落不可使用一般 update endpoint 修改；若未來要支援修訂，另建版本表，不覆寫原文。

---

## 6. 權限與安全設計

### 6.1 RLS 原則

所有公開可查詢的資料也必須經過活動與小組成員關係驗證。學生只能讀取自己所在活動與小組的資料；教師只能管理自己建立的活動；學生不可修改活動設定、過往段落、其他學生資料或 writer state。

### 6.2 對應權限

| 操作 | 教師 | 小組學生 | 未登入使用者 |
|---|---:|---:|---:|
| 讀取活動基本資訊 | 建立者可讀 | 以活動代碼加入前可讀有限資訊 | 只能讀取加入所需資訊 |
| 讀取小組故事 | 可 | 可 | 不可 |
| 讀取小組進度 | 可 | 可 | 不可 |
| 建立活動 | 可 | 不可 | 不可 |
| 加入活動 | 不適用 | 可 | 登入後可 |
| 提名候選人 | 不適用 | 僅目前作者可 | 不可 |
| 登記志願 | 不適用 | 合資格學生可 | 不可 |
| 提交段落 | 不適用 | 僅目前作者可 | 不可 |
| 修改已提交段落 | 不可 | 不可 | 不可 |
| 手動結束活動 | 建立者可 | 不可 | 不可 |

### 6.3 Secrets

Google Client Secret、Supabase service role key 與其他伺服器秘密不可進入前端 bundle、Git repository、Markdown 交接文件或 `.env` commit。前端只可使用可公開的 Supabase URL 與 anon／publishable key；所有高權限操作放在資料庫安全函式或 Edge Function。

---

## 7. 核心接力演算法

### 7.1 初始狀態

所有合資格學生初始值如下：

```text
times_written = 0
waiting_rounds = 0
selection_weight = 1
```

### 7.2 每輪提交與抽選

當目前作者提交成功後：

1. 驗證目前使用者確實是 `relay_rounds.current_writer_id`。
2. 驗證活動狀態為 `active`，且尚未超過 `expires_at` 或活動 deadline。
3. 驗證段落長度在 `min_words` 與 `max_words` 之間。
4. 將段落寫入 `segments`。
5. 對所有未被選中的合資格學生執行 `waiting_rounds += 1` 與 `selection_weight += 1`。
6. 建立候選池：若本輪有提名，預設只從提名候選人中抽選；若沒有提名，則使用全部合資格學生。
7. 排除目前作者、已離開小組者、已被停用者與不符合活動規則者。
8. 依 `selection_weight` 加權隨機選出下一位作者。
9. 被選中的學生執行 `times_written += 1`、`waiting_rounds = 0`、`selection_weight = 1`。
10. 建立下一個 `relay_round`，更新 `current_writer_id`。
11. 若達到 `required_segments`，將故事與活動標記為 `completed`，不建立下一輪。

### 7.3 隨機抽選要求

加權抽選必須在伺服器端或 PostgreSQL 內執行，不能信任前端傳入的權重或抽選結果。建議使用資料庫交易與 row-level lock，鎖定目前故事或接力輪次，避免同時提交造成競態條件。

概念 pseudocode：

```ts
async function submitSegment(input, authUser) {
  return db.transaction(async (tx) => {
    const round = await tx.lockCurrentRound(input.roundId);
    assert(round.currentWriterId === authUser.id);
    assert(round.status === "writing");
    assertWithinDeadline(round);
    assertWordCount(input.content);

    await tx.insertSegment({
      storyId: round.storyId,
      sequenceNo: round.roundNo,
      authorId: authUser.id,
      content: input.content,
    });

    await tx.incrementWaitingWeights(round.groupId, authUser.id);
    const candidates = await tx.resolveCandidatePool(round.id);
    const nextWriter = weightedRandom(candidates);

    await tx.resetWriterState(nextWriter.id);
    await tx.closeRound(round.id);

    if (await tx.reachedRequiredSegments(round.storyId)) {
      return tx.completeStory(round.storyId);
    }

    return tx.createNextRound(round.storyId, nextWriter.id);
  });
}
```

以上 pseudocode 僅表達流程，不可直接放進瀏覽器執行。實際 implementation 必須加入資料庫交易、資料庫約束、錯誤回滾與重試策略。

### 7.4 提名規則待確認

產品規格已確認提名會影響結果，但不直接決定結果；目前仍需要在開發前確認提名的數學定義。首版建議採用最容易理解與測試的規則：

> 有一位或多位提名時，提名名單成為候選池；抽選仍依候選人的 `selection_weight` 加權隨機。沒有提名時，所有合資格學生都進入候選池。

不要在第一版偷偷對被提名者增加倍率，除非產品負責人明確確認並更新規格。

---

## 8. Google OAuth 設定步驟

1. 建立或選擇 Google Cloud project。
2. 在 Google Auth Platform 設定 Branding 與 OAuth consent screen。
3. 建立 Web application OAuth Client ID。
4. 設定正式網站 origin 與本機開發 origin。
5. 將 Supabase 專案的 callback URL 加入 Authorized redirect URIs。
6. 將 Google Client ID 與 Client Secret 填入 Supabase Authentication → Providers → Google。
7. 在 Supabase Auth 設定允許的 redirect URLs。
8. 使用 `openid`、`email`、`profile` 基本 scopes 測試登入。
9. 測試登入成功、取消授權、重複登入、登出及 callback 錯誤。

Supabase 官方文件提供 Web application client ID、authorized origins 與 callback URL 的完整設定流程。[2]

---

## 9. API／前端整合契約

如果採 Supabase 直連，前端可使用 `@supabase/supabase-js`；若採 Manus full-stack 原生模式，則使用模板既有的 tRPC。不可同時為同一功能建立兩套呼叫方式。

### 9.1 建議功能契約

| 功能 | Supabase 直連實作 | Manus full-stack 替代實作 |
|---|---|---|
| 目前登入者 | `supabase.auth.getUser()` | `trpc.auth.me.useQuery()` |
| Google 登入 | `supabase.auth.signInWithOAuth({ provider: 'google' })` | 由既有 OAuth flow 處理，或另接 provider |
| 建立活動 | insert `activities` | `activities.create` mutation |
| 加入活動 | function／transaction | `activities.join` mutation |
| 讀取故事 | select view／RPC | `stories.getByGroup` query |
| 讀取進度 | view／RPC | `groups.getProgress` query |
| 志願登記 | insert `volunteers` | `relay.volunteer` mutation |
| 提名 | insert `nominations` | `relay.nominate` mutation |
| 提交段落 | Edge Function／RPC | `relay.submitSegment` mutation |
| 手動結束 | Edge Function／RPC | `activities.close` mutation |

### 9.2 建議讀取 view

為了讓前端不必重組多張表，建立以下 read-only view 或 RPC：

- `story_with_segments`：故事、段落、作者顯示名稱與提交時間。
- `group_progress`：總段落、已完成段落、完成百分比、目前作者與剩餘段落。
- `member_relay_status`：成員顯示名稱、已寫段落數、目前狀態與等待輪數。
- `completed_story_sequence`：完成故事與實際作者順序。

前端 Home 頁面應只依賴穩定的資料 shape，不直接在多個元件中拼接 raw tables。

---

## 10. 即時同步策略

第一階段使用 5–10 秒輪詢，並在提交成功、提名成功或志願登記成功後立即重新取得資料。這能降低 WebSocket 連線、重連與房間管理的維護成本。

待 MVP 確認使用者確實需要「某人提交後立即看到狀態」時，再啟用 Supabase Realtime 監聽 `activity_events` 或相關資料表。Realtime 不是第一階段的必要條件；如果開啟，必須測試權限過濾、離開頁面取消訂閱、斷線重連與重複事件。

---

## 11. 開發階段與執行順序

### Phase 1：環境與選型鎖定

確認採用 Supabase 直連或 Manus full-stack 原生資料層，建立專案、環境變數與 OAuth 設定。若選 Supabase，新增 `VITE_SUPABASE_URL` 與前端 publishable／anon key；service role key 只能放在伺服器端或 Edge Function secrets。

### Phase 2：資料庫與安全規則

建立 schema、索引、constraints、RLS policies 與必要的 views／RPC。先用最小測試資料驗證教師只能看自己的活動、學生只能看自己的小組，並確認已提交段落不可修改。

### Phase 3：認證與活動流程

完成 Google OAuth、登入後 profile 建立、教師建立活動、學生以活動代碼加入，以及自動或教師指定分組。所有異常流程都要有可理解的繁體中文錯誤訊息。

### Phase 4：接力核心流程

完成 Writer 0、目前作者、志願登記、提名、段落提交、權重更新、伺服器端抽選、逾時處理與活動完成條件。這一階段優先測試 transaction 與併發，不要先做動畫或額外視覺功能。

### Phase 5：前端資料接入

將 `Home.tsx` 的 `members` 與 `seedSegments` 示範常數替換為真實查詢；將志願登記、提名與提交改為 mutation；加入 loading、empty、error、權限不足與活動完成狀態。

### Phase 6：完成頁與教師視圖

加入完成故事頁、實際寫作序列、貢獻者清單、教師活動管理與手動結束活動。保留故事閱讀的情緒中心，不加入排行榜或作者比較分數。

### Phase 7：測試、驗證與交付

執行型別檢查、單元測試、資料庫權限測試、併發測試、Google OAuth 流程測試、桌面與手機瀏覽器測試，最後建立 checkpoint 再交付。

---

## 12. 測試與驗收標準

### 12.1 身分與權限

- 教師可登入、建立活動並取得活動代碼。
- 學生可使用 Google OAuth 登入並加入活動。
- 未加入小組的學生無法讀取其他小組故事。
- 學生不能修改活動設定或已提交段落。
- 非建立者教師不能結束別人的活動。

### 12.2 接力流程

- Writer 0 可正確建立故事初始狀態。
- 目前作者能提交符合字數範圍的段落。
- 少於最小字數或超過最大字數時，提交被拒絕且有清楚錯誤訊息。
- 提交成功後只新增一個段落。
- 下一位作者由伺服器端依權重抽選。
- 未被選中的成員等待權重正確累積。
- 被選中的成員權重正確重設。
- 同一輪重複提交只會成功一次。
- 同時提交不會產生兩個相同序號段落或兩位目前作者。

### 12.3 活動完成

- 達到 required segments 後活動自動完成。
- 教師手動結束後不可再提交。
- deadline 到達後不可再提交，或依產品確認規則執行逾時處理。
- 完成頁顯示完整故事、貢獻者與實際寫作順序。

### 12.4 前端體驗

- 桌面版維持故事長頁＋右側工作台。
- 手機版不出現水平溢出，提交抽屜可正常操作。
- loading、empty、error 與活動完成畫面均有明確狀態。
- 主要按鈕可用鍵盤操作，焦點狀態清楚。
- 保留「紙上接力」視覺語言：暖紙白、深墨綠、朱紅編輯標記與故事優先層級。

---

## 13. 開發前必須確認的產品決策

以下事項目前尚未完全定義。下一位 agent 不應自行猜測後永久寫死；若沒有產品負責人回覆，請採用本節的預設值並在 PR／交接紀錄中標註。

| 問題 | 建議預設值 |
|---|---|
| 目前作者是否可成為下一輪候選人 | 不可，避免連續由同一人接力。 |
| 提名如何影響結果 | 提名只縮小候選池，不額外增加倍率。 |
| 學生是否可連續多次寫作 | 可以，但每輪不能選目前作者；長期公平由等待權重處理。 |
| 每位學生是否有寫作上限 | MVP 不設個人上限，僅由小組段落數與加權機制平衡。 |
| 逾時未提交如何處理 | 先標記該輪逾時，由教師手動重新開輪或跳過；不要靜默刪除輪次。 |
| 活動 deadline 時區 | 儲存 UTC，介面依教師建立活動時的時區顯示。 |
| 學生離開活動 | 標記 `left_at`，從後續候選池排除，但保留歷史貢獻。 |
| 顯示名稱是否唯一 | 同一小組內唯一；活動代碼不應暴露真實 Email。 |
| Google OAuth 是否使用額外 Google API | 否，只使用登入所需基本 scopes。 |

---

## 14. Agent 執行規則

下一位 agent 開始前，先閱讀本文件、`ideas.md`、`todo.md`、現有 `Home.tsx` 與目前專案 README。不要直接修改 `server/` 或資料庫，除非已完成後端方案選擇並明確進入 full-stack implementation phase。

如果使用 Manus full-stack 模板，遵循模板的 tRPC-first 流程：更新 schema、產生並套用 migration、建立 database helpers、建立 procedures，再接入前端 hooks；不要自行新增 Axios 或平行 REST layer。若使用 Supabase 外部後端，則統一使用 Supabase client、RPC／Edge Function 與 RLS，並將 service role key 保持在伺服器端。

任何核心提交流程的程式碼都必須有測試。不要用前端 local state 偽裝後端完成；local state 只可用於 optimistic UI，且 mutation 失敗時必須回滾或重新讀取真實資料。

不要加入產品規格明確排除的提醒、通知、競爭排行榜、積分、XP、徽章與 AI 寫作協助。不要捏造使用者評價、評論或 testimonial。

---

## 15. 參考資料

[1] [Supabase Pricing](https://supabase.com/pricing)；[Supabase Platform](https://supabase.com/)

[2] [Supabase：Login with Google](https://supabase.com/docs/guides/auth/social-login/auth-google)

[3] [Google：Using OAuth 2.0 to Access Google APIs](https://developers.google.com/identity/protocols/oauth2)

---

## 16. 交接完成定義

當下一位 agent 完成以下條件時，本交接計畫可視為完成：真實 Google OAuth 可登入、教師與學生權限有效、活動與小組資料可持久化、段落提交與加權選擇在 transaction 中安全執行、進度與故事可被多位成員讀取、活動可完成且能回顧寫作序列、現有繁體中文「紙上接力」介面仍維持、測試與正式 build 通過，並建立可回滾的 checkpoint。
