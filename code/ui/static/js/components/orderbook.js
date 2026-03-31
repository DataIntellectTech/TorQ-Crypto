/**
 * orderbook.js — L2 order book panel.
 *
 * Calls GET /api/orderbook?sym=X every POLL_MS milliseconds.
 * Source: orderbook[] in cryptolib.q — columns: exchange_b, bidSize, bid, ask, askSize, exchange_a
 *
 * Renders a side-by-side bid/ask depth table.
 */

const fmt = (v, dp = 2) =>
  v == null || (typeof v === 'number' && isNaN(v))
    ? '-'
    : Number(v).toLocaleString('en-US', { minimumFractionDigits: dp, maximumFractionDigits: dp });

const POLL_MS = 5000;

export class OrderBook {
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
    this.#container.innerHTML = `
      <div class="grid-wrap">
        <table id="ob-table">
          <thead>
            <tr>
              <th>Bid Exchange</th>
              <th>Bid Size</th>
              <th>Bid</th>
              <th>Ask</th>
              <th>Ask Size</th>
              <th>Ask Exchange</th>
            </tr>
          </thead>
          <tbody id="ob-body">
            <tr><td colspan="6" class="text-muted">Waiting for data...</td></tr>
          </tbody>
        </table>
      </div>`;
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
      const rows = await this.#feed.fetchOrderBook(this.#sym);
      this.#render(rows);
    } catch (e) {
      console.error('orderbook fetch failed:', e);
    }
  }

  #render(rows) {
    const tbody = document.getElementById('ob-body');
    if (!tbody) return;
    if (!rows.length) {
      tbody.innerHTML = `<tr><td colspan="6" class="text-muted">No data for ${this.#sym}</td></tr>`;
      return;
    }
    tbody.innerHTML = rows.map(r => `
      <tr>
        <td class="text-muted">${r.exchange_b ?? '-'}</td>
        <td>${fmt(r.bidSize, 4)}</td>
        <td class="bid-price">${fmt(r.bid)}</td>
        <td class="ask-price">${fmt(r.ask)}</td>
        <td>${fmt(r.askSize, 4)}</td>
        <td class="text-muted">${r.exchange_a ?? '-'}</td>
      </tr>`).join('');
  }
}
