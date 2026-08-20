const deckLabels = {
  person: '人', event: '事', time: '時', place: '地', object: '物',
  disruption: '突發事件', obstacle: '故事阻礙', genre: '故事類型', transformation: '故事變形',
}
const mainKeys = ['person','event','time','place','object']
const extraKeys = ['disruption','obstacle','genre','transformation']
const navItems = [
  ['home','首頁'],['overview','課程介紹'],['unit-1','Unit 1'],['unit-2','Unit 2'],['unit-3','Unit 3'],['unit-4','Unit 4'],
  ['cards','抽卡中心'],['toolkit','活動工具箱'],['stuck','卡住了？'],['teacher','教師指南'],
]
let decks = {}
let unitMarkdown = {}
let draws = JSON.parse(localStorage.getItem('cw-draws') || '{}')
let locks = JSON.parse(localStorage.getItem('cw-locks') || '{}')
let activeDeck = null

const $ = (sel) => document.querySelector(sel)
const esc = (s='') => String(s).replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#039;','"':'&quot;'}[c]))
const inline = (s='') => esc(s).replace(/\*\*(.*?)\*\*/g,'<strong>$1</strong>')

function markdown(source='') {
  const lines = source.trim().split('\n')
  let html = '', ul = false, ol = false, exampleIndex = 0
  const closeLists = () => { if (ul) { html += '</ul>'; ul=false } if (ol) { html += '</ol>'; ol=false } }
  for (let i=0; i<lines.length; i++) {
    const line = lines[i].trim()
    if (!line) { closeLists(); continue }
    if (line.startsWith('- ')) { if (ol) { html += '</ol>'; ol=false } if (!ul) { html += '<ul>'; ul=true } html += `<li>${inline(line.slice(2))}</li>`; continue }
    if (/^\d+\.\s/.test(line)) { if (ul) { html += '</ul>'; ul=false } if (!ol) { html += '<ol>'; ol=true } html += `<li>${inline(line.replace(/^\d+\.\s/,''))}</li>`; continue }
    closeLists()
    if (line.startsWith('# ')) html += `<h1>${inline(line.slice(2))}</h1>`
    else if (line.startsWith('## ')) {
      const next = (lines[i+1] || '').trim()
      if (next.startsWith(':::example ')) {
        const id = `lesson-example-${exampleIndex++}`
        const example = next.slice(':::example '.length)
        html += `<div class="lesson-heading-row"><h2>${inline(line.slice(3))}</h2><button class="example-toggle" data-example-toggle="${id}" aria-expanded="false" aria-controls="${id}">範例</button></div><div class="example-panel" id="${id}" hidden>${inline(example)}</div>`
        i++
      } else html += `<h2>${inline(line.slice(3))}</h2>`
    }
    else if (line.startsWith('> ')) html += `<blockquote>${inline(line.slice(2))}</blockquote>`
    else html += `<p>${inline(line)}</p>`
  }
  closeLists(); return html
}

function pageFromHash() {
  const p = location.hash.replace('#/','') || 'home'
  return navItems.some(([key]) => key === p) ? p : 'home'
}
function nav(page) { location.hash = `#/${page}` }

function shell(content) {
  const page = pageFromHash()
  return `<div class="app-shell">
    <header class="topbar">
      <button class="brand" data-nav="home" aria-label="回首頁"><span class="brand-mark">CW</span><span><strong>Creative Writing Lab</strong><small>創意寫作課堂引導</small></span></button>
      <button class="menu-button" id="menuButton">選單</button>
      <nav class="nav" id="nav">${navItems.map(([key,label]) => `<button class="${page===key?'active':''}" data-nav="${key}">${label}</button>`).join('')}</nav>
    </header>
    <main>${content}</main>
    <footer>Creative Writing Lab · 靜態教學網站 · 不儲存學生作品</footer>
  </div>`
}

function home() {
  const units = [
    ['unit-1','01','我也可以創作','敢想：先建立創作安全感與發散經驗'],
    ['unit-2','02','創意就是建立關係','連結：用強制關聯把不相干元素串成故事'],
    ['unit-3','03','讓故事發展起來','發展：用因果、阻礙與人物選擇推動故事'],
    ['unit-4','04','把想法變成作品','表達：讓別人看見你的想像，並重新改寫'],
  ]
  return `<section class="hero"><p class="eyebrow">CREATIVE CONFIDENCE</p><h1>不是找出最會寫的人，<br>而是讓每個人發現：<em>我可以創造。</em></h1><p class="hero-copy">四個 2 小時單元，從發散、關聯、發展到表達。網站提供流程與限制，但不替學生創作。</p><div class="hero-actions"><button class="primary" data-nav="unit-1">開始 Unit 1</button><button class="secondary" data-nav="cards">前往抽卡中心</button></div></section>
  <section class="section-wrap"><div class="unit-grid">${units.map(([key,no,title,desc]) => `<button class="unit-card" data-nav="${key}"><span class="unit-no">${no}</span><h2>${title}</h2><p>${desc}</p><span class="arrow">→</span></button>`).join('')}</div><div class="quick-grid"><button class="quick-card" data-nav="toolkit"><strong>我忘記活動怎麼做</strong><span>快速查看所有創作工具</span></button><button class="quick-card" data-nav="stuck"><strong>我們的故事卡住了</strong><span>依照現在遇到的問題找下一步</span></button></div></section>`
}
function overview() { return `<div class="content-wrap"><article class="lesson"><p class="eyebrow">COURSE MAP</p><h1>課程怎麼進行？</h1><blockquote>敢想 → 連結 → 發展 → 表達與分享</blockquote><h2>課程原則</h2><ul><li>先產生想法，再處理語言表現。</li><li>一個問題可以有很多答案。</li><li>奇怪的答案值得探索，而不是立刻修正。</li><li>改寫不是改錯，而是探索另一種可能。</li><li>小組分享用「我注意到／我很好奇／我想知道」，不做排名。</li></ul><h2>網站扮演什麼角色？</h2><p>網站是共享操作手冊與抽卡工具。學生真正的創作發生在討論、紙筆與小組合作中；網站不評分、不生成故事，也不保存學生作品。</p></article></div>` }
function unitPage(unit) { return `<div class="content-wrap"><article class="lesson markdown">${markdown(unitMarkdown[unit] || '# 內容尚未建立')}</article>${unit==='unit-2'?'<div class="inline-action"><h2>準備抽卡？</h2><p>先和組員討論下一張想抽「人、事、時、地、物」中的哪一類。</p><button class="primary" data-nav="cards">開啟抽卡中心</button></div>':''}</div>` }

function draw(key) {
  if (locks[key]) return
  const choices = decks[key] || []
  if (!choices.length) return
  const pool = choices.length > 1 ? choices.filter(x => x !== draws[key]) : choices
  draws[key] = pool[Math.floor(Math.random()*pool.length)]
  localStorage.setItem('cw-draws', JSON.stringify(draws)); render()
}
function toggleLock(key) { locks[key] = !locks[key]; localStorage.setItem('cw-locks', JSON.stringify(locks)); render() }
function resetMain() { mainKeys.forEach(k => { delete draws[k]; delete locks[k] }); activeDeck=null; localStorage.setItem('cw-draws',JSON.stringify(draws)); localStorage.setItem('cw-locks',JSON.stringify(locks)); render() }
function drawBox(key) { const value=draws[key], locked=!!locks[key]; return `<div class="draw-box"><p class="eyebrow">現在選擇</p><h3>${deckLabels[key]}</h3><div class="draw-result">${esc(value || '？')}</div><div class="draw-actions"><button class="primary" data-draw="${key}" ${locked?'disabled':''}>${value?'重抽這一類':'抽取'}</button>${value?`<button class="secondary" data-lock="${key}">${locked?'解除鎖定':'鎖定這張'}</button>`:''}</div>${value?'<p class="prompt">先討論：這個元素讓你們想到什麼？再決定下一張要抽哪一類。</p>':''}</div>` }
function cards() {
  const drawn = mainKeys.filter(k => draws[k])
  const extraExamples = {
    disruption: '例：抽到「有人在說謊」後，不重寫故事，而是讓原本可信的線索變得可疑。',
    obstacle: '例：角色正要離開時抽到「最重要的東西不見了」，故事因此多出一個新的問題。',
    genre: '例：同樣是「遺失一把鑰匙」，推理故事會追查線索，喜劇則可能讓每個人都拿錯鑰匙。',
    transformation: '例：抽到「換一個人來說」，把原本由學生敘述的故事改成老師的視角。',
  }
  return `<div class="content-wrap wide"><section class="cards-header"><p class="eyebrow">CARD CENTER</p><h1>抽卡中心</h1><p>先和組員討論：<strong>下一張想抽什麼？</strong> 不需要按照「人→事→時→地→物」的順序。</p></section><section class="main-draw-panel"><div class="section-title-row"><h2>強制關聯｜人・事・時・地・物</h2><button class="example-toggle" data-example-toggle="card-main-example" aria-expanded="false" aria-controls="card-main-example">範例</button></div><div class="example-panel compact" id="card-main-example" hidden>例：先抽「物」得到「紅色雨傘」，再抽「地」得到「廢棄遊樂園」。先討論兩者可能有什麼關係，再決定第三張要抽哪一類。</div><p class="hint">選一個類別後，再單獨抽取。看到結果後先討論，再決定下一個類別。</p><div class="category-grid">${mainKeys.map(key => `<button class="category-tile ${draws[key]?'has-value':''} ${locks[key]?'locked':''}" data-active="${key}"><span>${deckLabels[key]}</span><strong>${esc(draws[key] || '尚未抽取')}</strong><small>${locks[key]?'已鎖定':'點選這一類'}</small></button>`).join('')}</div>${activeDeck && mainKeys.includes(activeDeck) ? drawBox(activeDeck) : ''}<div class="current-set"><div class="current-head"><h3>我們現在有什麼？</h3><button class="text-button" id="resetMain">清除本組</button></div>${drawn.length?`<div class="chips">${drawn.map(key => `<span><b>${deckLabels[key]}</b> ${esc(draws[key])} ${locks[key]?'🔒':''}</span>`).join('')}</div>`:'<p>還沒有抽卡。先討論想從哪一類開始。</p>'}</div></section><section class="extra-section"><h2>其他牌組</h2><div class="extra-grid">${extraKeys.map(key => `<div class="extra-card"><div class="extra-title-row"><h3>${deckLabels[key]}</h3><button class="example-toggle" data-example-toggle="extra-${key}" aria-expanded="false" aria-controls="extra-${key}">範例</button></div><div class="example-panel compact" id="extra-${key}" hidden>${inline(extraExamples[key])}</div><p>${esc(draws[key] || '尚未抽取')}</p><button class="secondary" data-draw="${key}">抽一張</button></div>`).join('')}</div></section><section class="rule-note"><strong>提醒</strong><p>強制關聯的重點不是抽到容易的牌，而是嘗試連結原本看起來不相干的元素。是否允許重抽、可以重抽幾次，由老師在活動開始前決定。</p></section></div>`
}
function toolkit() { const tools=[
  ['三句故事','第一句發生一件事 → 第二句事情改變 → 第三句出現意外','例：今天畢業，但校門打不開。警衛說學校從昨晚起不讓任何人離開。鐘聲響起時，我發現操場上少了一個人的影子。'],
  ['強制關聯','每加入一個元素，都問：「它改變了什麼？」','例：「紅色雨傘」加上「廢棄遊樂園」後，可以先問：這把傘為什麼一定要出現在這個地方？'],
  ['關聯檢查','拿掉這個元素，故事是否仍差不多？如果是，就繼續追問為什麼它一定要存在。','例：拿掉生日蛋糕後故事仍成立，就讓蛋糕成為辨認失蹤者的唯一線索，使它真正影響事件。'],
  ['因為 → 所以 → 但是','「所以」建立因果；「但是」加入阻礙。','例：因為忘了鑰匙，所以她晚上回學校，但是教室裡有人。'],
  ['人物三問','他想要什麼？害怕什麼？不能讓別人知道什麼？最後，他做了什麼選擇？','例：他想離開城市、害怕父親失望、秘密是已買好單程票；最後他必須決定要不要上車。'],
  ['同儕回饋','我注意到……／我很好奇……／我想知道……','例：「我注意到那把鑰匙一直出現；我很好奇它原本屬於誰；我想知道主角最後會不會真的把門打開。」']
]; return `<div class="content-wrap"><section class="cards-header"><p class="eyebrow">TOOLKIT</p><h1>活動工具箱</h1><p>忘記規則時，不必翻回整個單元。</p></section><div class="tool-list">${tools.map(([t,d,e],i)=>`<article><div class="tool-title-row"><h2>${t}</h2><button class="example-toggle" data-example-toggle="tool-example-${i}" aria-expanded="false" aria-controls="tool-example-${i}">範例</button></div><div class="example-panel compact" id="tool-example-${i}" hidden>${inline(e)}</div><p>${d}</p></article>`).join('')}</div></div>` }
function stuck() { const items=[['我們完全想不到故事','不要想完整故事。先回答：「這個人為什麼會在這裡？」'],['這些東西根本連不起來','先找最奇怪的兩個，問：「如果它們其實有關，會是什麼關係？」'],['故事很無聊','加入一個「但是……」，讓原本計畫遇到阻礙。'],['事情很多，但不像故事','找出哪一件事是「因為前一件事」才發生。'],['不知道角色要做什麼','問：「他現在最想得到什麼？」再逼他做一個選擇。'],['大家都沒有想法','每個人先講一個「最爛的想法」。發想階段先求有，再求好。'],['有人一直否定別人的點子','先用「對，而且……」繼續增加可能，不急著用「可是……」刪掉可能。']]; return `<div class="content-wrap"><section class="cards-header"><p class="eyebrow">TROUBLESHOOTING</p><h1>卡住了？</h1><p>先找到最接近你們現在遇到的問題。</p></section><div class="problem-list">${items.map(([q,a])=>`<details><summary>${q}</summary><p>${a}</p></details>`).join('')}</div></div>` }
function teacher() { return `<div class="content-wrap"><article class="lesson"><p class="eyebrow">TEACHER GUIDE</p><h1>教師指南</h1><h2>每堂課的基本節奏</h2><ol><li>說明今天的創意工具。</li><li>老師示範一次。</li><li>讓小組自行活動。</li><li>巡視，但不要立即提供答案。</li><li>遇到流程問題先讓學生查「卡住了？」。</li><li>最後進行分享與反思。</li></ol><h2>40 人、一位老師</h2><p>建議固定 8 組 × 5 人，角色輪替：引導者、記錄者、關聯者、挑戰者、發表者。關聯者負責追問「為什麼有關？」；挑戰者負責提出「還有沒有另一種可能？」。</p><h2>抽卡原則</h2><p>Unit 2 不要一次抽完人事時地物。請各組先討論下一個想抽的類別，再逐張抽取。抽卡順序本身也是創作決策的一部分。</p></article></div>` }

function contentFor(page) { if(page==='home')return home(); if(page==='overview')return overview(); if(page.startsWith('unit-'))return unitPage(page); if(page==='cards')return cards(); if(page==='toolkit')return toolkit(); if(page==='stuck')return stuck(); return teacher() }
function bind() {
  document.querySelectorAll('[data-nav]').forEach(el => el.addEventListener('click',()=>nav(el.dataset.nav)))
  $('#menuButton')?.addEventListener('click',()=>$('#nav')?.classList.toggle('open'))
  document.querySelectorAll('[data-active]').forEach(el=>el.addEventListener('click',()=>{activeDeck=el.dataset.active;render()}))
  document.querySelectorAll('[data-draw]').forEach(el=>el.addEventListener('click',()=>draw(el.dataset.draw)))
  document.querySelectorAll('[data-lock]').forEach(el=>el.addEventListener('click',()=>toggleLock(el.dataset.lock)))
  $('#resetMain')?.addEventListener('click',resetMain)
  document.querySelectorAll('[data-example-toggle]').forEach(el=>el.addEventListener('click',()=>{ const panel=document.getElementById(el.dataset.exampleToggle); if(!panel)return; const opening=panel.hidden; panel.hidden=!opening; el.setAttribute('aria-expanded', String(opening)); el.textContent=opening?'收起範例':'範例' }))
}
function render() { const page=pageFromHash(); $('#app').innerHTML=shell(contentFor(page)); bind(); window.scrollTo({top:0,behavior:'instant'}) }

async function loadData() {
  const deckPairs = await Promise.all(Object.keys(deckLabels).map(async key => [key, await (await fetch(`./decks/${key}.json`)).json()]))
  decks = Object.fromEntries(deckPairs)
  const unitPairs = await Promise.all([1,2,3,4].map(async n => [`unit-${n}`, await (await fetch(`./content/units/unit-${n}.md`)).text()]))
  unitMarkdown = Object.fromEntries(unitPairs)
}

window.addEventListener('hashchange', render)
loadData().then(()=>{ if(!location.hash) location.hash='#/home'; else render() }).catch(err => { console.error(err); $('#app').innerHTML='<p style="padding:2rem">網站資料載入失敗，請確認以 HTTP 伺服器開啟此資料夾。</p>' })
