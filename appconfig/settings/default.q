system"c 23 2000"

\d .crypto

//Defaults for frequency of querying API
deffreq : 0D00:00:30.000
bhexfreq : .crypto.deffreq
finexfreq : .crypto.deffreq
huobifreq : .crypto.deffreq
okexfreq : .crypto.deffreq
zbfreq : .crypto.deffreq

//Defaults for limit of depth of market returned
deflimit: "10"
bhexlimit : .crypto.deflimit
finexlimit : .crypto.deflimit
huobilimit : .crypto.deflimit
okexlimit : .crypto.deflimit
zblimit : .crypto.deflimit

\d .
