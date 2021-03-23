// Bespoke ZB Feed config : TorQ Crypto

\d .proc
loadprocesscode:1b


\d .servers
enabled:1b
CONNECTIONS:enlist `segmentedtickerplant                                       // Feedhandler connects to the tickerplant
HOPENTIMEOUT:30000


\d .zb
main_url:"http://api.zb.cn/data/v1/depth?market="                              // URL used for Coinbase API requests
limit:.crypto.deflimit
freq:.crypto.deffreq

\d .

