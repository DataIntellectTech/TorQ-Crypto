// Bespoke Feed config : Finance Starter Pack

\d .proc
loadprocesscode:1b


\d .servers
enabled:1b
CONNECTIONS:enlist `tickerplant                                                // Feedhandler connects to the tickerplant
HOPENTIMEOUT:30000


\d .okex
main_url:"https://www.okex.com/api/spot/v3/instruments/"                       // URL used for Coinbase API requests
syms:("BTC-USDT";"ETH-USDT")                                                   // list of currency pairs to request prices for
limit:"10"                                                                     // Bid/Ask quote limit
\d .