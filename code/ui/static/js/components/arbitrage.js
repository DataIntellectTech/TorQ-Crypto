/**
 * arbitrage.js — Cross-venue arbitrage panel.
 *
 * Calls GET /api/arbitrage?sym=X every POLL_MS milliseconds.
 * Source: arbitrage[] in cryptolib.q — topofbook data extended with profit + arbitrage columns.
 * Columns: exchangeTime, {exchange}Bid, {exchange}Ask, ..., profit, arbitrage
 *
 * Highlights rows where arbitrage=true (profit opportunity detected).
 */

const fmt = (v, dp = 2) =>
  v == null || (typeof v === 'number' && isNaN(v))
    ? '-'
    : Number(v).toLocaleString('en-US', { minimumFractionDigits: dp, maximumFractionDigits: dp });

const fmtTime = (ts) => {
  if (!ts) return '-';
  const d = new Date(ts);
  return isNaN(d) ? '-' : d.toLocaleTimeString('en-GB', { hour12: false });
};

const POLL_MS = 5000;

export class Arbitrage {
  #container;
  #feed;
  #sym;
  #timer = null;

  constructor(containerEl, feed, initialSym) {
    this.#container = containerEl;
    this.#feed      = feed;
    this.#sym       = initialSym;
  }

  init() {
    this.#container.innerHTML = `<p class="text-muted">Waiting for data...</p>`;
    this.#startPolling();
  }

  setSym(sym) {
    this.#sym = sym;
    this.#poll();
  }

  // ---------------------------------------------------------------------------

  #startPolling() {
    this.#poll();
    this.#timer = setInterval(() => this.#poll(), POLL_MS);
  }

  async #poll() {
    try {
      const rows = await this.#feed.fetchArbitrage(this.#sym);
      this.#render(rows);
    } catch (e) {
      console.error('arbitrage fetch failed:', e);
    }
  }

  #render(rows) {
    if (!rows.length) {
      this.#container.innerHTML = `<p class="text-muted">No data for ${this.#sym}</p>`;
      return;
    }

    // Derive columns from the first row, keeping exchangeTime first, profit/arbitrage last
    const allCols    = Object.keys(rows[0]);
    const fixedFirst = ['exchangeTime'];
    const fixedLast  = ['profit', 'arbitrage'];
    const midCols    = allCols.filter(c => !fixedFirst.includes(c) && !fixedLast.includes(c));
    const cols       = [...fixedFirst, ...midCols, ...fixedLast];

    const headerHtml = cols.map(c => `<th>${c}</th>`).join('');

    const rowsHtml = rows.map(r => {
      const arb   = r.arbitrage === true || r.arbitrage === 1;
      const cells = cols.map(c => {
        if (c === 'exchangeTime') return `<td class="text-muted">${fmtTime(r[c])}</td>`;
        if (c === 'profit')       return `<td class="${arb ? 'arb-profit' : ''}">${fmt(r[c], 4)}</td>`;
        if (c === 'arbitrage')    return `<td class="${arb ? 'arb-flag' : ''}">${arb ? '\u2714' : ''}</td>`;
        return `<td>${fmt(r[c])}</td>`;
      }).join('');
      return `<tr class="${arb ? 'arb-row' : ''}">${cells}</tr>`;
    }).join('');

    this.#container.innerHTML = `
      <div class="grid-wrap">
        <table>
          <thead><tr>${headerHtml}</tr></thead>
          <tbody>${rowsHtml}</tbody>
        </table>
      </div>`;
  }
}
