# Story Relay 開發紀錄補遺：Safari production blank-page incident

**日期：2026-09-06**  
**Production：** `https://story-relay.wu33000.workers.dev`  
**狀態：RESOLVED / PASS**

本文件是 `STORY_RELAY_DEVELOPMENT_RECORD.md` 的 production incident 補遺。詳細技術紀錄另見：

`story-relay/SAFARI_BOOTSTRAP_HARDENING.md`

## 1. 使用者回報

有使用者回報，iPhone Safari 無法正確開啟 Story Relay。

確認條件：

- browser：mobile Safari
- iOS：26.6.1
- failure point：首頁一打開即失敗，尚未進入 Google OAuth
- symptom：完全白畫面
- 沒有看到 AuthGate 的「正在確認登入狀態…」
- 沒有看到 React ErrorBoundary

因此 OAuth 問題與一般 React component rendering error 被降為低優先；診斷集中在 React mount 之前的 production bootstrap / module / asset loading。

## 2. Repo inspection

檢查 production frontend 後發現：

- Vite production plugin chain 仍包含 Manus runtime。
- JSX-location instrumentation 仍在 plugin chain。
- Manus debug collector / storage proxy 與 production 設定混在同一 config。
- `client/index.html` 仍有未解析的 Manus analytics placeholders。
- `main.tsx` 在 React mount 前沒有 bootstrap-level recovery UI。
- React ErrorBoundary 無法攔截 module import、parse 或 top-level bootstrap failure，因此這類錯誤可能直接形成白畫面。

## 3. Production hardening patch

施作：

1. production Vite build 只保留必要的 React / Tailwind plugins；Manus runtime、JSX-location、debug collector、storage proxy 改為 development-only。
2. 移除未設定的 analytics placeholder script。
3. `main.tsx` 增加同步 bootstrap error fallback。
4. `index.html` 增加不依賴 React/CSS 的 startup watchdog；若 12 秒後 `#root` 仍為空，顯示可見 recovery UI，而不是永久白頁。

主要 commit：

`48f3f1c39aa8f9b828687aa83bc3c9d6fd297869`

## 4. Deployment pipeline 發現

Patch push 到 GitHub `main` 後，Cloudflare dashboard 並沒有產生新的 build。

檢查時可見：

- Active deployment 仍是約 1 day ago 的舊版本。
- Version History 全部是舊 deployment。
- Recent builds 也全部是舊紀錄。

因此不能把 GitHub commit 視為已進 production。

進一步確認 Cloudflare Workers 與 GitHub 的 connected build 已斷線。重新連接 GitHub 後，Cloudflare 才重新 build / deploy `main`。

這是本次除錯的重要 operational finding：

> GitHub `main` 已更新 ≠ Cloudflare production 已更新。

## 5. Production retest

Cloudflare 重新連接 GitHub並完成 build/deploy 後，請原本回報問題的同一支 iPhone Safari 再次開啟：

`https://story-relay.wu33000.workers.dev`

結果：

**A — 正常顯示。PASS。**

原本的完全白畫面不再出現。

## 6. Root-cause assessment

能夠確定的事項：

- incident 屬於 pre-render / bootstrap 類型症狀，而不是 OAuth 後才發生。
- 第一輪修復未立即反映到 production，是因 Cloudflare 與 GitHub connected build 已斷線。
- Cloudflare 重新連接 GitHub並部署 hardened build 後，同一受影響裝置恢復正常。

不能宣稱已證明的事項：

- 不能把單一 Manus plugin 宣稱為唯一 root cause。
- 不能把 Safari cache / stale asset 宣稱為已證明的唯一 root cause。
- 不能把 Supabase `getSession()` 宣稱為 root cause，因使用者連 AuthGate loading UI 都未看到。

因此正式結論採：

> Safari blank-page incident 在 production bootstrap hardening 實際部署後解除；同時發現並修復 Cloudflare ↔ GitHub connected-build 斷線。原始白畫面的單一 JavaScript 根因未被孤立重現，因此不過度歸因。

## 7. Permanent operational rule

任何未來 production fix push 到 `main` 後，都必須確認：

1. GitHub `main` 含預期 commit。
2. Cloudflare Build History 出現對應的新 build。
3. Cloudflare Deployments 顯示新版本已 active。
4. 再進行 production/browser acceptance。

不得只因 GitHub push 成功就宣稱 Cloudflare 已部署。

## 8. Acceptance

截至 2026-09-06：

- 原受影響 iPhone Safari homepage：**PASS**
- production blank-page symptom：**RESOLVED**
- Cloudflare GitHub connection：**restored**
- hardened production bootstrap：**deployed**
- visible pre-React fallback：**implemented**

詳細 implementation 與診斷紀錄：

`story-relay/SAFARI_BOOTSTRAP_HARDENING.md`
