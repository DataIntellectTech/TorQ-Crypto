# TorQ Crypto


![Aquaq Logo](graphics/aquaqlogo.PNG)


TorQ-Crypto provides an example of how an application can be built and
deployed on top of the TorQ framework. This package delivers real-time
cryptocurrency market data via WebSocket feeds from three major exchanges,
a consolidated order book aggregation layer, and a live browser UI.

- [TorQ Manual](https://dataintellecttech.github.io/TorQ/)
- [TorQ GitHub](https://github.com/DataIntellectTech/TorQ)
- [Testing](testing.md)

TorQ-Crypto includes:

- Real-time WebSocket feeds from **Binance**, **Kraken**, and **Coinbase**
- Correct instrument distinction: BTC-USD (FIAT) and BTC-USDT (Tether) are separate
- Auto-discovery of available instruments at startup via exchange REST APIs
- Consolidated order book maintained in real time across venues
- Automatic recovery via TP log replay (kdb+) and REST backfill (Python)
- Minimal live UI: price grid and 30-minute mid chart served over WebSocket
- Custom API functions for OHLC, orderbook, top-of-book, arbitrage, and consolidated book queries

### Architecture

```
Python feed manager
  ├── Binance WebSocket  ─┐
  ├── Kraken  WebSocket  ─┤── IPC ──▶ pythonfeed1 ──▶ tickerplant1
  └── Coinbase WebSocket ─┘
                                           │
                         ┌─────────────────┼──────────────────┐
                         ▼                 ▼                  ▼
                       rdb1             wdb1             cryptoagg1
                       hdb1/2                          (consolidated book)
                         │                                    │
                         └──────────────┐ ┌──────────────────┘
                                        ▼ ▼
                                      gateway1
                                          │
                                       UI server ──▶ browser
```

*email:* <support@aquaq.co.uk>

*web:* [www.aquaq.co.uk](http://www.aquaq.co.uk)
