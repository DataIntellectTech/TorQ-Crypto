// Bespoke DigiFinex Feed config : TorQ Crypto

\d .proc
loadprocesscode:1b


\d .servers
enabled:1b
CONNECTIONS:enlist `segmentedtickerplant                                       // Feedhandler connects to the tickerplant
HOPENTIMEOUT:30000


\d .finex
main_url:"https://openapi.digifinex.com/v3/order_book?symbol="                 // URL used for Coinbase API requests
limit:.crypto.deflimit
freq:.crypto.deffreq
\d .

