# Testing

TorQ-Crypto has two test suites: q unit tests for the kdb+ processes, and Python unit tests for the feed handler. All tests are self-contained and do not require a running TorQ stack.

Run everything from the **repo root**.

---

## q Tests

The q tests mock all TorQ framework dependencies inline, so no live processes are needed.

| File | What it tests |
|---|---|
| `tests/test_cryptoagg.q` | `cryptoagg` process — order book aggregation, consolidation, API functions |
| `tests/test_cryptolib.q` | `cryptolib.q` — OHLC, `getconsolidated`, `setdefaults`, parameter validation |
| `tests/test_pythonfeed.q` | `pythonfeed` process — `upd` dispatch, `maxtime`, symmap upsert |

**Run a single file:**

```bash
q tests/test_cryptoagg.q   -noprocess
q tests/test_cryptolib.q   -noprocess
q tests/test_pythonfeed.q  -noprocess
```

**Run all q tests in one go:**

```bash
for f in tests/test_*.q; do
  echo "=== $f ==="; q "$f" -noprocess; echo
done
```

Each test prints `[PASS]`/`[FAIL]` per assertion and exits with code `0` on success or `1` if any assertion fails.

---

## Python Tests

The Python tests use `unittest.mock` to avoid real HTTP or WebSocket calls.

| File | What it tests |
|---|---|
| `tests/test_discovery.py` | REST-based instrument discovery per exchange |
| `tests/test_symmap.py` | Symbol mapping CSV load, lookup, and normalisation |

**Prerequisites** — install test dependencies into your virtual environment:

```bash
source .venv/bin/activate      # or deploy/.venv/bin/activate after deploy.sh
pip install pytest
```

**Run a single file:**

```bash
python -m pytest tests/test_discovery.py -v
python -m pytest tests/test_symmap.py    -v
```

**Run all Python tests:**

```bash
python -m pytest tests/ -v
```

---

## Running Everything

```bash
# q tests
for f in tests/test_*.q; do
  echo "=== $f ==="
  q "$f" -noprocess || exit 1
done

# Python tests
python -m pytest tests/ -v
```
