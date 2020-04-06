# TorQ-Crpyto Configuration

- Feeds
Available feeds with this pack include:
 - OKEX (okex)
 - DigiFinex (finex)
 - Huobi (huobi)
 - ZB (zb)
 - Blue Helix (bhex)
To change what feeds are available??

- Syms
The default available syms are Bitcoin/Tether (BTCUSDT) and Ethereum/Tether (ETHUSDT), but other syms may be switched on.
Navigate to `appconfig/symconfig.csv` and edit the table to turn on specific syms for specific exchanges.

- Frequency of querying feed APIs and limit of depth of market
The default time and market depth limit for querying feed API's is every 30 seconds and 10 records.
This frequency and limit of depth can be changed in `appconfig/settings/default.q`.
