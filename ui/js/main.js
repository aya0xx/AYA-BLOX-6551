'use strict';

const _splashStart = Date.now();

function esc(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const El = {};
function cacheElements() {
  El.topbar         = document.getElementById('topbar');
  El.sidenav        = document.getElementById('sidenav');
  El.content        = document.getElementById('content');
  El.loadingOverlay = document.getElementById('loading-overlay');
  El.loadingText    = document.getElementById('loading-text');
  El.confirmDialog  = document.getElementById('confirm-dialog');
  El.confirmTitle   = document.getElementById('confirm-title');
  El.confirmMsg     = document.getElementById('confirm-msg');
  El.mintBaseDialog = document.getElementById('mint-base-dialog');
  El.mbCostVal      = document.getElementById('mb-cost-val');
  El.mintSubDialog  = document.getElementById('mint-sub-dialog');
  El.msSub          = document.getElementById('ms-sub');
  El.msSlotRow      = document.getElementById('ms-slot-row');
  El.msSlotRemain   = document.getElementById('ms-slot-remaining');
  El.msScoreTag     = document.getElementById('ms-score-tag');
  El.msCostVal      = document.getElementById('ms-cost-val');
  El.mintFeedback   = document.getElementById('mint-feedback');
  El.subFeedback    = document.getElementById('sub-feedback');
  El.walletStatus   = document.getElementById('wallet-status');
  El.notification  = document.getElementById('notification');
  El.errCardList   = document.getElementById('err-card-list');
}

// SVG — mirrors SVGRenderer.sol exactly. Do not alter coordinates, fonts, or fill colors.

function _svgSlots(limit, filled) {
  const SZ = 36, GAP = 8, GX = 20, GY = 155;
  let s = '';
  for (let i = 0; i < limit; i++) {
    const x = GX + (i % 4) * (SZ + GAP);
    const y = GY + Math.floor(i / 4) * (SZ + GAP);
    const on = i < filled;
    s += `<rect x="${x}" y="${y}" width="${SZ}" height="${SZ}"
            fill="${on ? '#00ff88' : '#1a1a1a'}" stroke="${on ? '#00ff88' : '#2a2a2a'}"
            stroke-width="1" rx="3"/>`;
    if (on) s += `<text x="${x+SZ/2}" y="${y+SZ/2+5}" font-family="monospace" font-size="13"
                    fill="#0d0d0d" text-anchor="middle">${i+1}</text>`;
  }
  return s;
}

function buildSVG(tokenId, type, limit, filled) {
  const ms  = (limit * (limit + 1)) / 2;
  const col = type === 0 ? '#666666' : type === 1 ? '#999999' : '#cccccc';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" width="100%" height="100%">
    <rect width="400" height="400" fill="#0d0d0d"/>
    <text x="20" y="44" font-family="monospace" font-size="18" font-weight="bold" fill="#e0e0e0">AYA-BLOX-6551 #${tokenId}</text>
    <line x1="20" y1="56" x2="380" y2="56" stroke="#2a2a2a" stroke-width="1"/>
    <text x="20"  y="82" font-family="monospace" font-size="12" fill="#555">TYPE</text>
    <text x="90"  y="82" font-family="monospace" font-size="12" fill="#555">SLOTS</text>
    <text x="165" y="82" font-family="monospace" font-size="12" fill="#555">MAX SCORE</text>
    <text x="20"  y="114" font-family="monospace" font-size="32" font-weight="bold" fill="${col}">${type}</text>
    <text x="90"  y="114" font-family="monospace" font-size="18" fill="#e0e0e0">${limit}</text>
    <text x="165" y="114" font-family="monospace" font-size="18" fill="#e0e0e0">${ms}</text>
    <text x="20"  y="140" font-family="monospace" font-size="11" fill="#444">SLOT CAPACITY</text>
    ${_svgSlots(limit, filled)}
    <text x="20" y="390" font-family="monospace" font-size="10" fill="#2a2a2a">AYA-BLOX-6551 | ERC-6551</text>
  </svg>`;
}


/* ═══════════════════════════════════════════════════════════════════════════
   UI HELPERS — Phase 3: CSS class-based, no inline styles
══════════════════════════════════════════════════════════════════════════════ */

function slotDots(filled, limit) {
  let h = '<div class="slot-dots">';
  for (let i = 0; i < limit; i++) {
    h += `<div class="slot-dot${i < filled ? ' slot-dot--filled' : ''}"></div>`;
  }
  return h + '</div>';
}

function largeSlotGrid(filled, limit) {
  const COLS = Math.min(limit, 4);
  let h = `<div class="slot-grid slot-grid--${COLS}col">`;
  for (let i = 0; i < limit; i++) {
    const on = i < filled;
    h += `<div class="slot-cell${on ? ' slot-cell--filled' : ''}">
             ${on ? `<span class="slot-cell__num">${i+1}</span>` : ''}
           </div>`;
  }
  return h + '</div>';
}

function subChips(subUnits) {
  if (!subUnits || subUnits.length === 0)
    return '<span class="sub-chip--empty">—</span>';
  return '<div class="sub-chips">' +
    subUnits.map((_, i) => `<div class="sub-chip">+${i+1}</div>`).join('') +
  '</div>';
}


/* ═══════════════════════════════════════════════════════════════════════════
   CARD BUILDERS — V1 Portrait (locked)
══════════════════════════════════════════════════════════════════════════════ */

function buildPortraitCard(unit, index) {
  const isSel  = State.selectedBaseIndex === index;
  const isDone = unit.isCompleted;
  const cls = isSel ? 'card card--selected' : isDone ? 'card card--complete' : 'card';
  return `
    <li class="card-item">
      <div data-action="select-card" data-index="${index}" class="${cls}" tabindex="0">
        <div class="card__thumb">
          ${buildSVG(unit.tokenId, unit.type, unit.limit, unit.subUnitCount)}
        </div>
        <div class="card__data">
          <div class="card__meta">
            <span class="card__type">${esc(unit.typeName)}</span>
            <span class="card__id">#${esc(unit.tokenId)}</span>
          </div>
          ${slotDots(unit.subUnitCount, unit.limit)}
          <div class="card__score-row">
            <span class="card__score">${unit.localScore}</span>
            <span class="card__score-max">/ ${unit.maxScore}</span>
            <span class="card__score-unit">pts</span>
          </div>
          ${isDone ? '<div class="card__complete">✓ COMPLETE</div>' : '<div class="card__progress">IN PROGRESS</div>'}
        </div>
      </div>
    </li>`;
}

function buildGhostCard() {
  if (!State.connected || State.baseUnitsOwned >= State.maxPerWallet) return '';
  if (State.baseUnitsOwned === 0) return `
    <li class="card-item">
      <div data-action="mint-base" class="card--ghost" tabindex="0">
        <div class="ghost-body">
          <span class="ghost-eyebrow">START HERE</span>
          <span class="ghost-title">MINT BASE UNIT</span>
          <div class="ghost-rule"></div>
          <div class="ghost-steps">COLLECT<br>FILL SLOTS<br>EARN SCORE</div>
        </div>
        <div class="ghost-footer">
          <span class="ghost-price">${State.baseUnitPriceEth} ETH</span>
        </div>
      </div>
    </li>`;
  return `
    <li class="card-item">
      <div data-action="mint-base" class="card--ghost" tabindex="0">
        <div class="ghost-body">
          <span class="ghost-eyebrow">ADD ANOTHER</span>
          <span class="ghost-title">MINT BASE UNIT</span>
          <div class="ghost-rule"></div>
          <div class="ghost-stat">
            <span class="ghost-stat-val">${State.baseUnitsOwned}</span> OF <span class="ghost-stat-val">${State.maxPerWallet}</span> MINTED<br>
            <span class="ghost-stat-dim">SLOTS AVAILABLE</span>
          </div>
        </div>
        <div class="ghost-footer">
          <span class="ghost-price">${State.baseUnitPriceEth} ETH</span>
        </div>
      </div>
    </li>`;
}


/* ═══════════════════════════════════════════════════════════════════════════
   DETAIL PANEL — V3 Slot Grid Dominant (locked)
══════════════════════════════════════════════════════════════════════════════ */

function buildDetailPanel() {
  const unit = State.selectedBase;

  if (!unit) {
    if (State.baseUnitsOwned === 0) return `
      <div class="panel__sel-body">
        <span class="panel__sel-eyebrow">FIRST STEP</span>
        <span class="panel__sel-title">MINT A<br/>BASE UNIT</span>
        <div class="panel__sel-rule"></div>
        <div class="panel__sel-hint">
          <span class="panel__sel-hint-arrow">←</span>
          <span class="panel__sel-hint-text">CLICK THE CARD</span>
        </div>
      </div>`;
    return `
      <div class="panel__sel-body">
        <span class="panel__sel-eyebrow">NEXT STEP</span>
        <span class="panel__sel-title">SELECT A<br/>BASE UNIT</span>
        <div class="panel__sel-rule"></div>
        <div class="panel__sel-hint">
          <span class="panel__sel-hint-arrow">←</span>
          <span class="panel__sel-hint-text">CLICK ANY CARD</span>
        </div>
      </div>`;
  }

  const mintBtn = unit.isCompleted
    ? `<button disabled class="panel__mint-btn">✓ COMPLETED</button>`
    : `<button data-action="mint-sub" class="panel__mint-btn">MINT SUB UNIT</button>`;

  return `
    <div data-action="close-panel" class="panel__close">← BACK</div>
    <div class="panel__inner">
      <div class="panel__slots">
        <div class="panel__slots-header">
          <span class="panel__slot-label">SLOTS</span>
          <span class="panel__slot-count">${unit.subUnitCount} / ${unit.limit}</span>
        </div>
        ${largeSlotGrid(unit.subUnitCount, unit.limit)}
      </div>
      <div class="panel__divider"></div>
      <div class="panel__thumb-info">
        <span class="panel__unit-name">${esc(unit.typeName)} #${esc(unit.tokenId)}</span>
        <span>
          <span class="panel__score">${unit.localScore}</span>
          <span class="panel__score-max"> / ${unit.maxScore} pts</span>
        </span>
      </div>
      <div class="panel__subs">
        <div class="panel__subs-label">SUB UNITS</div>
        ${subChips(unit.subUnits)}
      </div>
      <div class="panel__spacer"></div>
      ${mintBtn}
    </div>`;
}


/* ═══════════════════════════════════════════════════════════════════════════
   VIEW BUILDERS
══════════════════════════════════════════════════════════════════════════════ */

function buildIntroView() {
  return `
    <div class="intro">
      <div class="intro__left">
        <p class="intro__eyebrow">AYA-BLOX-6551</p>
        <h2 class="intro__headline">MINT.<br/>FILL.<br/>SCORE.</h2>
        <p class="intro__body">
          ERC-721 + ERC-6551 TOKEN-BOUND ACCOUNTS.<br/>
          FULLY ON-CHAIN SVG. DETERMINISTIC SCORING.<br/>
          MINT-ONLY SUB UNITS. NON-TRANSFERABLE.
        </p>
        <div>
          ${State.connected
            ? `<button data-action="nav" data-view="base" class="intro__cta">VIEW BASE UNITS</button>`
            : `<button data-action="connect" class="intro__cta">CONNECT WALLET</button>`}
        </div>
      </div>
      <div class="intro__right">
        <div class="intro__nft">
          ${buildSVG(2, 2, 8, 8)}
        </div>
      </div>
    </div>`;
}

function buildBaseView() {
  if (!State.connected) return `
    <div class="base-connect">
      <p class="base-connect__msg">CONNECT WALLET TO VIEW BASE UNITS</p>
      <button data-action="connect" class="base-connect__btn">CONNECT WALLET</button>
    </div>`;

  const cards = State.baseUnits.map((u, i) => buildPortraitCard(u, i)).join('');
  return `
    <div class="base-view">
      <ul class="card-grid" role="list">
        ${cards}
        ${buildGhostCard()}
      </ul>
      <div class="panel">
        ${buildDetailPanel()}
      </div>
    </div>`;
}

function buildAboutView() {
  const row = (label, value, bold) => `
    <div class="about__row">
      <span class="about__label">${label}</span>
      <span class="about__value${bold ? ' about__value--bold' : ''}">${value}</span>
    </div>`;
  const dim = (label, value) => `
    <div class="about__row">
      <span class="about__label">${label}</span>
      <span class="about__value about__value--dim">${value}</span>
    </div>`;
  const link = (label, href) => `
    <div class="about__row">
      <span class="about__label">${label}</span>
      <a href="${href}" target="_blank" rel="noopener" class="about__link">${href.replace('https://', '')}</a>
    </div>`;
  const rule = () => '<div class="about__rule"></div>';

  return `
    <div class="about">
      <div class="about__grid">
        ${row('SYSTEM',   'AYA-BLOX-6551', true)}
        ${rule()}
        ${row('PROTOCOL', 'ERC-721 + ERC-6551 TOKEN-BOUND ACCOUNTS', false)}
        ${rule()}
        ${row('METADATA', 'FULLY ON-CHAIN SVG', false)}
        ${rule()}
        ${row('SCORING',  'DETERMINISTIC — POSITION × WEIGHT', false)}
        ${rule()}
        ${row('SUB UNITS','MINT-ONLY · NON-TRANSFERABLE', false)}
        <div class="about__rule about__rule--section"></div>
        ${dim('NETWORK',  'LOCAL ANVIL')}
        ${dim('CHAIN ID', '31337')}
        ${dim('RPC',      'http://127.0.0.1:8545')}
        ${link('SOURCE', 'https://github.com/aya0xx/aya-blox-6551')}
      </div>
    </div>`;
}


/* ═══════════════════════════════════════════════════════════════════════════
   RENDER
══════════════════════════════════════════════════════════════════════════════ */

function _networkBadge() {
  const id = State.chainId;
  if (!id) return '';
  const nets = {
    31337:    { label: 'ANVIL',       cls: 'nb-tag--anvil'   },
    11155111: { label: 'SEPOLIA',     cls: 'nb-tag--sepolia'  },
    8453:     { label: 'BASE',        cls: 'nb-tag--base'     },
  };
  const net = nets[id];
  return net
    ? `<span class="nb-tag ${net.cls}">${net.label}</span>`
    : `<span class="nb-tag nb-tag--unsupported">UNSUPPORTED</span>`;
}

function renderTopBar() {
  const S     = State;
  const addr  = S.connected ? esc(S.shortAddr(S.userAddress)) : '---';
  const score = S.connected ? S.globalScore : '---';
  const units = S.connected ? `${S.baseUnitsOwned}/${S.maxPerWallet}` : '---';
  const cls   = S.connected ? 'val' : 'val-muted';

  El.topbar.innerHTML = `
    <h1 class="topbar-brand">AYA-BLOX</h1>
    ${_networkBadge()}
    <div class="pipe topbar__pipe-addr"></div>
    <span class="lbl topbar__address">ADDRESS <span class="${cls}">${addr}</span></span>
    <div class="pipe"></div>
    <span class="lbl">SCORE <span class="${cls}">${score}</span></span>
    <div class="pipe topbar__pipe-units"></div>
    <span class="lbl topbar__units">UNITS <span class="${cls}">${units}</span></span>
    ${S.connected ? `<button data-action="disconnect" class="btn-connected">DISCONNECT</button>` : ''}`;
}

function renderNav() {
  const views = [
    { id:'intro', label:'INTRO',      num:'01' },
    { id:'base',  label:'BASE UNITS', num:'02' },
    { id:'about', label:'ABOUT',      num:'03' },
  ];
  El.sidenav.innerHTML =
    `<span class="sidenav-head">NAVIGATE</span>` +
    views.map(v => {
      const a = State.activeView === v.id;
      return `<div data-action="nav" data-view="${v.id}" class="nav-row"${a ? ' aria-current="page"' : ''}>
        <span class="${a ? 'nav-num-active' : 'nav-num-inactive'}">${v.num}</span>
        <span class="${a ? 'nav-lbl-active' : 'nav-lbl-inactive'}">${v.label}</span>
      </div>`;
    }).join('');
}

const VIEW_TITLES = {
  intro: 'AYA-BLOX-6551',
  base:  'AYA-BLOX-6551 — Base Units',
  about: 'AYA-BLOX-6551 — About',
};

function renderContent() {
  document.title = VIEW_TITLES[State.activeView] || 'AYA-BLOX-6551';
  const v = State.activeView;
  El.content.innerHTML =
    v === 'intro' ? buildIntroView() :
    v === 'base'  ? buildBaseView()  :
                    buildAboutView();
}

function showMintFeedback(unit) {
  const el         = El.mintFeedback;
  const subVisible = El.subFeedback.classList.contains('is-visible');
  el.innerHTML = `
    ${!subVisible ? '<span class="status-section-label">NOTIFICATION</span>' : ''}
    <div class="mf-header">
      <div class="mf-dot"></div>
      <span class="mf-title">BASE UNIT #${esc(unit.tokenId)} MINTED</span>
    </div>
    <div class="mf-rows">
      <div class="mf-row">
        <span class="mf-key">TYPE</span>
        <span class="mf-val">${esc(unit.typeName)}</span>
      </div>
      <div class="mf-row">
        <span class="mf-key">SLOTS</span>
        <span class="mf-val">${unit.limit}</span>
      </div>
      <div class="mf-row">
        <span class="mf-key">MAX SCORE</span>
        <span class="mf-val">${unit.maxScore} PTS</span>
      </div>
    </div>`;
  el.classList.add('is-visible');
  setTimeout(() => el.classList.remove('is-visible'), 30000);
}

function showSubMintFeedback(unit) {
  const el = El.subFeedback;
  el.innerHTML = `
    <span class="status-section-label">NOTIFICATION</span>
    <div class="mf-header">
      <div class="mf-dot"></div>
      <span class="mf-title">SUB UNIT MINTED</span>
    </div>
    <div class="mf-rows">
      <div class="mf-row">
        <span class="mf-key">INTO</span>
        <span class="mf-val">${esc(unit.typeName)} #${esc(unit.tokenId)}</span>
      </div>
      <div class="mf-row">
        <span class="mf-key">SLOT</span>
        <span class="mf-val">${unit.subUnitCount} OF ${unit.limit}</span>
      </div>
      <div class="mf-row">
        <span class="mf-key">SCORE</span>
        <span class="mf-val">${unit.localScore} / ${unit.maxScore} PTS</span>
      </div>
    </div>`;
  el.classList.add('is-visible');
  setTimeout(() => el.classList.remove('is-visible'), 30000);
}

function renderWalletStatus() {
  const el = El.walletStatus;
  if (State.connected) {
    el.innerHTML = `
      <span class="status-section-label">WALLET</span>
      <div class="ws-top">
        <div class="ws-dot"></div>
        <span class="ws-status">CONNECTED</span>
      </div>
      <span class="ws-addr">${esc(State.shortAddr(State.userAddress))}</span>`;
    el.classList.add('is-connected');
  } else {
    el.classList.remove('is-connected');
  }
}

function render() {
  renderTopBar();
  renderNav();
  renderContent();
  renderWalletStatus();
}


/* ═══════════════════════════════════════════════════════════════════════════
   CONFIRM DIALOG
══════════════════════════════════════════════════════════════════════════════ */

let _resolve        = null;
let _confirmTrigger = null;

function openConfirm(title, msg) {
  return new Promise(res => {
    _resolve        = res;
    _confirmTrigger = document.activeElement;
    El.confirmTitle.textContent = title;
    El.confirmMsg.textContent   = msg;
    El.confirmDialog.style.display = 'flex';
    setTimeout(() => document.querySelector('.confirm-ok')?.focus(), 0);
  });
}

function openMintBaseDialog() {
  return new Promise(res => {
    _resolve        = res;
    _confirmTrigger = document.activeElement;
    El.mbCostVal.textContent = State.baseUnitPriceEth + ' ETH';
    El.mintBaseDialog.style.display = 'flex';
    setTimeout(() => document.querySelector('#mint-base-dialog .confirm-ok')?.focus(), 0);
  });
}

function openMintSubDialog(unit) {
  return new Promise(res => {
    _resolve        = res;
    _confirmTrigger = document.activeElement;
    const slot      = unit.subUnitCount + 1;
    const remaining = unit.limit - slot;
    El.msSub.textContent        = `${unit.typeName} #${unit.tokenId} · SLOT ${slot} OF ${unit.limit}`;
    El.msSlotRow.textContent    = `SLOT ${slot} OF ${unit.limit} FILLED`;
    El.msSlotRemain.textContent = remaining > 0 ? `${remaining} REMAINING` : 'LAST SLOT';
    El.msScoreTag.textContent   = `UP TO ${unit.maxScore} PTS`;
    El.msCostVal.textContent    = State.subUnitPriceEth + ' ETH';
    El.mintSubDialog.style.display = 'flex';
    setTimeout(() => document.querySelector('#mint-sub-dialog .confirm-ok')?.focus(), 0);
  });
}

function closeConfirm(ok) {
  El.confirmDialog.style.display  = 'none';
  El.mintBaseDialog.style.display = 'none';
  El.mintSubDialog.style.display  = 'none';
  if (_confirmTrigger) { _confirmTrigger.focus(); _confirmTrigger = null; }
  if (_resolve) { _resolve(ok); _resolve = null; }
}


/* ═══════════════════════════════════════════════════════════════════════════
   ERROR CARD — hard errors · bottom-right · persists until × dismissed
══════════════════════════════════════════════════════════════════════════════ */

function errorCard(title, reason) {
  const card = document.createElement('div');
  card.className = 'ec';
  card.setAttribute('role', 'alert');
  card.innerHTML = `
    <div class="ec-top">
      <span class="ec-label">NOTIFICATION</span>
      <button class="ec-close" aria-label="Dismiss">×</button>
    </div>
    <div class="ec-header">
      <div class="ec-dot"></div>
      <span class="ec-title">${esc(title)}</span>
    </div>
    ${reason ? `
    <div class="ec-rows">
      <div class="ec-row">
        <span class="ec-key">REASON</span>
        <span class="ec-val">${esc(reason)}</span>
      </div>
    </div>` : ''}`;
  card.querySelector('.ec-close').addEventListener('click', () => card.remove());
  El.errCardList.appendChild(card);
}


/* ═══════════════════════════════════════════════════════════════════════════
   TOAST
══════════════════════════════════════════════════════════════════════════════ */

function toast(message, type = 'info', detail = null) {
  const dotClass = type === 'error'   ? 'mf-dot--error'
                 : type === 'warning' ? 'mf-dot--warning'
                 :                      'mf-dot--info';
  const detailRow = detail ? `
    <div class="mf-rows">
      <div class="mf-row">
        <span class="mf-key">REASON</span>
        <span class="mf-val">${esc(detail)}</span>
      </div>
    </div>` : '';
  El.notification.innerHTML = `
    <span class="status-section-label">NOTIFICATION</span>
    <div class="mf-header">
      <div class="mf-dot ${dotClass}"></div>
      <span class="mf-title">${esc(message)}</span>
    </div>${detailRow}`;
  El.notification.classList.add('nf--visible');
  clearTimeout(El.notification._timer);
  El.notification._timer = setTimeout(
    () => El.notification.classList.remove('nf--visible'), 4000
  );
}


/* ═══════════════════════════════════════════════════════════════════════════
   LOADING
══════════════════════════════════════════════════════════════════════════════ */

function showLoading(msg = 'LOADING') {
  El.loadingOverlay.classList.remove('is-splash', 'is-fading');
  El.loadingText.textContent = msg;
  El.loadingOverlay.style.display = 'flex';
  document.body.setAttribute('aria-busy', 'true');
}
function hideLoading() {
  El.loadingOverlay.style.display = 'none';
  document.body.removeAttribute('aria-busy');
}
function hideSplash() {
  if (El.loadingOverlay.style.display === 'none') return;
  El.loadingOverlay.classList.add('is-fading');
  setTimeout(() => {
    El.loadingOverlay.style.display = 'none';
    El.loadingOverlay.classList.remove('is-fading', 'is-splash');
    document.documentElement.classList.remove('loading');
  }, 600);
}
function _scheduleSplashHide() {
  const elapsed   = Date.now() - _splashStart;
  const remaining = Math.max(0, 1500 - elapsed);
  setTimeout(hideSplash, remaining);
}


/* ═══════════════════════════════════════════════════════════════════════════
   DATA
══════════════════════════════════════════════════════════════════════════════ */

async function loadConstants() {
  const [bc, sc] = await Promise.all([Api.getBaseUnitConstants(), Api.getSubUnitConstants()]);
  State.maxSupply        = bc.maxSupply;
  State.totalSupply      = bc.totalSupply;
  State.maxPerWallet     = bc.maxPerWallet;
  State.baseUnitPriceEth = bc.priceEth;
  State.subUnitPriceEth  = sc.priceEth;
}

async function loadUserData(address) {
  const [units, score, balances] = await Promise.all([
    Api.getUserBaseUnits(address),
    Api.getUserGlobalScore(address),
    Api.getUserTypeBalances(address),
  ]);
  State.baseUnits      = units;
  State.baseUnitsOwned = units.length;
  State.globalScore    = score;
  State.typeBalances   = balances;
}


/* ═══════════════════════════════════════════════════════════════════════════
   ACTION HANDLERS
══════════════════════════════════════════════════════════════════════════════ */

async function handleConnect() {
  if (State.connected) return;
  showLoading('CONNECTING');
  try {
    const result = await Api.connectWallet();
    if (!result) return; // network switch in progress — chainChanged will reload
    const { address } = result;
    State.connected        = true;
    State.userAddress      = address;
    State.userAddressShort = State.shortAddr(address);
    await loadUserData(address);
    State.activeView = 'base';
    render();
  } catch (err) {
    const reason = err.message?.includes('not detected')
                 ? err.message
                 : err.code === 4001
                 ? 'User rejected the request.'
                 : err.shortMessage || err.message || 'Unknown error.';
    console.error('[connect]', err);
    errorCard('CONNECTION FAILED', reason);
  } finally {
    hideLoading();
  }
}

async function handleDisconnect() {
  window._intentionalDisconnect = true;
  try {
    await Api.disconnectWallet();
  } catch (_) { /* wallet_revokePermissions not supported — local clear only */ }

  State.connected         = false;
  State.userAddress       = '';
  State.userAddressShort  = '';
  State.baseUnits         = [];
  State.baseUnitsOwned    = 0;
  State.globalScore       = 0;
  State.typeBalances      = [];
  State.selectedBaseIndex = null;
  State.activeView        = 'intro';
  render();

  El.mintFeedback.classList.remove('is-visible');
  const ws = El.walletStatus;
  ws.innerHTML = `
    <span class="status-section-label">WALLET</span>
    <div class="ws-top">
      <div class="ws-dot ws-dot--dim"></div>
      <span class="ws-status">DISCONNECTED</span>
    </div>`;
  ws.classList.add('is-connected');
  setTimeout(() => ws.classList.remove('is-connected'), 6000);
}

function handleNav(view) {
  State.activeView = view;
  render();
  El.content.scrollTop = 0;
}

function handleSelectCard(index) {
  State.selectedBaseIndex = index;
  renderContent();
  if (window.innerWidth <= 1100) {
    document.querySelector('.panel')?.classList.add('panel--open');
    setTimeout(() => document.querySelector('.panel__close')?.focus(), 0);
  }
}

function handleClosePanel() {
  document.querySelector('.panel')?.classList.remove('panel--open');
  const card = document.querySelector(`[data-index="${State.selectedBaseIndex}"]`);
  card?.focus();
}

async function handleMintBase() {
  if (!State.connected) { toast('CONNECT WALLET FIRST', 'warning'); return; }
  if (State.baseUnitsOwned >= State.maxPerWallet) { toast('WALLET CAP REACHED', 'warning'); return; }

  const ok = await openMintBaseDialog();
  if (!ok) return;

  showLoading('MINTING BASE UNIT');
  try {
    const { tokenId } = await Api.mintBaseUnit();
    await loadUserData(State.userAddress);
    render();
    const unit = State.baseUnits.find(u => u.tokenId === tokenId);
    if (unit) showMintFeedback(unit);
  } catch (err) {
    const reason = err.code === 'ACTION_REJECTED'
                 ? 'User rejected the transaction.'
                 : err.reason
                 ? String(err.reason)
                 : err.shortMessage || err.message || 'Unknown error.';
    console.error('[mint-base]', err);
    errorCard('MINT FAILED', reason);
  } finally {
    hideLoading();
  }
}

async function handleMintSub() {
  const unit = State.selectedBase;
  if (!unit) { toast('SELECT A BASE UNIT FIRST', 'warning'); return; }
  if (unit.isCompleted) { toast('UNIT ALREADY COMPLETED', 'warning'); return; }

  const ok = await openMintSubDialog(unit);
  if (!ok) return;

  showLoading('MINTING SUB UNIT');
  const tokenId = unit.tokenId;
  try {
    await Api.mintSubUnit(tokenId);
    await loadUserData(State.userAddress);
    render();
    const updated = State.baseUnits.find(u => u.tokenId === tokenId);
    if (updated) showSubMintFeedback(updated);
  } catch (err) {
    const reason = err.code === 'ACTION_REJECTED'
                 ? 'User rejected the transaction.'
                 : err.reason
                 ? String(err.reason)
                 : err.shortMessage || err.message || 'Unknown error.';
    console.error('[mint-sub]', err);
    errorCard('MINT FAILED', reason);
  } finally {
    hideLoading();
  }
}


/* ═══════════════════════════════════════════════════════════════════════════
   EVENT DELEGATION
══════════════════════════════════════════════════════════════════════════════ */

document.body.addEventListener('click', function (e) {
  const el = e.target.closest('[data-action]');
  if (!el) {
    if (State.selectedBaseIndex !== null && e.target.closest('.base-view')) {
      State.selectedBaseIndex = null;
      render();
    }
    return;
  }
  const a = el.dataset.action;
  if      (a === 'connect')        handleConnect();
  else if (a === 'disconnect')     handleDisconnect();
  else if (a === 'nav')            handleNav(el.dataset.view);
  else if (a === 'select-card')    handleSelectCard(+el.dataset.index);
  else if (a === 'mint-base')      handleMintBase();
  else if (a === 'mint-sub')       handleMintSub();
  else if (a === 'close-panel')    handleClosePanel();
  else if (a === 'confirm-ok')     closeConfirm(true);
  else if (a === 'confirm-cancel') closeConfirm(false);
});

document.addEventListener('keydown', function (e) {
  const openDialog = [El.confirmDialog, El.mintBaseDialog, El.mintSubDialog]
    .find(el => el.style.display === 'flex');

  if (!openDialog) return;

  if (e.key === 'Escape') { closeConfirm(false); return; }
  if (e.key !== 'Tab') return;

  const focusable = Array.from(openDialog.querySelectorAll(
    'button, [href], input, [tabindex]:not([tabindex="-1"])'
  )).filter(el => !el.disabled);

  if (!focusable.length) { e.preventDefault(); return; }

  const first = focusable[0];
  const last  = focusable[focusable.length - 1];

  if (e.shiftKey && document.activeElement === first) {
    e.preventDefault(); last.focus();
  } else if (!e.shiftKey && document.activeElement === last) {
    e.preventDefault(); first.focus();
  }
});


/* ═══════════════════════════════════════════════════════════════════════════
   INIT
══════════════════════════════════════════════════════════════════════════════ */

async function init() {
  cacheElements();
  State.selectedBaseIndex = null;
  State.activeView        = 'intro';

  if (window.ethereum) {
    const hex = await window.ethereum.request({ method: 'eth_chainId' }).catch(() => null);
    if (hex) State.chainId = Number(BigInt(hex));
  }

  State.chainId = await Api.initNetwork(State.chainId);

  try {
    await loadConstants();
  } catch (err) {
    console.error('[init] loadConstants failed:', err);
    render();
    errorCard('CONTRACTS NOT FOUND', 'Is Anvil running? Start with: anvil  then deploy: forge script script/DeployAnvil.s.sol --broadcast');
    _scheduleSplashHide();
    return;
  }

  // Auto-connect if MetaMask already has permission (e.g. after network-switch reload)
  // eth_accounts is silent — no popup, returns [] if no permission
  if (window.ethereum) {
    const accounts = await window.ethereum.request({ method: 'eth_accounts' }).catch(() => []);
    if (accounts.length > 0) {
      await handleConnect();
      if (State.connected) { _scheduleSplashHide(); return; }
    }
  }

  render();
  _scheduleSplashHide();
}

document.addEventListener('DOMContentLoaded', init);
