# SPI Interface (plphp_spi.c/h)

## Overview

The SPI (Server Programming Interface) layer provides PHP functions that allow PL/php code to execute SQL queries and interact with the PostgreSQL database. This module exposes a PHP API that wraps PostgreSQL's SPI_* C functions.

Files:
- `plphp_spi.c` (542 lines)
- `plphp_spi.h` (61 lines)

## Public PHP Functions

The following functions are available to PHP code running within PL/php:

| Function | Purpose |
|----------|---------|
| `spi_exec()` | Execute SQL query |
| `spi_fetch_row()` | Fetch next row from result |
| `spi_processed()` | Get number of rows processed |
| `spi_status()` | Get execution status string |
| `spi_rewind()` | Reset result cursor to beginning |
| `pg_raise()` | Raise PostgreSQL notice/warning/error |
| `return_next()` | Return next row in set-returning function |

## Data Structures

### php_SPIresult

**Location**: `plphp_spi.h:38`

Resource type representing the result of an `spi_exec()` call:

```c
typedef struct
{
    SPITupleTable  *SPI_tuptable;   // Result tuples (NULL if not SELECT)
    uint32          SPI_processed;  // Number of rows processed
    uint32          current_row;    // Current position for fetch
    int             status;         // SPI status code
} php_SPIresult;
```

**Lifecycle**:
1. Created by `spi_exec()`
2. Registered as PHP resource
3. Passed to other SPI functions as resource handle
4. Freed automatically when out of scope via `php_SPIresult_destroy()`

### Global Variables

**SRF Support Variables** (`plphp_spi.h:28-34`):

```c
FunctionCallInfo current_fcinfo;         // Current function call info
TupleDesc current_tupledesc;             // SRF result tuple descriptor
AttInMetadata *current_attinmeta;        // Attribute metadata
MemoryContext current_memcxt;            // Per-row memory context
Tuplestorestate *current_tuplestore;     // Tuplestore for SRF results
HashTable *saved_symbol_table;           // Symbol table for RETURNS TABLE
```

**Resource Type**:
```c
int SPIres_rtype;  // Resource type ID for SPI results
```

## PHP Function Implementations

### spi_exec()

**Location**: `plphp_spi.c:97`
**PHP Signature**: `resource spi_exec(string $query [, int $limit])`

Executes an SQL query and returns a resource representing the result.

**Parameters**:
- `$query` - SQL query string
- `$limit` - Optional row limit (default: 0 = no limit)

**Return**: Resource ID (php_SPIresult) or FALSE on error

**Implementation Flow**:
1. Parse PHP arguments (query string, optional limit)
2. Begin internal subtransaction
3. Execute `SPI_exec(query, limit)`
4. On success:
   - Release subtransaction
   - Create `php_SPIresult` structure
   - Register as PHP resource
   - Return resource ID
5. On error:
   - Rollback subtransaction
   - Copy error data
   - Call `zend_error(E_ERROR)` to raise PHP error
   - Restore SPI connection

**Subtransaction Purpose**: Isolates query execution so failures don't abort the entire function.

**Example**:
```php
$result = spi_exec("SELECT * FROM users WHERE active = true");
if ($result === FALSE) {
    // Error occurred
}
```

**Memory**: Result allocated via `malloc()`, freed in `php_SPIresult_destroy()`

### spi_fetch_row()

**Location**: `plphp_spi.c:226`
**PHP Signature**: `array|false spi_fetch_row(resource $result)`

Fetches the next row from a query result.

**Parameters**:
- `$result` - Resource returned by `spi_exec()`

**Return**: Associative array representing row, or FALSE if no more rows

**Implementation Flow**:
1. Parse resource parameter
2. Validate resource type (must be SPI result)
3. Check status (must be `SPI_OK_SELECT`)
4. If rows remain (`current_row < SPI_processed`):
   - Convert tuple to PHP array via `plphp_zval_from_tuple()`
   - Increment `current_row`
   - Return array
5. Otherwise return FALSE

**Example**:
```php
$result = spi_exec("SELECT id, name FROM users");
while ($row = spi_fetch_row($result)) {
    echo "User: " . $row['name'] . "\n";
}
```

**Memory Note**: Each row creates a new PHP array. The comment notes this may leak memory - unclear how PHP should free it.

### spi_processed()

**Location**: `plphp_spi.c:282`
**PHP Signature**: `int spi_processed(resource $result)`

Returns the number of rows processed by a query.

**Parameters**:
- `$result` - Resource returned by `spi_exec()`

**Return**: Integer row count

**Implementation**: Simply returns `SPIres->SPI_processed`

**Example**:
```php
$result = spi_exec("DELETE FROM old_logs WHERE created < '2020-01-01'");
$deleted = spi_processed($result);
pg_raise('NOTICE', "Deleted $deleted rows");
```

### spi_status()

**Location**: `plphp_spi.c:317`
**PHP Signature**: `string spi_status(resource $result)`

Returns a string describing the query execution status.

**Parameters**:
- `$result` - Resource returned by `spi_exec()`

**Return**: Status string (e.g., "SPI_OK_SELECT", "SPI_OK_INSERT_RETURNING")

**Implementation**: Calls `SPI_result_code_string(SPIres->status)`

**Possible Values**:
- `SPI_OK_SELECT`
- `SPI_OK_INSERT`
- `SPI_OK_DELETE`
- `SPI_OK_UPDATE`
- `SPI_OK_INSERT_RETURNING`
- `SPI_OK_DELETE_RETURNING`
- `SPI_OK_UPDATE_RETURNING`
- `SPI_OK_UTILITY`
- Various error codes

**Example**:
```php
$result = spi_exec("INSERT INTO log VALUES (...)");
$status = spi_status($result);
if ($status != "SPI_OK_INSERT") {
    pg_raise('ERROR', "Insert failed: $status");
}
```

### spi_rewind()

**Location**: `plphp_spi.c:358`
**PHP Signature**: `void spi_rewind(resource $result)`

Resets the fetch cursor to the beginning of the result set.

**Parameters**:
- `$result` - Resource returned by `spi_exec()`

**Return**: NULL

**Implementation**: Sets `SPIres->current_row = 0`

**Example**:
```php
$result = spi_exec("SELECT * FROM config");
while ($row = spi_fetch_row($result)) { /* first pass */ }
spi_rewind($result);
while ($row = spi_fetch_row($result)) { /* second pass */ }
```

### pg_raise()

**Location**: `plphp_spi.c:390`
**PHP Signature**: `void pg_raise(string $level, string $message)`

Raises a PostgreSQL notice, warning, or error from PHP code.

**Parameters**:
- `$level` - One of: `"ERROR"`, `"WARNING"`, `"NOTICE"` (case-insensitive)
- `$message` - Message text

**Return**: void (function may not return if level is ERROR)

**Level Translation**:
- `"ERROR"` → `E_ERROR` (aborts function execution)
- `"WARNING"` → `E_WARNING` (continues execution)
- `"NOTICE"` → `E_NOTICE` (continues execution)

**Implementation**: Calls `zend_error()` with translated level

**Example**:
```php
pg_raise('NOTICE', 'Processing batch...');
pg_raise('WARNING', 'Deprecated function called');
pg_raise('ERROR', 'Invalid input data');  // Aborts
```

**Important**: `pg_raise('ERROR')` terminates function execution immediately.

### return_next()

**Location**: `plphp_spi.c:429`
**PHP Signature**: `void return_next([array $row])`

Returns the next row in a set-returning function.

**Parameters**:
- `$row` - Array representing row data (optional for RETURNS TABLE)

**No Return**: Adds row to tuplestore, function continues

**Two Modes**:

#### 1. Explicit Row (RETURNS SETOF type)
```php
CREATE FUNCTION generate_series_php(int, int)
RETURNS SETOF int AS $$
    for ($i = $args[0]; $i <= $args[1]; $i++) {
        return_next([$i]);
    }
$$ LANGUAGE plphp;
```

#### 2. Implicit Row (RETURNS TABLE)
```php
CREATE FUNCTION get_users()
RETURNS TABLE(id int, name text) AS $$
    // Function parameters become row columns
    $id = 1; $name = "Alice";
    return_next();  // Uses $id and $name from symbol table
    $id = 2; $name = "Bob";
    return_next();
$$ LANGUAGE plphp;
```

**Implementation Flow**:
1. Verify function is declared as set-returning (error if not)
2. If no argument, call `get_table_arguments()` to build row from named parameters
3. Otherwise, use provided array
4. Switch to per-query memory context
5. Convert array to tuple via `plphp_srf_htup_from_zval()`
6. Create tuplestore on first call
7. Add tuple to tuplestore via `tuplestore_puttuple()`
8. Free tuple
9. Return to original context

**Memory**: Uses `current_memcxt` (reset per row) and per-query context (persists)

**Errors**:
- Called from non-SRF function → ERROR
- Wrong number of columns → ERROR

## Helper Functions

### php_SPIresult_destroy()

**Location**: `plphp_spi.c:495`

Resource destructor called when SPI result resource is freed.

**Process**:
1. If result has tuple table, call `SPI_freetuptable()`
2. Free the `php_SPIresult` structure

**Automatically Invoked**:
- Resource goes out of scope
- Resource overwritten
- Script ends

### get_table_arguments()

**Location**: `plphp_spi.c:507`

Builds return row for `return_next()` in RETURNS TABLE functions.

**Process**:
1. Create new PHP array
2. For each attribute in result tuple descriptor:
   - Get attribute name
   - Look up variable with that name in `saved_symbol_table`
   - Add to array (or NULL if not found)
3. Return array

**Example**:
```sql
CREATE FUNCTION test()
RETURNS TABLE(a int, b text) AS $$
    $a = 1; $b = "hello";
    return_next();  // Implicitly uses $a and $b
$$ LANGUAGE plphp;
```

`get_table_arguments()` builds: `[1, "hello"]`

## Subtransaction Handling

### Why Subtransactions?

SPI calls can fail (syntax error, constraint violation, etc.). Without subtransactions, a failed query would abort the entire outer transaction. Subtransactions provide isolation:

```c
BeginInternalSubTransaction(NULL);
MemoryContextSwitchTo(oldcontext);

PG_TRY();
{
    status = SPI_exec(query, limit);
    ReleaseCurrentSubTransaction();
    // Success path
}
PG_CATCH();
{
    // Save error info
    edata = CopyErrorData();
    // Rollback failed query
    RollbackAndReleaseCurrentSubTransaction();
    // Restore SPI connection
    SPI_restore_connection();
    // Raise error to PHP
    zend_error(E_ERROR, "%s", edata->message);
}
PG_END_TRY();
```

**Benefits**:
- Failed queries don't abort function
- Can catch and handle SQL errors in PHP code
- Matches behavior of other PLs (PL/Perl, PL/Python)

**Cost**:
- Overhead of subtransaction management
- Each `spi_exec()` call creates/destroys subtransaction

## SRF Execution Model

### Setup Phase (plphp_srf_handler)

1. Set global SRF variables:
   ```c
   current_fcinfo = fcinfo;
   current_tupledesc = CreateTupleDescCopy(tupdesc);
   current_attinmeta = TupleDescGetAttInMetadata(tupdesc);
   current_memcxt = AllocSetContextCreate(...);
   current_tuplestore = NULL;  // Created on first return_next()
   ```

2. Invoke PHP function

### Execution Phase (PHP code)

PHP function repeatedly calls `return_next()`:
```php
return_next([row1_data]);
return_next([row2_data]);
// ... etc
```

Each call:
- Converts array to tuple
- Adds to tuplestore
- Resets per-row memory context

### Cleanup Phase (plphp_srf_handler)

1. Set return mode: `rsi->returnMode = SFRM_Materialize`
2. Return tuplestore: `rsi->setResult = current_tuplestore`
3. Return tuple descriptor: `rsi->setDesc = current_tupledesc`
4. Delete per-row context
5. Clear global SRF variables

## Error Handling

### Query Execution Errors

Handled via subtransaction PG_CATCH block:
```c
PG_CATCH();
{
    ErrorData *edata = CopyErrorData();
    FlushErrorState();
    RollbackAndReleaseCurrentSubTransaction();
    SPI_restore_connection();
    zend_error(E_ERROR, "%s", strdup(edata->message));
}
```

### PHP-Level Errors

Raised via `zend_error()`:
```c
zend_error(E_WARNING, "Cannot parse parameters");
```

These trigger `plphp_error_cb()` in plphp.c, which translates to PostgreSQL errors.

### Resource Validation

All functions validate resource type:
```c
ZEND_FETCH_RESOURCE(SPIres, php_SPIresult *, z_spi, -1,
                    "SPI result", SPIres_rtype);
```

**Raises**: `E_WARNING` if resource type mismatch

## Usage Patterns

### Simple Query

```php
$result = spi_exec("SELECT COUNT(*) FROM users");
$row = spi_fetch_row($result);
$count = $row['count'];
return $count;
```

### Parameterized Query (Manual Escaping)

```php
$name = pg_escape_string($args[0]);  // Not actually available!
$result = spi_exec("SELECT * FROM users WHERE name = '$name'");
// NOTE: No built-in parameterized queries - SQL injection risk!
```

### INSERT with RETURNING

```php
$result = spi_exec(
    "INSERT INTO log (message) VALUES ('test') RETURNING id"
);
$row = spi_fetch_row($result);
pg_raise('NOTICE', "Inserted row with ID: " . $row['id']);
```

### Iterating Results

```php
$result = spi_exec("SELECT id, name FROM users");
while ($row = spi_fetch_row($result)) {
    pg_raise('NOTICE', "User: {$row['name']} (ID: {$row['id']})");
}
```

### Error Handling

```php
$result = spi_exec("UPDATE users SET active = true");
if ($result === FALSE) {
    // Error already raised by SPI, function will abort
}
$updated = spi_processed($result);
return $updated;
```

### Set-Returning Function

```php
// CREATE FUNCTION get_range(int, int) RETURNS SETOF int
for ($i = $args[0]; $i <= $args[1]; $i++) {
    return_next([$i]);
}
```

### RETURNS TABLE

```php
// CREATE FUNCTION users_list() RETURNS TABLE(id int, name text)
$result = spi_exec("SELECT id, name FROM users");
while ($row = spi_fetch_row($result)) {
    $id = $row['id'];
    $name = $row['name'];
    return_next();  // Implicitly uses $id and $name
}
```

## Known Limitations

### 1. No Prepared Statements

PL/php doesn't support prepared statements or parameterized queries.

**Workaround**: Manual escaping (but no `pg_escape_string()` provided!)

**Risk**: SQL injection vulnerabilities

### 2. No Query Cancellation

Long-running queries can't be interrupted from PHP code.

**Workaround**: Set `statement_timeout` in SQL

### 3. Memory Leaks (Possible)

Comment at `plphp_spi.c:224` notes potential memory leak:
```c
/*
 * XXX Apparently this is leaking memory. How do we tell PHP to free
 * the tuple once the user is done with it?
 */
```

Each `spi_fetch_row()` creates a new PHP array that may not be properly freed.

### 4. No Cursor Support

Cannot use PostgreSQL cursors for large result sets.

**Impact**: Large result sets consume memory

### 5. Subtransaction Overhead

Every `spi_exec()` creates a subtransaction.

**Impact**: Performance cost for frequent queries

## Security Considerations

### SQL Injection

No parameterized query support means manual string building:

**Dangerous**:
```php
$name = $args[0];
$result = spi_exec("SELECT * FROM users WHERE name = '$name'");
// Vulnerable to: '; DROP TABLE users; --
```

**Better** (but still risky):
```php
// Manually quote and validate
if (!preg_match('/^[a-zA-Z0-9_]+$/', $args[0])) {
    pg_raise('ERROR', 'Invalid input');
}
```

**Best**: Use trusted data only, never user input directly in SQL.

### Privilege Escalation

SPI executes with function owner's privileges (if SECURITY DEFINER).

**Risk**: Untrusted code could access restricted data

**Mitigation**: Validate inputs, use trusted/untrusted language distinction

## Performance Considerations

### Subtransaction Cost

Each `spi_exec()` call:
1. Begins subtransaction
2. Executes query
3. Commits or rolls back subtransaction

**Impact**: Noticeable overhead for many small queries

**Alternative**: Batch operations when possible

### Result Set Size

All results materialized in memory:
```c
SPIres->SPI_tuptable = SPI_tuptable;  // Entire result set
```

**Impact**: Large result sets consume significant memory

**Mitigation**: Use LIMIT, or process incrementally if possible

### Row-by-Row Fetching

`spi_fetch_row()` doesn't actually fetch from cursor - all rows already loaded.

**Current**: All rows in memory, iteration just indexes into array

**Could Be**: Cursor-based fetching to reduce memory (not implemented)

## Testing

### Basic Query Tests

```sql
CREATE FUNCTION test_spi_exec() RETURNS int AS $$
    $r = spi_exec("SELECT 42 AS answer");
    $row = spi_fetch_row($r);
    return (int)$row['answer'];
$$ LANGUAGE plphp;

SELECT test_spi_exec();  -- Should return 42
```

### Error Handling Tests

```sql
CREATE FUNCTION test_spi_error() RETURNS void AS $$
    $r = spi_exec("SELECT * FROM nonexistent_table");
    // Should not reach here
$$ LANGUAGE plphp;

SELECT test_spi_error();  -- Should error
```

### SRF Tests

```sql
CREATE FUNCTION test_return_next() RETURNS SETOF int AS $$
    for ($i = 1; $i <= 5; $i++) {
        return_next([$i]);
    }
$$ LANGUAGE plphp;

SELECT * FROM test_return_next();  -- Returns 1,2,3,4,5
```

### RETURNS TABLE Tests

```sql
CREATE FUNCTION test_table() RETURNS TABLE(x int, y text) AS $$
    $x = 1; $y = "one";
    return_next();
    $x = 2; $y = "two";
    return_next();
$$ LANGUAGE plphp;

SELECT * FROM test_table();
```

## Debugging

### Enable Memory Reporting

```c
#define DEBUG_PLPHP_MEMORY
```

Adds `REPORT_PHP_MEMUSAGE()` calls throughout SPI functions.

### Trace SPI Calls

Add logging:
```php
pg_raise('NOTICE', 'Executing query: ' . $query);
$result = spi_exec($query);
pg_raise('NOTICE', 'Status: ' . spi_status($result));
pg_raise('NOTICE', 'Rows: ' . spi_processed($result));
```

### Inspect Resources

```php
$r = spi_exec("SELECT 1");
pg_raise('NOTICE', 'Resource type: ' . gettype($r));  // "resource"
```

## Extension Opportunities

### Add Prepared Statement Support

Would require:
1. New `spi_prepare(query, types)` function
2. New `spi_execute(plan, params)` function
3. Plan caching mechanism
4. Parameter binding

### Add Cursor Support

Would require:
1. `spi_cursor_open(query)` → cursor name
2. `spi_cursor_fetch(name, count)` → rows
3. `spi_cursor_close(name)`

### Add Transaction Control

Currently not available (would break SPI model):
- `spi_begin()` - Start subtransaction
- `spi_commit()` - Commit subtransaction
- `spi_rollback()` - Rollback subtransaction

**Challenge**: Conflicts with SPI's automatic subtransaction management
