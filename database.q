finex:([]time:`timestamp$(); sym:`g#`symbol$();exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())
bhex:huobi:okex:zb:finex
exchange:([]time:`timestamp$(); sym:`g#`symbol$(); exchangeTime:`timestamp$(); exchange:`symbol$();bid:`float$(); bidSize:`float$(); ask:`float$();askSize:`float$())
exchange_top:exchange

// Real-time trade stream from WebSocket feeds (append-only, time-partitioned in HDB)
trade:([]
  time:`timestamp$();
  sym:`g#`symbol$();
  exchange:`symbol$();
  price:`float$();
  size:`float$();
  side:`symbol$();
  venue_sym:`symbol$()
  )

// Note: symboldiscovery is NOT defined here — it is not a tickerplant-routed table.
// .crypto.symmap (same schema) is initialised in code/processes/pythonfeed.q.


