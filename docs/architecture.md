# PL/php Architecture Overview

## Introduction

PL/php is a PostgreSQL procedural language extension that embeds the PHP interpreter within PostgreSQL, allowing stored procedures, triggers, and functions to be written in PHP. This document describes the overall architecture and how the various components interact.

## System Architecture

PL/php operates by embedding the PHP interpreter (via the embed SAPI) within PostgreSQL backend processes. Each backend maintains its own instance of the PHP interpreter, initialized on the first PL/php function call.

### Execution Flow

1. **PostgreSQL Function Call** → PostgreSQL's function manager invokes `plphp_call_handler()`
2. **Initialization** → PHP interpreter initialized on first call via `plphp_init()`
3. **Compilation** → Function source compiled and cached via `plphp_compile_function()`
4. **Execution** → Appropriate handler invoked (function, trigger, or SRF)
5. **Return** → Result converted from PHP to PostgreSQL format

## Core Components

### 1. Language Handler (plphp.c)

The main entry point and orchestrator. Key responsibilities:

- **PHP Interpreter Management**: Initializes and configures the embedded PHP interpreter
- **Function Dispatching**: Routes calls to appropriate handlers (regular, trigger, SRF)
- **Function Compilation & Caching**: Compiles PHP source into callable functions
- **Error Handling**: Bridges PHP errors to PostgreSQL error system
- **Memory Management**: Coordinates between PostgreSQL and PHP memory systems

Entry points:
- `plphp_call_handler()` - Main function/trigger invocation
- `plphp_validator()` - Function syntax validation at creation time

### 2. Type Conversion Layer (plphp_io.c/h)

Handles bidirectional data conversion between PostgreSQL and PHP:

- **Tuple ↔ PHP Array**: Converts PostgreSQL rows to/from PHP associative arrays
- **Array Conversion**: PostgreSQL arrays ↔ PHP arrays
- **Scalar Conversion**: PostgreSQL datums ↔ PHP scalars (int, float, string, bool)
- **Type Metadata**: Manages type information and conversion functions

### 3. SPI Interface (plphp_spi.c/h)

Provides PHP functions for executing SQL from within PL/php procedures:

- **Query Execution**: `spi_exec()` - Execute SQL and return results
- **Result Iteration**: `spi_fetch_row()`, `spi_rewind()`
- **Result Metadata**: `spi_processed()`, `spi_status()`
- **Error Reporting**: `pg_raise()` - Raise PostgreSQL notices/warnings/errors
- **Set-Returning Functions**: `return_next()` - Return rows incrementally

## Execution Modes

### Regular Functions

Flow:
1. `plphp_call_handler()` called by PostgreSQL
2. `plphp_compile_function()` retrieves/compiles function
3. `plphp_func_handler()` executes function
4. `plphp_call_php_func()` invokes PHP code
5. Return value converted via type conversion layer

PHP function signature: `function plphp_proc_<oid>($args, $argc)`

### Triggers

Flow:
1. `plphp_call_handler()` detects trigger context
2. `plphp_trigger_handler()` builds `$_TD` array with trigger data
3. `plphp_call_php_trig()` invokes PHP trigger function
4. Return value determines action (SKIP, MODIFY, or pass-through)

PHP function signature: `function plphp_proc_<oid>_trigger($_TD)`

Available in `$_TD`:
- `name`, `relid`, `relname`, `schemaname` - Trigger metadata
- `event` - INSERT, UPDATE, or DELETE
- `when` - BEFORE or AFTER
- `level` - ROW or STATEMENT
- `new`, `old` - Row data (for row-level triggers)
- `args`, `argc` - Trigger arguments

### Set-Returning Functions (SRF)

Flow:
1. `plphp_srf_handler()` sets up tuplestore
2. PHP function calls `return_next()` for each row
3. `return_next()` adds tuples to tuplestore
4. Final tuplestore returned to PostgreSQL

PHP usage: Call `return_next($row_array)` for each result row.

## Memory Management

PL/php must carefully manage memory across two systems:

### PostgreSQL Memory Contexts

- **TopMemoryContext** - Permanent allocations (function cache)
- **CurrentTransactionContext** - Per-transaction allocations
- **SPI Memory Context** - SPI query results
- **Per-query Context** - SRF tuplestore

### PHP Memory Management

- **Zend Memory Manager** - PHP's internal allocator
- **Symbol Tables** - PHP variable storage
- **zval Reference Counting** - PHP value lifecycle

### Coordination

- Function metadata stored in `malloc()` (permanent)
- PostgreSQL data conversions use `palloc()` (context-aware)
- PHP values use Zend allocator
- Careful cleanup required to prevent leaks across boundaries

## Version Compatibility

PL/php supports multiple PostgreSQL versions through conditional compilation:

```c
#define PG_VERSION_81_COMPAT  // PostgreSQL 8.1+
#define PG_VERSION_82_COMPAT  // PostgreSQL 8.2+ (requires PG_MODULE_MAGIC)
#define PG_VERSION_83_COMPAT  // PostgreSQL 8.3+
```

Version-specific code uses `#ifdef` guards to handle API differences.

## Function Compilation and Caching

### Compilation Process

1. **Source Extraction**: Retrieve `prosrc` from `pg_proc`
2. **Function Wrapping**: Wrap source in PHP function declaration
3. **Argument Aliases**: Create named parameter aliases if provided
4. **OUT Parameter Handling**: Special return logic for OUT/INOUT parameters
5. **Evaluation**: Execute via `zend_eval_string()`
6. **Caching**: Store function descriptor in `plphp_proc_array`

### Cache Key

Functions cached by internal name: `plphp_proc_<oid>` or `plphp_proc_<oid>_trigger`

### Cache Invalidation

Function recompiled if:
- `fn_xmin` (transaction ID) changes
- `fn_cmin` (command ID) changes

## Error Handling

### PHP → PostgreSQL Error Translation

The `plphp_error_cb()` callback translates PHP errors:

- `E_ERROR`, `E_CORE_ERROR`, `E_COMPILE_ERROR`, `E_USER_ERROR`, `E_PARSE` → ERROR
- `E_WARNING`, `E_CORE_WARNING`, `E_COMPILE_WARNING`, `E_USER_WARNING`, `E_STRICT` → WARNING
- `E_NOTICE`, `E_USER_NOTICE` → NOTICE

### Subtransactions

SPI calls wrapped in subtransactions:
1. `BeginInternalSubTransaction()` before SPI call
2. `ReleaseCurrentSubTransaction()` on success
3. `RollbackAndReleaseCurrentSubTransaction()` on error

This ensures failed SQL doesn't abort the entire function.

## PHP Configuration

PL/php configures PHP with hardcoded settings:

```c
INI_HARDCODED("register_argc_argv", "0");
INI_HARDCODED("html_errors", "0");
INI_HARDCODED("implicit_flush", "1");
INI_HARDCODED("max_execution_time", "0");
INI_HARDCODED("max_input_time", "-1");
INI_HARDCODED("memory_limit", "1073741824");  // 1GB
```

## Security Model

- **Trusted vs Untrusted**: Language can be installed as trusted or untrusted
- **PHP Safe Mode**: `PG(safe_mode)` activated based on function's language trust level
- **Function Isolation**: Each function execution uses isolated symbol table

## Header Inclusion Order

Critical requirement: PostgreSQL headers MUST be included before PHP headers.

Both define `PACKAGE_*` macros, so PL/php undefines them between includes:

```c
#undef PACKAGE_BUGREPORT
#undef PACKAGE_NAME
// ... include PostgreSQL headers
#undef PACKAGE_BUGREPORT
#undef PACKAGE_NAME
// ... include PHP headers
```

## Data Flow Diagrams

### Function Call Flow

```
PostgreSQL Function Manager
    ↓
plphp_call_handler()
    ↓
SPI_connect()
    ↓
plphp_compile_function()
    ↓
plphp_func_handler()
    ↓
plphp_call_php_func()
    ↓ [builds $args array]
plphp_func_build_args()
    ↓ [executes PHP]
call_user_function_ex()
    ↓ [converts result]
Type Conversion Layer
    ↓
SPI_finish()
    ↓
Return to PostgreSQL
```

### Type Conversion Flow

```
PostgreSQL Datum
    ↓
FunctionCall3(&desc->arg_out_func, ...)
    ↓
plphp_convert_from_pg_array() [if array]
    ↓
add_next_index_string() [populate zval]
    ↓
PHP zval available in $args

[Return path]

PHP return value (zval)
    ↓
plphp_zval_get_cstring() [scalar]
plphp_convert_to_pg_array() [array]
plphp_htup_from_zval() [tuple]
    ↓
FunctionCall3(&desc->result_in_func, ...)
    ↓
PostgreSQL Datum
```

## Extension Points

### Adding New PHP Functions

To add new PHP-callable functions:

1. Define function in `plphp_spi.c` using `ZEND_FUNCTION()` macro
2. Add declaration to `plphp_spi.h`
3. Add entry to `spi_functions[]` array
4. Register during initialization in `plphp_init()`

### Adding New Data Type Conversions

Extend conversion functions in `plphp_io.c`:

- Modify `plphp_zval_get_cstring()` for PHP → string
- Modify `plphp_convert_to_pg_array()` for array handling
- Add type-specific logic in `plphp_build_tuple_argument()`

## Performance Considerations

### Function Caching

- Compiled functions cached permanently (until backend exit)
- Avoids re-parsing PHP source on every call
- Cache lookup by OID is fast (hash table)

### Memory Leaks

- PHP allocations persist until backend exit
- Cannot easily reclaim per-function memory
- Long-running backends may accumulate memory
- Documented FIXME: need per-function memory contexts

### SPI Overhead

- Each SPI call has subtransaction overhead
- Result copying from SPI to PHP arrays
- Large result sets consume memory in both systems

## Known Limitations

1. **Thread Safety**: PHP must be built non-threadsafe (ZTS disabled)
2. **Memory Growth**: Function cache never freed until backend exit
3. **Array Detection**: Heuristic detection of arrays (starts with '{') is fragile
4. **Global State**: Some PHP global state persists across function calls
5. **Parameter Passing**: All parameters passed by value, not reference (except for trigger `$_TD`)
