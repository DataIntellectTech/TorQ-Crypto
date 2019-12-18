// Bespoke Huobi Feed config : Torq Crypto

\d .proc
loadprocesscode:1b


\d .servers
enabled:1b
CONNECTIONS:enlist `tickerplant                                                // Feedhandler connects to the tickerplant
HOPENTIMEOUT:30000


\d .huobi
main_url:"https://api.huobi.pro/market/depth?type=step1&symbol="               // URL used for Huobi API requests
syms:("btcusdt";"ethusdt")                                                     // list of currency pairs to request prices for

\d .

