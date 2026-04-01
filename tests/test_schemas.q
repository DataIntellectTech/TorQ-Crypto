// tests/test_schemas.q
// Validates canonical table schemas defined in appconfig/schemas/tables.q
//
// Run from repo root:
//   q tests/test_schemas.q
//
// Exit codes:  0 = all tests passed
//              1 = one or more tests failed

\l appconfig/schemas/tables.q

errors:0;
pass:{-1 "PASS: ",x;}
fail:{errors+::1; -1 "FAIL: ",x;}

// ---------------------------------------------------------------------------
// trade
// ---------------------------------------------------------------------------
$[`trade in key `.; pass"trade exists"; fail"trade exists — table not defined"];
$[`time`sym`venue`price`size`side`venue_sym`seq ~ cols trade;
  pass"trade cols";
  fail"trade cols — expected: time sym venue price size side venue_sym seq"];
$[12 11 11 9 9 11 11 7h ~ type each value flip trade;
  pass"trade types";
  fail"trade types — expected: timestamp symbol symbol float float symbol symbol long"];

// ---------------------------------------------------------------------------
// quote
// ---------------------------------------------------------------------------
$[`quote in key `.; pass"quote exists"; fail"quote exists — table not defined"];
$[`time`sym`venue`bid`ask`bsize`asize`venue_sym ~ cols quote;
  pass"quote cols";
  fail"quote cols — expected: time sym venue bid ask bsize asize venue_sym"];
$[12 11 11 9 9 9 9 11h ~ type each value flip quote;
  pass"quote types";
  fail"quote types — expected: timestamp symbol symbol float float float float symbol"];

// ---------------------------------------------------------------------------
// lastprice (keyed: sym+venue)
// ---------------------------------------------------------------------------
$[`lastprice in key `.; pass"lastprice exists"; fail"lastprice exists — table not defined"];
$[99h = type lastprice;
  pass"lastprice is keyed table";
  fail"lastprice is keyed table — got type ",(string type lastprice)];
$[`sym`venue ~ cols key lastprice;
  pass"lastprice key cols";
  fail"lastprice key cols — expected: sym venue"];
$[11 11h ~ type each value flip key lastprice;
  pass"lastprice key types";
  fail"lastprice key types — expected: symbol symbol"];
$[`time`price`bid`ask`mid ~ cols value lastprice;
  pass"lastprice value cols";
  fail"lastprice value cols — expected: time price bid ask mid"];
$[12 9 9 9 9h ~ type each value flip value lastprice;
  pass"lastprice value types";
  fail"lastprice value types — expected: timestamp float float float float"];

// ---------------------------------------------------------------------------
// consolidatedmid
// ---------------------------------------------------------------------------
$[`consolidatedmid in key `.; pass"consolidatedmid exists"; fail"consolidatedmid exists — table not defined"];
$[`time`sym`mid`n_venues`spread_dispersion`outlier_flag ~ cols consolidatedmid;
  pass"consolidatedmid cols";
  fail"consolidatedmid cols — expected: time sym mid n_venues spread_dispersion outlier_flag"];
$[12 11 9 6 9 1h ~ type each value flip consolidatedmid;
  pass"consolidatedmid types";
  fail"consolidatedmid types — expected: timestamp symbol float int float boolean"];

// ---------------------------------------------------------------------------
// symbology (keyed: venue+venue_sym)
// ---------------------------------------------------------------------------
$[`symbology in key `.; pass"symbology exists"; fail"symbology exists — table not defined"];
$[99h = type symbology;
  pass"symbology is keyed table";
  fail"symbology is keyed table — got type ",(string type symbology)];
$[`venue`venue_sym ~ cols key symbology;
  pass"symbology key cols";
  fail"symbology key cols — expected: venue venue_sym"];
$[11 11h ~ type each value flip key symbology;
  pass"symbology key types";
  fail"symbology key types — expected: symbol symbol"];
$[`canonical_sym`base`quote`instrument_type`tick_size`price_precision ~ cols value symbology;
  pass"symbology value cols";
  fail"symbology value cols — expected: canonical_sym base quote instrument_type tick_size price_precision"];
$[11 11 11 11 9 6h ~ type each value flip value symbology;
  pass"symbology value types";
  fail"symbology value types — expected: symbol symbol symbol symbol float int"];

// ---------------------------------------------------------------------------
// result
// ---------------------------------------------------------------------------
-1 "";
if[0=errors;
  -1 "All schema tests PASSED";
  exit 0
  ];
-1 (string errors)," schema test(s) FAILED";
exit 1
