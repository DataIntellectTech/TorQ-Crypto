/**
 * app.js — Application entry point.
 *
 * Owns CONFIG and wires all components to the data feed.
 *
 * To add a new panel:
 *   1. Create a component class in js/components/
 *   2. Import it here
 *   3. Add a mount point in index.html
 *   4. Instantiate and wire below
 */

import { DataFeed }   from './api.js';
import { PriceGrid }  from './components/grid.js';
import { LastPrices } from './components/lastprices.js';
import { OrderBook }  from './components/orderbook.js';
import { Arbitrage }  from './components/arbitrage.js';
import { MidChart }   from './components/chart.js';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const CONFIG = {
  symbols:     ['BTC-USD', 'BTC-USDT', 'ETH-USD', 'ETH-USDT'],
  historyMins: 30,
};

// ---------------------------------------------------------------------------
// Connection status
// ---------------------------------------------------------------------------
const statusEl = document.getElementById('conn-status');
const STATUS_LABELS = { connected: 'Connected', reconnecting: 'Reconnecting...', disconnected: 'Disconnected' };

function setStatus(state) {
  statusEl.className   = state;
  statusEl.textContent = STATUS_LABELS[state] ?? state;
}

// ---------------------------------------------------------------------------
// Symbol selector — shared across chart, order book, and arbitrage panels
// ---------------------------------------------------------------------------
const symSelect = document.getElementById('sym-select');
for (const sym of CONFIG.symbols) {
  const opt = document.createElement('option');
  opt.value = opt.textContent = sym;
  symSelect.appendChild(opt);
}

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------
const feed      = new DataFeed();
const grid      = new PriceGrid(document.getElementById('price-grid'), CONFIG);
const lastPrices = new LastPrices(document.getElementById('last-prices'));
const orderBook = new OrderBook(document.getElementById('order-book'), feed, CONFIG.symbols[0]);
const arbitrage = new Arbitrage(document.getElementById('arbitrage'),  feed, CONFIG.symbols[0]);
const chart     = new MidChart(document.getElementById('mid-chart'),   feed, CONFIG);

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------
feed.addEventListener('status',       e => setStatus(e.detail));
feed.addEventListener('consolidated', e => grid.update(e.detail));
feed.addEventListener('lastprices',   e => lastPrices.update(e.detail));
feed.addEventListener('consolidated', e => chart.onConsolidated(e.detail));

symSelect.addEventListener('change', e => {
  chart.setSym(e.target.value);
  orderBook.setSym(e.target.value);
  arbitrage.setSym(e.target.value);
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
grid.init();
lastPrices.init();
orderBook.init();
arbitrage.init();
chart.init();
feed.connect();
