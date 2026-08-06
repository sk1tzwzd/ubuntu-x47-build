// Crop app.nerovia.ai to chart or open-positions for X47 Firefox widgets.
(() => {
  const OVERRIDE_KEY = 'x47NeroviaSelectors';

  function modeFromLocation() {
    try {
      const u = new URL(location.href);
      const q = (u.searchParams.get('x47') || '').toLowerCase();
      if (q === 'chart' || q === 'positions')
        return q;
      const h = (u.hash || '').toLowerCase();
      if (h.includes('x47-positions') || h.includes('positions'))
        return 'positions';
      if (h.includes('x47-chart') || h.includes('chart'))
        return 'chart';
    } catch (_e) { /* ignore */ }
    return null;
  }

  function textOf(el) {
    return (el?.innerText || el?.textContent || '').replace(/\s+/g, ' ').trim();
  }

  function findByText(re, root = document.body) {
    if (!root)
      return null;
    const all = root.querySelectorAll('h1,h2,h3,h4,button,a,div,span,section,main,li,p');
    let best = null;
    let bestScore = 0;
    for (const el of all) {
      const t = textOf(el);
      if (!t || t.length > 120)
        continue;
      if (!re.test(t))
        continue;
      // Prefer short, specific nodes.
      const score = 1000 - t.length + (el.children.length ? 10 : 30);
      if (score > bestScore) {
        best = el;
        bestScore = score;
      }
    }
    return best;
  }

  function climbToPanel(start, pred, maxUp = 12) {
    let n = start;
    for (let i = 0; i < maxUp && n && n !== document.body; i++) {
      if (pred(n))
        return n;
      n = n.parentElement;
    }
    return start;
  }

  function loadOverrides() {
    // Optional JSON in page localStorage set by user for brittle class hashes.
    try {
      const raw = localStorage.getItem(OVERRIDE_KEY);
      if (!raw)
        return {};
      return JSON.parse(raw) || {};
    } catch (_e) {
      return {};
    }
  }

  function findChartRoot(overrides) {
    if (overrides.chart)
      try {
        const el = document.querySelector(overrides.chart);
        if (el)
          return el;
      } catch (_e) { /* bad selector */ }

    // TradingView host / iframe / canvas cluster.
    const tv = document.querySelector(
      'iframe[src*="tradingview"], iframe[id*="tradingview"], div[id*="tradingview"], div[class*="tradingview"]');
    if (tv) {
      return climbToPanel(tv, el => {
        const r = el.getBoundingClientRect();
        return r.height > 280 && r.width > 400;
      }, 14);
    }

    const scanning = findByText(/^SCANNING$/i) || findByText(/SCANNING/i);
    if (scanning) {
      return climbToPanel(scanning, el => {
        const t = textOf(el);
        const r = el.getBoundingClientRect();
        return r.height > 320 && r.width > 480 && (/MACD|BTC|TradingView/i.test(t) || el.querySelector('canvas,iframe'));
      }, 16);
    }

    const macd = findByText(/MACD\s*\(/i);
    if (macd) {
      return climbToPanel(macd, el => {
        const r = el.getBoundingClientRect();
        return r.height > 320 && r.width > 480;
      }, 16);
    }

    // Largest canvas-bearing container.
    let best = null;
    let bestArea = 0;
    for (const canvas of document.querySelectorAll('canvas')) {
      const panel = climbToPanel(canvas, el => {
        const r = el.getBoundingClientRect();
        return r.height > 240 && r.width > 360;
      }, 10);
      if (!panel)
        continue;
      const r = panel.getBoundingClientRect();
      const area = r.width * r.height;
      if (area > bestArea) {
        best = panel;
        bestArea = area;
      }
    }
    return best;
  }

  function findPositionsRoot(overrides) {
    if (overrides.positions)
      try {
        const el = document.querySelector(overrides.positions);
        if (el)
          return el;
      } catch (_e) { /* bad selector */ }

    const heading = findByText(/Open Positions/i);
    if (heading) {
      return climbToPanel(heading, el => {
        const t = textOf(el);
        const r = el.getBoundingClientRect();
        return r.width > 480 && r.height > 120 &&
          /SYMBOL|UNREALISED|SIDE|ENTRY/i.test(t);
      }, 14);
    }

    // Table with trading columns.
    for (const table of document.querySelectorAll('table, [role="table"]')) {
      const t = textOf(table);
      if (/SYMBOL/i.test(t) && /UNREALISED|SIDE/i.test(t)) {
        return climbToPanel(table, el => {
          const r = el.getBoundingClientRect();
          return r.width > 480 && /Open Positions|History|Activity/i.test(textOf(el));
        }, 10) || table;
      }
    }
    return null;
  }

  function clearMarks() {
    document.documentElement.removeAttribute('data-x47-widget');
    for (const el of document.querySelectorAll('[data-x47-keep],[data-x47-hide]')) {
      el.removeAttribute('data-x47-keep');
      el.removeAttribute('data-x47-hide');
    }
  }

  function markKeepTree(target) {
    if (!target)
      return;
    let n = target;
    while (n && n !== document.documentElement) {
      n.setAttribute('data-x47-keep', '1');
      n = n.parentElement;
    }
    // Hide obvious chrome siblings (nav/aside/header) outside the keep path.
    for (const el of document.querySelectorAll('nav, aside, header, [class*="sidebar" i], [class*="SideBar" i]')) {
      if (!el.hasAttribute('data-x47-keep'))
        el.setAttribute('data-x47-hide', '1');
    }
    // Hide top-level body children that are not ancestors of target.
    for (const child of document.body.children) {
      if (!child.hasAttribute('data-x47-keep') && !child.contains(target))
        child.setAttribute('data-x47-hide', '1');
    }
  }

  function apply() {
    const mode = modeFromLocation();
    if (!mode) {
      clearMarks();
      return;
    }
    const overrides = loadOverrides();
    clearMarks();
    document.documentElement.setAttribute('data-x47-widget', mode);
    const target = mode === 'positions'
      ? findPositionsRoot(overrides)
      : findChartRoot(overrides);
    if (target) {
      markKeepTree(target);
      try {
        target.scrollIntoView({block: 'start', inline: 'nearest'});
      } catch (_e) { /* ignore */ }
    } else {
      // Keep page usable until SPA finishes hydrating.
      document.documentElement.setAttribute('data-x47-widget', mode);
    }
  }

  let timer = 0;
  function schedule() {
    if (timer)
      clearTimeout(timer);
    timer = setTimeout(apply, 120);
  }

  apply();
  const obs = new MutationObserver(schedule);
  if (document.body)
    obs.observe(document.body, {childList: true, subtree: true});
  else
    document.addEventListener('DOMContentLoaded', () => {
      apply();
      obs.observe(document.body, {childList: true, subtree: true});
    }, {once: true});

  window.addEventListener('hashchange', schedule);
  window.addEventListener('popstate', schedule);
  // SPA soft-navigations.
  const push = history.pushState;
  const replace = history.replaceState;
  history.pushState = function (...args) {
    const r = push.apply(this, args);
    schedule();
    return r;
  };
  history.replaceState = function (...args) {
    const r = replace.apply(this, args);
    schedule();
    return r;
  };

  // Retry a few times while TradingView mounts.
  let tries = 0;
  const boot = setInterval(() => {
    tries += 1;
    apply();
    if (tries >= 20)
      clearInterval(boot);
  }, 750);
})();
