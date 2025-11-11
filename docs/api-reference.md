# PL/php API Reference

## Overview

This document describes the PHP API available within PL/php functions. These functions allow PHP code to interact with PostgreSQL through the Server Programming Interface (SPI).

## Available Functions

PL/php provides the following built-in PHP functions:

| Function | Category | Purpose |
|----------|----------|---------|
| `spi_exec()` | Query Execution | Execute SQL query |
| `spi_fetch_row()` | Result Handling | Fetch next result row |
| `spi_processed()` | Result Metadata | Get processed row count |
| `spi_status()` | Result Metadata | Get execution status |
| `spi_rewind()` | Result Handling | Reset result cursor |
| `pg_raise()` | Error Handling | Raise PostgreSQL message |
| `return_next()` | Set Functions | Return next row in SRF |

## Query Execution

### spi_exec()

Execute an SQL query and return a result resource.

**Signature**:
```php
resource spi_exec(string $query [, int $limit])
```

**Parameters**:
- `$query` (string, required) - SQL query to execute
- `$limit` (int, optional) - Maximum number of rows to return (0 = unlimited, default: 0)

**Returns**:
- Resource handle on success
- `FALSE` on error (also raises PHP ERROR)

**Examples**:
```php
// Simple query
$result = spi_exec("SELECT * FROM users");

// Query with limit
$result = spi_exec("SELECT * FROM large_table", 100);

// INSERT
$result = spi_exec("INSERT INTO log (message) VALUES ('test')");

// UPDATE
$result = spi_exec("UPDATE users SET active = true WHERE id = 1");

// DELETE
$result = spi_exec("DELETE FROM old_records WHERE created < '2020-01-01'");

// Query with RETURNING
$result = spi_exec("INSERT INTO users (name) VALUES ('Alice') RETURNING id");
```

**Query Types Supported**:
- SELECT
- INSERT / INSERT ... RETURNING
- UPDATE / UPDATE ... RETURNING
- DELETE / DELETE ... RETURNING
- Any other SQL statement PostgreSQL supports

**Error Handling**:
Errors raise PHP `E_ERROR` level, terminating function execution:
```php
// This will raise an error and abort
$result = spi_exec("SELECT * FROM nonexistent_table");
// Following code won't execute
```

**Subtransactions**:
Each `spi_exec()` call runs in a subtransaction, so errors don't abort the entire function transaction.

**Security Warning**:
No prepared statement support - must manually construct queries. Be careful with SQL injection:
```php
// UNSAFE - vulnerable to SQL injection
$name = $args[0];
$result = spi_exec("SELECT * FROM users WHERE name = '$name'");

// Better - validate input first
if (!preg_match('/^[a-zA-Z0-9_]+$/', $args[0])) {
    pg_raise('ERROR', 'Invalid input');
}
$result = spi_exec("SELECT * FROM users WHERE name = '{$args[0]}'");
```

---

### spi_fetch_row()

Fetch the next row from a query result.

**Signature**:
```php
array|false spi_fetch_row(resource $result)
```

**Parameters**:
- `$result` (resource, required) - Result resource from `spi_exec()`

**Returns**:
- Associative array (column_name => value) for next row
- `FALSE` when no more rows remain

**Examples**:
```php
// Basic iteration
$result = spi_exec("SELECT id, name, email FROM users");
while ($row = spi_fetch_row($result)) {
    echo "User: {$row['name']} ({$row['email']})\n";
}

// Process single row
$result = spi_exec("SELECT COUNT(*) AS total FROM users");
$row = spi_fetch_row($result);
$count = (int)$row['total'];

// Check for results
$result = spi_exec("SELECT * FROM users WHERE id = 999");
$row = spi_fetch_row($result);
if ($row === FALSE) {
    pg_raise('NOTICE', 'No user found');
} else {
    // Process row
}
```

**Row Data Format**:
All values are returned as strings (except NULL):
```php
$result = spi_exec("SELECT 42 AS num, 'hello' AS str, NULL AS nothing");
$row = spi_fetch_row($result);

var_dump($row);
// array(3) {
//   ["num"]     => string(2) "42"
//   ["str"]     => string(5) "hello"
//   ["nothing"] => NULL
// }

// Type conversion needed
$number = (int)$row['num'];  // Convert to integer
```

**NULL Handling**:
NULL database values become PHP `NULL`:
```php
if ($row['email'] === NULL) {
    echo "No email provided";
}
```

---

### spi_processed()

Get the number of rows processed by a query.

**Signature**:
```php
int spi_processed(resource $result)
```

**Parameters**:
- `$result` (resource, required) - Result resource from `spi_exec()`

**Returns**:
- Integer number of rows processed

**Examples**:
```php
// Count rows from SELECT
$result = spi_exec("SELECT * FROM users WHERE active = true");
$count = spi_processed($result);
pg_raise('NOTICE', "Found $count active users");

// Count affected rows from UPDATE
$result = spi_exec("UPDATE users SET last_login = NOW() WHERE active = true");
$updated = spi_processed($result);
pg_raise('NOTICE', "Updated $updated users");

// Count deleted rows
$result = spi_exec("DELETE FROM old_logs WHERE created < '2020-01-01'");
$deleted = spi_processed($result);
return $deleted;
```

**For Different Query Types**:
- SELECT: Number of rows returned
- INSERT: Number of rows inserted
- UPDATE: Number of rows updated
- DELETE: Number of rows deleted
- UTILITY: 0 or other value depending on command

---

### spi_status()

Get the execution status of a query as a string.

**Signature**:
```php
string spi_status(resource $result)
```

**Parameters**:
- `$result` (resource, required) - Result resource from `spi_exec()`

**Returns**:
- String describing query status

**Possible Return Values**:
- `"SPI_OK_SELECT"` - SELECT query
- `"SPI_OK_INSERT"` - INSERT without RETURNING
- `"SPI_OK_DELETE"` - DELETE without RETURNING
- `"SPI_OK_UPDATE"` - UPDATE without RETURNING
- `"SPI_OK_INSERT_RETURNING"` - INSERT with RETURNING
- `"SPI_OK_DELETE_RETURNING"` - DELETE with RETURNING
- `"SPI_OK_UPDATE_RETURNING"` - UPDATE with RETURNING
- `"SPI_OK_UTILITY"` - Utility command (CREATE, DROP, etc.)
- Error codes (various)

**Examples**:
```php
// Check query type
$result = spi_exec("INSERT INTO log (msg) VALUES ('test')");
$status = spi_status($result);
if ($status == "SPI_OK_INSERT") {
    pg_raise('NOTICE', 'Insert successful');
}

// Verify expected operation
$result = spi_exec($query);
$status = spi_status($result);
if ($status != "SPI_OK_SELECT") {
    pg_raise('ERROR', "Expected SELECT, got $status");
}

// Handle different query types
switch (spi_status($result)) {
    case "SPI_OK_SELECT":
        return spi_fetch_row($result);
    case "SPI_OK_INSERT":
    case "SPI_OK_UPDATE":
    case "SPI_OK_DELETE":
        return spi_processed($result);
    default:
        return NULL;
}
```

---

### spi_rewind()

Reset the result cursor to the beginning.

**Signature**:
```php
void spi_rewind(resource $result)
```

**Parameters**:
- `$result` (resource, required) - Result resource from `spi_exec()`

**Returns**:
- `NULL` (no return value)

**Examples**:
```php
// Process results twice
$result = spi_exec("SELECT id, name FROM users");

// First pass
while ($row = spi_fetch_row($result)) {
    // Process row
}

// Rewind and second pass
spi_rewind($result);
while ($row = spi_fetch_row($result)) {
    // Process row again
}

// Count and then process
$result = spi_exec("SELECT * FROM data");
$count = 0;
while (spi_fetch_row($result)) {
    $count++;
}
pg_raise('NOTICE', "Found $count rows, now processing...");

spi_rewind($result);
while ($row = spi_fetch_row($result)) {
    // Actually process the data
}
```

**Performance Note**:
All rows are already in memory - `spi_rewind()` just resets the internal counter. No additional query is executed.

---

## Error Handling

### pg_raise()

Raise a PostgreSQL notice, warning, or error message.

**Signature**:
```php
void pg_raise(string $level, string $message)
```

**Parameters**:
- `$level` (string, required) - Message level: `"ERROR"`, `"WARNING"`, or `"NOTICE"` (case-insensitive)
- `$message` (string, required) - Message text

**Returns**:
- No return value
- `ERROR` level does not return (aborts function)

**Levels**:

**ERROR**: Aborts function execution, rolls back transaction
```php
pg_raise('ERROR', 'Invalid input data');
// Function terminates here, following code not executed
```

**WARNING**: Logs warning, continues execution
```php
pg_raise('WARNING', 'Deprecated function used');
// Execution continues
```

**NOTICE**: Informational message, continues execution
```php
pg_raise('NOTICE', 'Processing batch 1 of 10');
// Execution continues
```

**Examples**:
```php
// Input validation
if ($args[0] < 0) {
    pg_raise('ERROR', 'Value must be non-negative');
}

// Progress reporting
for ($i = 0; $i < 100; $i++) {
    if ($i % 10 == 0) {
        pg_raise('NOTICE', "Progress: $i%");
    }
}

// Deprecation warning
pg_raise('WARNING', 'This function is deprecated, use new_func() instead');

// Debug information
pg_raise('NOTICE', 'Received arguments: ' . json_encode($args));

// Conditional errors
$result = spi_exec("SELECT * FROM users WHERE id = {$args[0]}");
if (spi_processed($result) == 0) {
    pg_raise('ERROR', "User {$args[0]} not found");
}
```

**Client Visibility**:
- ERROR: Always visible, aborts query
- WARNING: Visible depending on `client_min_messages` setting
- NOTICE: Visible depending on `client_min_messages` setting

---

## Set-Returning Functions

### return_next()

Return the next row in a set-returning function.

**Signature**:
```php
void return_next([array $row])
```

**Parameters**:
- `$row` (array, optional) - Row data as array

**Two Usage Modes**:

**1. Explicit Row (RETURNS SETOF type)**:
```php
// Function: RETURNS SETOF integer
for ($i = 1; $i <= 5; $i++) {
    return_next([$i]);
}
```

**2. Implicit Row (RETURNS TABLE)**:
```php
// Function: RETURNS TABLE(id int, name text)
$id = 1; $name = "Alice";
return_next();  // Uses $id and $name variables

$id = 2; $name = "Bob";
return_next();  // Uses new values
```

**Returns**:
- No return value
- Adds row to result set
- Function continues execution

**Examples**:

**Simple Generator**:
```sql
CREATE FUNCTION generate_series_php(int, int)
RETURNS SETOF int AS $$
    for ($i = $args[0]; $i <= $args[1]; $i++) {
        return_next([$i]);
    }
$$ LANGUAGE plphp;

SELECT * FROM generate_series_php(1, 10);
```

**RETURNS TABLE**:
```sql
CREATE FUNCTION get_users()
RETURNS TABLE(user_id int, user_name text) AS $$
    $result = spi_exec("SELECT id, name FROM users");
    while ($row = spi_fetch_row($result)) {
        $user_id = (int)$row['id'];
        $user_name = $row['name'];
        return_next();
    }
$$ LANGUAGE plphp;

SELECT * FROM get_users();
```

**Filtered Results**:
```sql
CREATE FUNCTION active_users()
RETURNS TABLE(id int, name text, email text) AS $$
    $result = spi_exec("SELECT id, name, email FROM users");
    while ($row = spi_fetch_row($result)) {
        // Filter in PHP
        if (strlen($row['email']) > 0) {
            $id = (int)$row['id'];
            $name = $row['name'];
            $email = $row['email'];
            return_next();
        }
    }
$$ LANGUAGE plphp;
```

**Computed Results**:
```sql
CREATE FUNCTION fibonacci(int)
RETURNS SETOF int AS $$
    $a = 0; $b = 1;
    for ($i = 0; $i < $args[0]; $i++) {
        return_next([$a]);
        $temp = $a + $b;
        $a = $b;
        $b = $temp;
    }
$$ LANGUAGE plphp;

SELECT * FROM fibonacci(10);
```

**Empty Result Set**:
```php
// Function returns no rows
if ($args[0] < 0) {
    // Don't call return_next() at all
    return;
}
```

**Errors**:
```php
// ERROR: Called outside set-returning function
function not_a_srf() {
    return_next([1]);  // ERROR!
}

// ERROR: Wrong number of columns
// RETURNS TABLE(a int, b int)
$a = 1;
// Missing $b
return_next();  // ERROR!
```

---

## Special Variables

### Function Arguments: $args and $argc

**Available in**: Regular functions (not triggers)

**$args**: Array of function arguments
```php
CREATE FUNCTION add(int, int) RETURNS int AS $$
    return (int)$args[0] + (int)$args[1];
$$ LANGUAGE plphp;
```

**$argc**: Count of arguments
```php
CREATE FUNCTION sum_all(int, int, int) RETURNS int AS $$
    $total = 0;
    for ($i = 0; $i < $argc; $i++) {
        $total += (int)$args[$i];
    }
    return $total;
$$ LANGUAGE plphp;
```

**Named Parameters**:
If function has named parameters, they're available as variables:
```php
CREATE FUNCTION greet(name text, age int) RETURNS text AS $$
    // Both work:
    return "Hello $name, you are $age years old";
    return "Hello {$args[0]}, you are {$args[1]} years old";
$$ LANGUAGE plphp;
```

**Type Conversions**:
All arguments arrive as strings - cast as needed:
```php
$int_val = (int)$args[0];
$float_val = (float)$args[1];
$bool_val = ($args[2] == 't' || $args[2] == 'true');
```

---

### Trigger Data: $_TD

**Available in**: Trigger functions only

**Structure**:
```php
$_TD = array(
    'name'       => string,   // Trigger name
    'relid'      => int,      // Relation OID
    'relname'    => string,   // Table name
    'schemaname' => string,   // Schema name
    'event'      => string,   // 'INSERT', 'UPDATE', 'DELETE'
    'when'       => string,   // 'BEFORE', 'AFTER'
    'level'      => string,   // 'ROW', 'STATEMENT'
    'argc'       => int,      // Trigger argument count
    'args'       => array,    // Trigger arguments (if argc > 0)
    'new'        => array,    // New row (INSERT/UPDATE row-level)
    'old'        => array,    // Old row (DELETE/UPDATE row-level)
);
```

**Event Types**:
- `$_TD['event']`: `"INSERT"`, `"UPDATE"`, or `"DELETE"`

**Timing**:
- `$_TD['when']`: `"BEFORE"` or `"AFTER"`

**Level**:
- `$_TD['level']`: `"ROW"` or `"STATEMENT"`

**Row Data**:
- `$_TD['new']`: Available for INSERT and UPDATE (row-level)
- `$_TD['old']`: Available for DELETE and UPDATE (row-level)

**Examples**:
```php
// Log all changes
CREATE FUNCTION audit_trigger() RETURNS trigger AS $$
    $table = $_TD['relname'];
    $event = $_TD['event'];
    pg_raise('NOTICE', "$event on $table");
    return NULL;
$$ LANGUAGE plphp;

// Validate before insert
CREATE FUNCTION validate_user() RETURNS trigger AS $$
    if ($_TD['event'] == 'INSERT' && $_TD['when'] == 'BEFORE') {
        if (strlen($_TD['new']['email']) == 0) {
            pg_raise('ERROR', 'Email required');
        }
    }
    return NULL;
$$ LANGUAGE plphp;

// Modify row before insert
CREATE FUNCTION set_created() RETURNS trigger AS $$
    if ($_TD['when'] == 'BEFORE' && $_TD['event'] == 'INSERT') {
        $_TD['new']['created_at'] = date('Y-m-d H:i:s');
        return 'MODIFY';
    }
    return NULL;
$$ LANGUAGE plphp;

// Track changes
CREATE FUNCTION track_update() RETURNS trigger AS $$
    if ($_TD['event'] == 'UPDATE') {
        $old_val = $_TD['old']['value'];
        $new_val = $_TD['new']['value'];
        pg_raise('NOTICE', "Changed from $old_val to $new_val");
    }
    return NULL;
$$ LANGUAGE plphp;
```

**Return Values**:

**For BEFORE Triggers**:
- `NULL` or not set: Use original row
- `"SKIP"`: Skip operation (don't insert/update/delete)
- `"MODIFY"`: Use modified `$_TD['new']` (INSERT/UPDATE only)

**For AFTER Triggers**:
- Return value ignored

---

## Type Handling

### Scalar Types

**PostgreSQL → PHP**:
All values arrive as strings:
```php
// PostgreSQL types → PHP strings
$result = spi_exec("SELECT 42::int, 3.14::float, true::bool, 'hello'::text");
$row = spi_fetch_row($result);

$row['int4']    // "42" (string)
$row['float8']  // "3.14" (string)
$row['bool']    // "t" or "f" (string)
$row['text']    // "hello" (string)
```

**Type Conversions**:
```php
$int = (int)$row['int4'];
$float = (float)$row['float8'];
$bool = ($row['bool'] == 't');
$string = $row['text'];  // Already string
```

**PHP → PostgreSQL**:
Return values converted to strings:
```php
return 42;        // → "42" → int4
return 3.14;      // → "3.14" → float8
return true;      // → "true" → bool
return "hello";   // → "hello" → text
```

### NULL Values

**PostgreSQL NULL → PHP NULL**:
```php
$result = spi_exec("SELECT NULL AS nothing");
$row = spi_fetch_row($result);
var_dump($row['nothing']);  // NULL
```

**PHP NULL → PostgreSQL NULL**:
```php
return NULL;  // Returns SQL NULL
```

### Arrays

**PostgreSQL Array → PHP Array**:
```php
$result = spi_exec("SELECT ARRAY[1,2,3] AS nums");
$row = spi_fetch_row($result);
$nums = $row['nums'];  // PHP array [1, 2, 3]
```

**PHP Array → PostgreSQL Array**:
```php
return [1, 2, 3];  // Returns PostgreSQL array
```

**Nested Arrays**:
```php
return [[1,2], [3,4]];  // 2D array
```

### Composite Types

**PostgreSQL Row → PHP Assoc Array**:
```php
CREATE TYPE person AS (name text, age int);

CREATE FUNCTION get_person() RETURNS person AS $$
    return ['name' => 'Alice', 'age' => 30];
$$ LANGUAGE plphp;
```

**Accessing Composite Arguments**:
```php
CREATE FUNCTION greet_person(person) RETURNS text AS $$
    $name = $args[0]['name'];
    $age = $args[0]['age'];
    return "Hello $name, age $age";
$$ LANGUAGE plphp;
```

---

## Best Practices

### Error Handling

**Always validate input**:
```php
if ($argc < 1) {
    pg_raise('ERROR', 'Insufficient arguments');
}
if (!is_numeric($args[0])) {
    pg_raise('ERROR', 'Argument must be numeric');
}
```

**Check query results**:
```php
$result = spi_exec($query);
if (spi_processed($result) == 0) {
    pg_raise('WARNING', 'No results found');
}
```

### Type Safety

**Cast arguments**:
```php
// Don't assume types
$bad = $args[0] + $args[1];  // String concatenation!

// Explicitly cast
$good = (int)$args[0] + (int)$args[1];
```

**Validate types**:
```php
if (!is_numeric($args[0])) {
    pg_raise('ERROR', 'Expected number');
}
```

### SQL Injection Prevention

**Avoid dynamic SQL with user input**:
```php
// Dangerous!
$table = $args[0];
$result = spi_exec("SELECT * FROM $table");

// Better - whitelist
$allowed_tables = ['users', 'posts', 'comments'];
if (!in_array($args[0], $allowed_tables)) {
    pg_raise('ERROR', 'Invalid table');
}
```

**Validate and escape**:
```php
// Still risky without proper escaping!
if (!preg_match('/^[a-zA-Z0-9_]+$/', $args[0])) {
    pg_raise('ERROR', 'Invalid identifier');
}
```

### Performance

**Avoid repeated queries**:
```php
// Bad - N queries
for ($i = 1; $i <= 100; $i++) {
    $result = spi_exec("SELECT * FROM users WHERE id = $i");
}

// Good - 1 query
$result = spi_exec("SELECT * FROM users WHERE id BETWEEN 1 AND 100");
```

**Use LIMIT**:
```php
// Get just what you need
$result = spi_exec("SELECT * FROM large_table LIMIT 100");
```

## Limitations

1. **No prepared statements** - All queries are dynamically constructed
2. **No cursors** - All result rows loaded into memory
3. **No transaction control** - Can't manually BEGIN/COMMIT/ROLLBACK
4. **Strings only** - All PostgreSQL values arrive as strings
5. **No async queries** - All queries are synchronous
6. **No connection pooling** - Uses current backend connection only

## Future API Additions

Potential future additions (not currently available):

```php
// Prepared statements
$plan = spi_prepare("SELECT * FROM users WHERE id = $1", ['int4']);
$result = spi_execute($plan, [42]);

// Cursors
$cursor = spi_cursor_open("SELECT * FROM large_table");
$rows = spi_cursor_fetch($cursor, 100);
spi_cursor_close($cursor);

// Transactions
spi_begin();
// ... operations ...
spi_commit();  // or spi_rollback()

// Escaping
$safe = spi_escape_string($user_input);
$safe_id = spi_escape_identifier($table_name);
```
