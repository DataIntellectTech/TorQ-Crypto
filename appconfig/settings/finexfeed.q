// Bespoke DigiFinex Feed config : TorQ Crypto

\d .proc
loadprocesscode:1b


\d .servers
enabled:1b
CONNECTIONS:enlist `tickerplant                                                // Feedhandler connects to the tickerplant
HOPENTIMEOUT:30000


\d .finex
main_url:"https://openapi.digifinex.vip/v3/order_book?symbol="                 // URL used for Coinbase API requests
syms:("btc_usdt";"eth_usdt")                                                   // list of currency pairs to request prices for
\d .

