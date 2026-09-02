# Story Relay GitHub 同步待辦

## 儲存庫確認

- [ ] 確認指定 GitHub 儲存庫存在且目前登入帳號具備推送權限。
- [ ] 查看遠端分支、既有提交與儲存庫是否已有重要檔案。
- [ ] 確認同步策略是新增／合併，而非覆蓋既有內容。

## 安全檢查

- [ ] 確認 `.gitignore` 排除 `.env`、密鑰、node_modules、build artifacts 與系統日誌。
- [ ] 搜尋專案是否包含 Supabase secret、Google OAuth client secret、JWT secret 或其他 token。
- [ ] 保留 `AGENT_HANDOFF_PLAN.md`、`ideas.md` 與前端原始碼。

## 提交與推送

- [ ] 建立清楚的 Git commit。
- [ ] 推送至指定 GitHub repository 的主要分支或明確的新分支。
- [ ] 不使用 force push，除非使用者另行明確要求。

## 驗證

- [ ] 確認遠端 commit 與本地 commit 一致。
- [ ] 確認 GitHub 上可看到主要程式碼與交接文件。
- [ ] 向使用者回報同步結果、分支、commit 與儲存庫連結。
