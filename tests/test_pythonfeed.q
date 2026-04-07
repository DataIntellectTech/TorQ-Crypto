// tests/test_pythonfeed.q
// Integration test for pythonfeed.q
//
// REQUIRES: pythonfeed1 running on port {KDBBASEPORT}+20 (default 9020).
//
// Start the process first:
//   source setenv.sh
//   q torq.q -load code/processes/pythonfeed.q -proctype pythonfeed -procname pythonfeed1 \
//     -procport 9020 -debug
//
// Then run this test in a separate terminal:
//   source setenv.sh
//   q tests/test_pythonfeed.q
//
// Exit codes: 0 = PASS, 1 = FAIL

errors:0;
pass:{-1 "PASS: ",x;};
fail:{errors+::1; -1 "FAIL: ",x;};

port:@[{`int$x};`KDBBASEPORT;{9000}]+20;

// ---------------------------------------------------------------------------
// Connect to pythonfeed1
// ---------------------------------------------------------------------------
h:@[hopen;`$":localhost:",string port;{`FAILED}];
$[h~`FAILED;
  [fail"connect to pythonfeed1 on port ",string port;
   -1 "Is pythonfeed1 running? See header comment for startup instructions.";
   exit 1];
  pass"connect to pythonfeed1"];

// ---------------------------------------------------------------------------
// Send a synthetic trade row via .u.upd
// ---------------------------------------------------------------------------
ts:.z.p;
row:(enlist ts;enlist `BTCUSD;enlist `binance;enlist 50000f;enlist 1f;enlist `buy;enlist `BTCUSDT;enlist 0j);
@[h(`.u.upd;`trade;row);`;()];
pass"send synthetic trade row";

// Allow pythonfeed time to process the message
.z.N; // flush

// ---------------------------------------------------------------------------
// Query .pythonfeed.maxtime
// ---------------------------------------------------------------------------
mt:@[h;(`.pythonfeed.maxtime;`BTCUSD;`binance);{0Np}];
$[mt~0Np;
  fail"maxtime is null — row may not have been processed";
  pass"maxtime is not null: ",(string mt)];

$[mt>=ts;
  pass"maxtime >= sent timestamp";
  fail"maxtime ",string[mt]," is older than sent timestamp ",string ts];

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------
hclose h;

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------
-1 "";
$[0=errors;
  [-1 "All pythonfeed integration tests PASSED"; exit 0];
  [-1 (string errors)," test(s) FAILED"; exit 1]
  ]