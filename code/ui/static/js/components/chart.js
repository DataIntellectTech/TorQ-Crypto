/**
 * chart.js — Mid price chart component.
 *
 * Renders a Chart.js line chart showing consolidated mid price over time.
 * History is loaded via REST on init and on symbol change; live ticks
 * append points from the WebSocket consolidated feed.
 *
 * Usage:
 *   const chart = new MidChart(document.getElementById('mid-chart'), feed, CONFIG);
 *   chart.init();
 *   feed.addEventListener('consolidated', e => chart.onConsolidated(e.detail));
 *
 * Extensibility:
 *   - Swap the dataset config below to change chart type or styling.
 *   - Add more datasets to show multiple series (e.g. bid/ask alongside mid).
 *   - CONFIG.historyMins controls the rolling window.
 */

export class MidChart {
  #canvas;
  #feed;
  #config;
  #chart  = null;
  #sym;

  constructor(canvasEl, feed, config) {
    this.#canvas = canvasEl;
    this.#feed   = feed;
    this.#config = config;
    this.#sym    = config.symbols[0];
  }

  init() {
    // Chart is accessed as a global (loaded via UMD script tag in index.html)
    this.#chart = new Chart(this.#canvas.getContext('2d'), {
      type: 'line',
      data: {
        datasets: [{
          label: 'Consolidated Mid',
          data: [],
          borderColor: '#4af',
          backgroundColor: 'rgba(68,170,255,0.07)',
          pointRadius: 0,
          borderWidth: 1.5,
          tension: 0.1,
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        scales: {
          x: {
            type: 'time',
            time: { unit: 'minute' },
            ticks: { color: '#666', maxTicksLimit: 10 },
            grid:  { color: '#222' },
          },
          y: {
            ticks: { color: '#666' },
            grid:  { color: '#222' },
          }
        },
        plugins: { legend: { display: false } }
      }
    });

    this.#loadHistory(this.#sym);
  }

  /** Switch the displayed symbol and reload history. */
  setSym(sym) {
    this.#sym = sym;
    this.#loadHistory(sym);
  }

  /** Called with the array of consolidated rows from the WebSocket feed. */
  onConsolidated(rows) {
    const row = rows.find(r => r.sym === this.#sym);
    if (row?.consolidated_mid != null) {
      this.#append(row.update_time, row.consolidated_mid);
    }
  }

  // ---------------------------------------------------------------------------

  async #loadHistory(sym) {
    this.#clear();
    try {
      const rows = await this.#feed.fetchHistory(sym, this.#config.historyMins);
      for (const row of rows) {
        const ts  = row.date || row.time || row.update_time;
        const mid = row.closePrice ?? row.consolidated_mid ?? row.price;
        if (ts != null && mid != null) this.#append(ts, mid);
      }
    } catch (e) {
      console.error('history fetch failed:', e);
    }
  }

  #append(ts, mid) {
    const ds     = this.#chart.data.datasets[0];
    const cutoff = Date.now() - this.#config.historyMins * 60 * 1000;
    ds.data.push({ x: new Date(ts), y: mid });
    while (ds.data.length > 0 && ds.data[0].x < cutoff) ds.data.shift();
    this.#chart.update('none');
  }

  #clear() {
    this.#chart.data.datasets[0].data = [];
    this.#chart.update('none');
  }
}
