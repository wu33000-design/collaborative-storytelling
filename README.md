# Creative Writing Lab

創意寫作課堂引導網站。定位為「教學內容 + 流程查閱 + 輕量抽卡工具」，不保存學生作品，也不需要後端。

## MVP

- 四個 2 小時教學單元
- 活動工具箱與「卡住了？」流程支援
- 人／事／時／地／物由小組自行選類別，再分開抽取
- 單類別重抽、鎖定、目前元素總覽
- 突發事件、故事阻礙、故事類型、故事變形牌組
- 抽卡狀態保存在瀏覽器 `localStorage`
- Mobile-first，亦適合課堂投影
- GitHub Pages 自動部署 workflow
- 零 npm 套件、零 build step、零 backend

## Local preview

不要直接雙擊 `index.html`，因為瀏覽器會阻擋本機 `fetch()` 讀取 Markdown/JSON。請在專案資料夾執行：

```bash
python3 -m http.server 8000
```

然後開啟 `http://localhost:8000`。

## Content

- 教學單元：`content/units/*.md`
- 牌組：`decks/*.json`

教材與牌組內容都和 UI 程式分離，未來可直接編輯 Markdown / JSON，不必改抽卡程式。

## Deployment

Repo 推到 GitHub 後：

1. Settings → Pages
2. Source 選 GitHub Actions
3. push 到 `main`
4. `.github/workflows/deploy-pages.yml` 會直接發布整個靜態站
