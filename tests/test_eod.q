// tests/test_eod.q
// Unit test: EOD partition writedown.
// Validates .Q.dpft creates the correct HDB directory structure and sym file
// for the trade table (matches appconfig/schemas/tables.q schema).
//
// Run: q tests/test_eod.q
//
// Exit codes: 0 = all tests passed, 1 = one or more failed
//
// Note: .Q.dpft[dir;date;p#col;`tablename] reads the named table from the
// root namespace and writes it as a splayed partition.  The table variable
// must therefore be defined at root scope before calling .Q.dpft.

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

errors:0;
pass:{-1 "PASS: ",x;};
fail:{errors+::1; -1 "FAIL: ",x;};
check:{[name;cond] $[cond; pass name; fail name]};

// Predicate: path exists (directory or flat file)
exists:{not ()~key hsym`$x};

// ---------------------------------------------------------------------------
// Setup: temp HDB directory (unique per q pid)
// ---------------------------------------------------------------------------

hdb_str:"/tmp/torqcrypto_test_hdb_",(string .z.i);
hdb_path:hsym`$hdb_str;
system "mkdir -p ",hdb_str;

// ---------------------------------------------------------------------------
// Synthetic trade data at root scope — schema matches database.q
// .Q.dpft reads the table by name from root namespace
// ---------------------------------------------------------------------------

today:.z.d;
n:5;
trade:([]
  time:n#.z.p;
  sym:n#`BTCUSD;
  venue:n#`binance;
  price:50000f+`float$til n;
  size:0.1f*1+`float$til n;
  side:n#`buy;
  venue_sym:n#`BTCUSDT;
  seq:`long$til n
  );

// ---------------------------------------------------------------------------
// Test 1: .Q.dpft writes a date partition without error
// .Q.dpft[dir; date; p#col; `tablename]
// ---------------------------------------------------------------------------

dpft_ok:1b;
@[.Q.dpft[hdb_path; today; `sym;]; `trade;
  {dpft_ok::0b; -1 "ERROR .Q.dpft: ",x}];

check["test1: .Q.dpft completed without error"; dpft_ok];

// ---------------------------------------------------------------------------
// Test 2: date partition directory created under HDB root
// ---------------------------------------------------------------------------

date_dir:hdb_str,"/",(string today);
check["test2: date partition directory exists"; exists date_dir];

// ---------------------------------------------------------------------------
// Test 3: trade table directory inside date partition
// ---------------------------------------------------------------------------

check["test3: trade directory in partition"; exists date_dir,"/trade"];

// ---------------------------------------------------------------------------
// Test 4: sym file created at HDB root
// ---------------------------------------------------------------------------

check["test4: sym file at HDB root"; (hsym`$hdb_str,"/sym")~key hsym`$hdb_str,"/sym"];

// ---------------------------------------------------------------------------
// Test 5: column files present inside trade directory
// ---------------------------------------------------------------------------

trade_cols:string key hsym`$date_dir,"/trade";
check["test5: time column file written";  any trade_cols like "time*"];
check["test5: price column file written"; any trade_cols like "price*"];
check["test5: sym column file written";   any trade_cols like "sym*"];

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

system "rm -rf ",hdb_str;

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

-1 "";
$[0=errors;
  [-1 "All EOD unit tests PASSED"; exit 0];
  [-1 (string errors)," test(s) FAILED"; exit 1]
  ]
