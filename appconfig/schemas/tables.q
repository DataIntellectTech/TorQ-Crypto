// Canonical table schemas for TorQ-Crypto
// Loaded by tickerplant at startup via process.csv -schemafile arg
// All tables use fully typed empty lists — never untyped ()

// ---------------------------------------------------------------------------
// 1. trade — append-only raw trades from all venues
// ---------------------------------------------------------------------------
trade:([]
  time:`timestamp$();
  sym:`symbol$();
  venue:`symbol$();
  price:`float$();
  size:`float$();
  side:`symbol$();
  venue_sym:`symbol$();
  seq:`long$()
  )

// ---------------------------------------------------------------------------
// 2. quote — top-of-book snapshots (optional stream, table must exist)
// ---------------------------------------------------------------------------
quote:([]
  time:`timestamp$();
  sym:`symbol$();
  venue:`symbol$();
  bid:`float$();
  ask:`float$();
  bsize:`float$();
  asize:`float$();
  venue_sym:`symbol$()
  )

// ---------------------------------------------------------------------------
// 3. lastprice — unkeyed intraday snapshot; latest per sym+venue via select last
// ---------------------------------------------------------------------------
lastprice:([]
  time:`timestamp$();
  sym:`g#`symbol$();
  venue:`symbol$();
  price:`float$();
  bid:`float$();
  ask:`float$();
  mid:`float$()
  )

// ---------------------------------------------------------------------------
// 4. consolidatedmid — timeseries aggregation across venues
// ---------------------------------------------------------------------------
consolidatedmid:([]
  time:`timestamp$();
  sym:`symbol$();
  mid:`float$();
  n_venues:`int$();
  spread_dispersion:`float$();
  outlier_flag:`boolean$()
  )

// ---------------------------------------------------------------------------
// 5. symbology — keyed instrument mapping, key: venue+venue_sym
// ---------------------------------------------------------------------------
symbology:([venue:`symbol$(); venue_sym:`symbol$()]
  canonical_sym:`symbol$();
  base:`symbol$();
  quote:`symbol$();
  instrument_type:`symbol$();
  tick_size:`float$();
  price_precision:`int$()
  )
