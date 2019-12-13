// Bespoke Blue Helix Feed config : Finance Starter Pack

\d .proc
loadprocesscode:1b


\d .servers
enabled:1b
CONNECTIONS:enlist `tickerplant                                                // Feedhandler connects to the tickerplant
HOPENTIMEOUT:30000


\d .bhex
main_url:"https://api.bhex.com/openapi/quote/v1/depth?symbol="                              // URL used for API requests
syms:("BTCUSDT";"ETHUSDT")                                                   // list of currency pairs to request prices for
limit:"10"                                                                     // Bid/Ask quote limit
\d .

