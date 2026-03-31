// Configuration of crypto symbol mapping
// Loads symconfig and symmap CSVs into .crypto namespace.
// The runtime symbol table (.crypto.rtsymmap) is populated at startup via
// IPC from the Python discovery process and takes precedence over the static CSV.

\d .crypto

// Static symbol config: canonical_symbol, enabled, binance, kraken, coinbase
symconfig:@[
  {("*BBB";enlist ",") 0:hsym first .proc.getconfigfile["symconfig.csv"]};
  `;
  {.lg.e[`cryptofeed;"failed to load symconfig.csv: ",x]; ([]canonical_symbol:`symbol$();enabled:`boolean$();binance:`boolean$();kraken:`boolean$();coinbase:`boolean$())}
  ]

// Static symbol map: canonical_symbol, venue, venue_symbol, base, quote,
//   instrument_type, tick_size, mapping_verified
// mapping_verified=true rows override auto-discovered rows for the same
// venue + venue_symbol combination (see discovery.py for auto-discovery logic).
symmap:@[
  {("***** F*";enlist ",") 0:hsym first .proc.getconfigfile["symmap.csv"]};
  `;
  {.lg.e[`cryptofeed;"failed to load symmap.csv: ",x]; ([]canonical_symbol:`symbol$();venue:`symbol$();venue_symbol:`symbol$();base:`symbol$();quote:`symbol$();instrument_type:`symbol$();tick_size:`float$();mapping_verified:`boolean$())}
  ]

// Runtime symbol map — populated by upd_discovery IPC calls from Python feeds.
// Merged with static symmap at query time; runtime rows take precedence
// unless a static row has mapping_verified=true for the same venue+venue_symbol.
rtsymmap:([]
  canonical_symbol:`symbol$();
  venue:`symbol$();
  venue_symbol:`symbol$();
  base:`symbol$();
  quote:`symbol$();
  instrument_type:`symbol$();
  tick_size:`float$();
  mapping_verified:`boolean$()
  )

\d .
