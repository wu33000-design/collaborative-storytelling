# Creative Writing Lab

創意寫作課堂引導網站。Repository 同時保存課堂教材工具與 `story-relay/` 協作敘事應用。

## Story Relay

Story Relay 的約 100 人課堂 MVP 已於 2026-09-04 完成本階段開發與驗收，公開前端已從 GitHub Pages 遷移至 Cloudflare Workers。

Production：

`https://story-relay.wu33000.workers.dev`

完整產品決策、架構、安全邊界、Phase A–E 開發與驗收、部署紀錄、已知限制與未來接手方式請先讀：

`STORY_RELAY_DEVELOPMENT_RECORD.md`

相關細節文件：

- `CLASSROOM_100_DEVELOPMENT_PLAN.md`
- `PHASE_E_DDOS_ABUSE_HARDENING.md`
- `SECURITY_AUDIT_REPORT.md`
- `story-relay/AGENT_HANDOFF_PLAN.md`
- `story-relay/supabase/migrations/`
- `story-relay/supabase/tests/`

GitHub 現在作為 Story Relay 的 source control 與 Cloudflare connected-build source；本 repository 的舊 GitHub Pages deployment workflow 已移除，不應重新把 Story Relay production frontend 切回 GitHub Pages。

## Creative Writing Lab legacy content

Repository root 仍保存原始創意寫作課堂教材與抽卡工具：

- 四個 2 小時教學單元
- 活動工具箱與「卡住了？」流程支援
- 人／事／時／地／物牌組
- 突發事件、故事阻礙、故事類型、故事變形牌組
- 教學單元：`content/units/*.md`
- 牌組：`decks/*.json`

這些 root-level 教材內容與 `story-relay/` 應用是不同層次的資產；不要因修改 Story Relay 而誤刪教材。

## Local preview of legacy root site

不要直接雙擊 root `index.html`，因為瀏覽器可能阻擋本機 `fetch()` 讀取 Markdown/JSON。可在 repository root 執行：

```bash
python3 -m http.server 8000
```

然後開啟 `http://localhost:8000`。
