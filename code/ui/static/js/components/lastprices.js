/**
 * lastprices.js — Last trade price per sym/exchange.
 *
 * Data arrives via the WebSocket 'lastprices' event (pushed every 2s).
 * Source: .cryptoagg.getlastprices — columns: sym, exchange, time, price, size
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

export class LastPrices {
  #container;

  constructor(containerEl) {
    this.#container = containerEl;
  }

  init() {
    this.#container.innerHTML = `
      <div class="grid-wrap">
        <table id="lp-table">
          <thead>
            <tr>
              <th>Symbol</th>
              <th>Exchange</th>
              <th>Last Price</th>
              <th>Size</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody id="lp-body">
            <tr><td colspan="5" class="text-muted">Waiting for data...</td></tr>
          </tbody>
        </table>
      </div>`;
  }

  /** Called with the array of lastprices rows from the WebSocket feed. */
  update(rows) {
    if (!rows.length) return;
    const tbody = document.getElementById('lp-body');
    if (!tbody) return;

    // Build a keyed map from existing rows so we only touch changed cells
    for (const row of rows) {
      const key = `lp-${row.sym}-${row.exchange}`;
      let tr = document.getElementById(key);
      if (!tr) {
        // First time we see this sym/exchange — add a row
        tbody.innerHTML = tbody.innerHTML === '<tr><td colspan="5" class="text-muted">Waiting for data...</td></tr>'
          ? ''
          : tbody.innerHTML;
        tr = document.createElement('tr');
        tr.id = key;
        tr.innerHTML = `
          <td>${row.sym}</td>
          <td>${row.exchange}</td>
          <td id="${key}-price" class="dash">-</td>
          <td id="${key}-size"  class="dash">-</td>
          <td id="${key}-time"  class="dash text-muted">-</td>`;
        tbody.appendChild(tr);
      }
      this.#set(`${key}-price`, fmt(row.price));
      this.#set(`${key}-size`,  fmt(row.size, 4));
      this.#set(`${key}-time`,  fmtTime(row.time));
    }
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
