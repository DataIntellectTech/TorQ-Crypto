/**
 * api.js — Data feed layer.
 *
 * DataFeed extends EventTarget and emits:
 *   'status'       detail: 'connected' | 'reconnecting' | 'disconnected'
 *   'consolidated' detail: array of consolidated order book rows
 *   'lastprices'   detail: array of last trade price rows (sym, exchange, price, size, time)
 *
 * REST methods (return promises):
 *   fetchHistory(sym, mins)  — ohlc trade data
 *   fetchLastBook(sym)       — per-venue top-of-book depth
 *   fetchOrderBook(sym)      — L2 order book
 *   fetchArbitrage(sym)      — cross-venue arbitrage data
 */

const WS_URL   = `ws://${window.location.host}/ws`;
const API_BASE = window.location.origin;
const RETRY_MS = 5000;

export class DataFeed extends EventTarget {
  #ws         = null;
  #retryTimer = null;

  connect() {
    this.#emit('status', 'reconnecting');
    this.#ws = new WebSocket(WS_URL);
    this.#ws.onopen    = ()    => { this.#emit('status', 'connected'); };
    this.#ws.onmessage = (evt) => { this.#onMessage(evt); };
    this.#ws.onclose   = ()    => { this.#onDisconnect(); };
    this.#ws.onerror   = ()    => { this.#onDisconnect(); };
  }

  disconnect() {
    clearTimeout(this.#retryTimer);
    this.#ws?.close();
    this.#ws = null;
  }

  async fetchHistory(sym, mins = 30) {
    return this.#get(`/api/history?sym=${encodeURIComponent(sym)}&mins=${mins}`);
  }

  async fetchLastBook(sym) {
    return this.#get(`/api/lastbook?sym=${encodeURIComponent(sym)}`);
  }

  async fetchOrderBook(sym) {
    return this.#get(`/api/orderbook?sym=${encodeURIComponent(sym)}`);
  }

  async fetchArbitrage(sym) {
    return this.#get(`/api/arbitrage?sym=${encodeURIComponent(sym)}`);
  }

  // ---------------------------------------------------------------------------

  async #get(path) {
    const resp = await fetch(`${API_BASE}${path}`);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
  }

  #onMessage(evt) {
    let msg;
    try { msg = JSON.parse(evt.data); } catch { return; }
    switch (msg.type) {
      case 'consolidated': if (Array.isArray(msg.data)) this.#emit('consolidated', msg.data); break;
      case 'lastprices':   if (Array.isArray(msg.data)) this.#emit('lastprices',   msg.data); break;
    }
  }

  #onDisconnect() {
    this.#emit('status', 'disconnected');
    clearTimeout(this.#retryTimer);
    this.#retryTimer = setTimeout(() => this.connect(), RETRY_MS);
  }

  #emit(type, detail) {
    this.dispatchEvent(new CustomEvent(type, { detail }));
  }
}
