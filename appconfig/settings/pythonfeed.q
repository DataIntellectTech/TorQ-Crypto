// appconfig/settings/pythonfeed.q
// Process-specific config overrides for pythonfeed.
// All variables use the guard pattern in pythonfeed.q — override here as needed.

\d .servers
CONNECTIONS:enlist `tickerplant

\d .