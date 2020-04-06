# TorQ-Crpyto Configuration

### Feeds  
Available feeds with this pack include the following:    
 - OKEX (okex) API: [https://www.okex.com/docs/en/ ]
 - DigiFinex (finex) API: [https://docs.digifinex.vip/en-ww/v3/ ]
 - Huobi (huobi) API: [https://huobiapi.github.io/docs/spot/v1/en/#introduction ]
 - ZB (zb) API: [https://www.zb.com/api]
 - Blue Helix (bhex) API: [https://github.com/bhexopen/BHEX-OpenApi ]  
To change what feeds are available??  

### Sym Configuration  
The default available syms are Bitcoin/Tether (BTCUSDT) and Ethereum/Tether (ETHUSDT), but other syms may be switched on.
Navigate to `appconfig/symconfig.csv` and edit the table to turn on specific syms for specific exchanges.

### Frequency of querying feed APIs and limit of depth of market  
The default time and market depth limit for querying feed API's is every 30 seconds and 10 records.
This frequency and limit of depth can be changed in `appconfig/settings/default.q`.
