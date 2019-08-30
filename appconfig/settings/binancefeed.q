// Bespoke Feed config : Finance Starter Pack

\d .proc
loadprocesscode:1b


\d .servers
enabled:1b
CONNECTIONS:enlist `tickerplant                                                // Feedhandler connects to the tickerplant
HOPENTIMEOUT:30000


\d .binance
main_url:"https://api.binance.com/api/v1/depth?symbol="                        // URL used for Coinbase API requests
syms:("BTCUSDT";"ETHUSDT")                                                     // list of currency pairs to request prices for
limit:"10"                                                                     // Bid/Ask quote limit
\d .

