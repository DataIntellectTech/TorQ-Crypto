/**
 * grid.js — Consolidated price grid.
 *
 * One row per canonical symbol showing:
 *   - Per-venue best bid / ask (dynamic from venue_names)
 *   - Consolidated bid, ask, mid
 *   - Spread (consolidated_ask - consolidated_bid)
 *   - Spread dispersion across venues (bps)
 *   - Venue count
 *   - Outlier flag
 *   - Last update time
 */

const fmt  = (v, dp = 2) =>
  v == null || (typeof v === 'number' && isNaN(v))
    ? '-'
    : Number(v).toLocaleString('en-US', { minimumFractionDigits: dp, maximumFractionDigits: dp });

const fmtTime = (ts) => {
  if (!ts) return '-';
  const d = new Date(ts);
  return isNaN(d) ? '-' : d.toLocaleTimeString('en-GB', { hour12: false });
};

export class PriceGrid {
  #container;
  #config;

  constructor(containerEl, config) {
    this.#container = containerEl;
    this.#config    = config;
  }

  init() {
    this.#container.innerHTML = `
      <div class="grid-wrap">
        <table>
          <thead>
            <tr>
              <th>Symbol</th>
              <th>Venues (Bid / Ask)</th>
              <th>Consol. Bid</th>
              <th>Consol. Ask</th>
              <th>Consol. Mid</th>
              <th>Spread</th>
              <th>Dispersion (bps)</th>
              <th>Venues</th>
              <th>Outlier</th>
              <th>Updated</th>
            </tr>
          </thead>
          <tbody>
            ${this.#config.symbols.map(s => this.#rowHtml(s)).join('')}
          </tbody>
        </table>
      </div>`;
  }

  update(rows) {
    for (const row of rows) {
      const { sym } = row;
      if (!this.#config.symbols.includes(sym)) continue;

      const bid = row.consolidated_bid;
      const ask = row.consolidated_ask;
      const spread = (bid != null && ask != null) ? ask - bid : null;

      this.#set(`cell-${sym}-cbid`,  fmt(bid));
      this.#set(`cell-${sym}-cask`,  fmt(ask));
      this.#set(`cell-${sym}-cmid`,  fmt(row.consolidated_mid));
      this.#set(`cell-${sym}-sprd`,  fmt(spread));
      this.#set(`cell-${sym}-disp`,  fmt(row.spread_dispersion, 1));
      this.#set(`cell-${sym}-vcnt`,  row.venue_count ?? '-');
      this.#set(`cell-${sym}-time`,  fmtTime(row.update_time));

      const outlierEl = document.getElementById(`cell-${sym}-outlier`);
      if (outlierEl) {
        outlierEl.textContent  = row.outlier_flag ? '\u2691' : '';
        outlierEl.className    = row.outlier_flag ? 'outlier' : '';
      }

      if (row.venue_names && row.venue_bids) {
        const names = [].concat(row.venue_names);
        const bids  = [].concat(row.venue_bids);
        const asks  = [].concat(row.venue_asks);
        const text  = names.map((v, i) => `${v}: ${fmt(bids[i])} / ${fmt(asks[i])}`).join('  |  ');
        this.#set(`cell-${sym}-venues`, text);
      }
    }
  }

  // ---------------------------------------------------------------------------

  #rowHtml(sym) {
    return `
      <tr id="row-${sym}">
        <td>${sym}</td>
        <td id="cell-${sym}-venues"  class="dash venues-cell">-</td>
        <td id="cell-${sym}-cbid"    class="dash">-</td>
        <td id="cell-${sym}-cask"    class="dash">-</td>
        <td id="cell-${sym}-cmid"    class="dash">-</td>
        <td id="cell-${sym}-sprd"    class="dash">-</td>
        <td id="cell-${sym}-disp"    class="dash">-</td>
        <td id="cell-${sym}-vcnt"    class="dash">-</td>
        <td id="cell-${sym}-outlier" class="dash">-</td>
        <td id="cell-${sym}-time"    class="dash text-muted">-</td>
      </tr>`;
  }

  #set(id, text) {
    const el = document.getElementById(id);
    if (!el) return;
    const val = String(text);
    if (el.textContent === val) return;
    el.textContent = val;
    el.classList.remove('dash', 'updated');
    void el.offsetWidth;
    el.classList.add('updated');
  }
}
