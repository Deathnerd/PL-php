# Testing Framework

## Overview

PL/php uses PostgreSQL's regression testing framework (`pg_regress`) to validate functionality. Tests are organized as SQL scripts with expected output files.

## Test Organization

### Test Files

**Location**: `sql/` directory

**Test Scripts** (in execution order):
1. `base.sql` - Base functionality (scalars, arrays, basic functions)
2. `shared.sql` - Shared memory and global state
3. `trigger.sql` - Trigger functions
4. `spi.sql` - SPI functions (`spi_exec`, `spi_fetch_row`, etc.)
5. `raise.sql` - Error handling (`pg_raise`)
6. `cargs.sql` - Function arguments (named params, IN/OUT/INOUT)
7. `pseudo.sql` - Pseudotypes (RECORD, ANYELEMENT, etc.)
8. `srf.sql` - Set-returning functions
9. `validator.sql` - Function validation

**Additional Test Files** (not in default suite):
- `out.sql` - OUT parameter tests
- `prepare.sql` - Prepared statement tests
- `varnames.sql` - Variable name validation

### Expected Output Files

**Location**: `expected/` directory

**Files**:
- `base.out` - Expected output for base.sql
- `base_2.out` - Alternate output (different PostgreSQL versions)
- `shared.out`, `shared_2.out` - Shared memory tests
- `trigger.out`, `trigger_2.out` - Trigger tests
- `spi.out` - SPI tests
- `raise.out` - Error handling tests
- `cargs.out` - Argument tests
- `pseudo.out` - Pseudotype tests
- `srf.out` - SRF tests
- `validator.out` - Validator tests
- Plus additional `.out` files

**Versioned Outputs**: Some tests have multiple `.out` files (e.g., `base.out` and `base_2.out`) to handle output differences across PostgreSQL versions.

## Running Tests

### Run All Tests

```bash
make installcheck
```

**Prerequisites**:
- PL/php must be installed (`make install`)
- PostgreSQL server must be running
- User must have permission to create databases

**Output**:
```
============== creating database "pl_regression" ==============
CREATE DATABASE
============== installing plphp                   ==============
CREATE LANGUAGE
============== running regression test queries    ==============
test base                     ... ok
test shared                   ... ok
test trigger                  ... ok
test spi                      ... ok
test raise                    ... ok
test cargs                    ... ok
test pseudo                   ... ok
test srf                      ... ok
test validator                ... ok

======================
 All 9 tests passed.
======================
```

### Run Individual Tests

```bash
make installcheck REGRESS="base"
```

Replace `"base"` with any test name from the REGRESS list.

**Multiple Tests**:
```bash
make installcheck REGRESS="base trigger spi"
```

### Custom Test Database

```bash
make installcheck PL_TESTDB=my_test_db
```

Default database name: `pl_regression`

## Test Configuration

**Configured in** `Makefile.in:12-13`:
```makefile
REGRESS_OPTS = --dbname=$(PL_TESTDB) --load-language=plphp
REGRESS = base shared trigger spi raise cargs pseudo srf validator
```

**Options**:
- `--dbname=$(PL_TESTDB)` - Test database name
- `--load-language=plphp` - Install plphp language before tests

## Test Framework Details

### Test Execution Flow

1. **Database Creation**: `pg_regress` creates test database
2. **Language Installation**: Loads PL/php language
3. **For Each Test**:
   - Execute SQL script from `sql/<test>.sql`
   - Capture output
   - Compare against `expected/<test>.out`
   - If mismatch, try alternate output files (`<test>_2.out`, etc.)
4. **Report Results**: Summary of passed/failed tests

### Output Comparison

**Exact Match Required**: Output must match expected file exactly (whitespace, line breaks, etc.)

**Alternate Outputs**: If `<test>.out` doesn't match, tries:
- `<test>_1.out`
- `<test>_2.out`
- etc.

**Failure**: If no output file matches, test fails and diff is saved to `regression.diffs`

### Results Location

**After Test Run**:
- `results/` - Actual output files
- `regression.diffs` - Diff for failed tests
- `regression.out` - Full test log

## Test Categories

### 1. Base Functionality Tests (base.sql)

**Tests**:
- Scalar returns (int, text, bool, etc.)
- Array returns
- Multi-dimensional arrays
- NULL handling
- Type coercion
- Basic function calls

**Example Test**:
```sql
CREATE FUNCTION test_an_int() RETURNS integer
LANGUAGE plphp AS $$
    return 1;
$$;
SELECT test_an_int();
```

**Expected** (`base.out`):
```
 test_an_int
-------------
           1
(1 row)
```

### 2. Shared Memory Tests (shared.sql)

**Tests**:
- Global PHP variables
- State persistence across calls
- Function-local state

**Example**:
```sql
CREATE FUNCTION counter() RETURNS integer AS $$
    global $count;
    if (!isset($count)) $count = 0;
    return ++$count;
$$ LANGUAGE plphp;

SELECT counter(), counter(), counter();
```

### 3. Trigger Tests (trigger.sql)

**Tests**:
- BEFORE triggers
- AFTER triggers
- INSERT/UPDATE/DELETE triggers
- Row-level vs statement-level
- Trigger data access (`$_TD`)
- Row modification (MODIFY return)

**Example**:
```sql
CREATE TABLE test_table (id int, value text);

CREATE FUNCTION test_trigger() RETURNS trigger AS $$
    if ($_TD['event'] == 'INSERT') {
        pg_raise('NOTICE', 'Inserting: ' . $_TD['new']['value']);
    }
    return NULL;
$$ LANGUAGE plphp;

CREATE TRIGGER test_trig
  AFTER INSERT ON test_table
  FOR EACH ROW EXECUTE PROCEDURE test_trigger();
```

### 4. SPI Tests (spi.sql)

**Tests**:
- `spi_exec()` - Query execution
- `spi_fetch_row()` - Row iteration
- `spi_processed()` - Row count
- `spi_status()` - Status codes
- `spi_rewind()` - Cursor reset

**Example**:
```sql
CREATE FUNCTION spi_test() RETURNS int AS $$
    $r = spi_exec("SELECT 42 AS answer");
    $row = spi_fetch_row($r);
    return (int)$row['answer'];
$$ LANGUAGE plphp;

SELECT spi_test();
```

### 5. Error Handling Tests (raise.sql)

**Tests**:
- `pg_raise()` with different levels
- ERROR level (aborts function)
- WARNING level (continues)
- NOTICE level (informational)

**Example**:
```sql
CREATE FUNCTION test_raise() RETURNS void AS $$
    pg_raise('NOTICE', 'This is a notice');
    pg_raise('WARNING', 'This is a warning');
$$ LANGUAGE plphp;

SELECT test_raise();
```

### 6. Argument Tests (cargs.sql)

**Tests**:
- Named parameters
- IN parameters
- OUT parameters
- INOUT parameters
- Parameter type conversion

**Example**:
```sql
CREATE FUNCTION test_args(IN x int, IN y int, OUT sum int)
AS $$
    $sum = $x + $y;
$$ LANGUAGE plphp;

SELECT test_args(5, 7);
```

### 7. Pseudotype Tests (pseudo.sql)

**Tests**:
- ANYELEMENT
- ANYARRAY
- RECORD types
- Polymorphic functions

**Example**:
```sql
CREATE FUNCTION first_element(ANYARRAY) RETURNS ANYELEMENT AS $$
    return $args[0][0];
$$ LANGUAGE plphp;

SELECT first_element(ARRAY[1,2,3]);
```

### 8. Set-Returning Function Tests (srf.sql)

**Tests**:
- RETURNS SETOF
- RETURNS TABLE
- `return_next()` calls
- Multi-row returns
- Empty result sets

**Example**:
```sql
CREATE FUNCTION generate_series_php(int, int)
RETURNS SETOF int AS $$
    for ($i = $args[0]; $i <= $args[1]; $i++) {
        return_next([$i]);
    }
$$ LANGUAGE plphp;

SELECT * FROM generate_series_php(1, 5);
```

### 9. Validator Tests (validator.sql)

**Tests**:
- Syntax validation at CREATE FUNCTION time
- Invalid syntax detection
- Error messages

**Example**:
```sql
-- Should succeed
CREATE FUNCTION valid_func() RETURNS int AS $$
    return 42;
$$ LANGUAGE plphp;

-- Should fail
CREATE FUNCTION invalid_func() RETURNS int AS $$
    this is not valid PHP;
$$ LANGUAGE plphp;
```

## Writing New Tests

### Test File Structure

**Pattern**:
```sql
--
-- Test Description
--

-- Create functions
CREATE FUNCTION test_func() ...;

-- Execute tests
SELECT test_func();

-- Clean up (optional)
DROP FUNCTION test_func();
```

### Expected Output

**Generate Initial Output**:
```bash
# Run test and save output
psql -d testdb -f sql/newtest.sql > expected/newtest.out

# Review and edit if needed
vim expected/newtest.out
```

**Include in Test Suite**:

Edit `Makefile.in`:
```makefile
REGRESS = base shared trigger spi raise cargs pseudo srf validator newtest
```

### Test Best Practices

1. **Isolation**: Each test should be self-contained
2. **Cleanup**: Drop created objects (or use unique names)
3. **Determinism**: Avoid non-deterministic outputs (random, timestamps)
4. **Comments**: Explain what each test validates
5. **Edge Cases**: Test boundary conditions, NULL, empty sets

## Debugging Failed Tests

### View Differences

```bash
cat regression.diffs
```

Shows diff between expected and actual output.

### View Actual Output

```bash
cat results/base.out
```

### Run Individual Test with Verbose Output

```bash
psql -d pl_regression -f sql/base.sql
```

### Common Failure Causes

1. **Platform Differences**: Floating point format, whitespace
2. **Version Differences**: PostgreSQL version-specific output
3. **Locale Differences**: Error message translations
4. **Installation Issues**: Language not properly installed
5. **Code Changes**: Intentional behavior change (update expected output)

## Regression Test Workflow

### After Code Changes

```bash
# Rebuild and reinstall
make clean
make
sudo make install

# Run tests
make installcheck

# If tests fail, investigate
cat regression.diffs

# Update expected output if change is intentional
cp results/base.out expected/base.out
```

### Continuous Integration

**Automated Testing**:
```bash
#!/bin/bash
set -e

# Build
./configure
make

# Install
sudo make install

# Test
make installcheck

# Report results
if [ $? -eq 0 ]; then
    echo "All tests passed"
    exit 0
else
    echo "Tests failed"
    cat regression.diffs
    exit 1
fi
```

## Platform-Specific Testing

### Different PostgreSQL Versions

Tests may produce different output on different PostgreSQL versions.

**Strategy**: Maintain alternate expected files:
- `base.out` - PostgreSQL 8.1-9.4
- `base_2.out` - PostgreSQL 9.5+

**Detection**: `pg_regress` tries all available output files.

### Different PHP Versions

PHP output may vary (error messages, formatting).

**Current**: Tests assume PHP 5.x
**Future**: May need PHP 7.x-specific expected outputs

## Performance Testing

**Not Included**: No performance/benchmark tests in regression suite.

**Manual Benchmarking**:
```sql
CREATE FUNCTION bench_test(int) RETURNS void AS $$
    for ($i = 0; $i < $args[0]; $i++) {
        $r = spi_exec("SELECT 1");
    }
$$ LANGUAGE plphp;

\timing
SELECT bench_test(1000);
```

## Test Coverage

### Current Coverage

| Area | Coverage | Gaps |
|------|----------|------|
| Basic types | Good | Complex types (JSON, arrays of composites) |
| Triggers | Good | INSTEAD OF triggers |
| SPI | Good | Cursor operations, prepared statements |
| Arguments | Good | VARIADIC arguments |
| SRF | Good | Large result sets |
| Errors | Basic | Subtransaction handling |
| Validators | Basic | All error conditions |

### Adding Coverage

**Identify Gaps**:
```bash
# Check which code paths are untested
gcov plphp.c  # Requires --coverage build flag
```

**Add Tests**:
1. Create test case in appropriate `sql/*.sql`
2. Run and capture output to `expected/*.out`
3. Add to `REGRESS` list in `Makefile.in`

## Test Utilities

### Helper Functions

**Not Provided**: No standard test helper functions.

**Could Add**:
```sql
-- Assert function
CREATE FUNCTION assert(bool, text) RETURNS void AS $$
    if (!$args[0]) {
        pg_raise('ERROR', 'Assertion failed: ' . $args[1]);
    }
$$ LANGUAGE plphp;

-- Use in tests
SELECT assert(test_func() = 42, 'test_func should return 42');
```

## Known Test Issues

### 1. Timing-Dependent Tests

Some tests may have non-deterministic output (timestamps, random values).

**Solution**: Avoid or mock such values.

### 2. Locale-Specific Output

Error messages may differ based on locale.

**Solution**: Run tests with `LC_MESSAGES=C`

### 3. Floating Point Precision

Float/double output may vary slightly.

**Solution**: Round or format consistently:
```php
return sprintf("%.2f", $value);
```

## Test Environment Setup

### Minimal Setup

```bash
# Install PL/php
sudo make install

# Start PostgreSQL
pg_ctl start

# Run tests
make installcheck
```

### Isolated Test Environment

```bash
# Create temporary PostgreSQL cluster
initdb -D /tmp/test_pg

# Start server
pg_ctl -D /tmp/test_pg start

# Run tests
make installcheck

# Stop server
pg_ctl -D /tmp/test_pg stop

# Clean up
rm -rf /tmp/test_pg
```

## Future Improvements

### Potential Additions

1. **Performance Tests**: Benchmark suite for regression detection
2. **Stress Tests**: Large datasets, memory limits
3. **Concurrency Tests**: Multiple concurrent PL/php calls
4. **Security Tests**: SQL injection, privilege escalation
5. **Memory Leak Detection**: Valgrind integration
6. **Code Coverage**: Automated coverage reporting

### Test Automation

**Continuous Integration**:
- Run tests on every commit
- Test multiple PostgreSQL versions
- Test multiple PHP versions
- Report coverage metrics

**Example GitHub Actions**:
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        pg: [9.5, 9.6, 10, 11, 12]
    steps:
      - uses: actions/checkout@v2
      - name: Install PostgreSQL ${{ matrix.pg }}
        run: sudo apt-get install postgresql-${{ matrix.pg }}
      - name: Build and test
        run: |
          ./configure
          make
          sudo make install
          make installcheck
```
