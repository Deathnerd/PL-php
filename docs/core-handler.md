# Core Language Handler (plphp.c)

## Overview

`plphp.c` is the main module of PL/php, serving as the language handler that PostgreSQL calls to execute PHP functions. It manages the PHP interpreter lifecycle, function compilation and caching, and coordinates the execution of regular functions, triggers, and set-returning functions.

Location: `plphp.c` (1953 lines)

## Key Data Structures

### plphp_proc_desc

The function descriptor structure that caches compiled function metadata:

```c
typedef struct plphp_proc_desc
{
    char       *proname;          // Internal function name
    TransactionId fn_xmin;        // Transaction ID for cache validation
    CommandId  fn_cmin;           // Command ID for cache validation
    bool       trusted;           // Trusted language flag
    pl_type    ret_type;          // Return type flags (bitmask)
    Oid        ret_oid;           // OID of return type
    bool       retset;            // Returns a set?
    FmgrInfo   result_in_func;    // Input function for result
    Oid        result_typioparam; // Type IO parameter
    int        n_out_args;        // Number of OUT arguments
    int        n_total_args;      // Total argument count
    int        n_mixed_args;      // Number of INOUT arguments
    FmgrInfo   arg_out_func[FUNC_MAX_ARGS];
    Oid        arg_typioparam[FUNC_MAX_ARGS];
    char       arg_typtype[FUNC_MAX_ARGS];
    char       arg_argmode[FUNC_MAX_ARGS];
    TupleDesc  args_out_tupdesc;  // Tuple descriptor for OUT args
} plphp_proc_desc;
```

### pl_type

Return type bitmask enum:

```c
typedef enum pl_type
{
    PL_TUPLE  = 1 << 0,  // Returns a tuple/row
    PL_ARRAY  = 1 << 1,  // Returns an array
    PL_PSEUDO = 1 << 2   // Returns a pseudotype
} pl_type;
```

### Global Variables

```c
static bool plphp_first_call = true;        // First call flag
static zval *plphp_proc_array = NULL;       // Function cache (PHP array)
static StringInfo currmsg = NULL;           // Buffer for PHP output
static char *error_msg = NULL;              // Error message from PHP
```

## Main Entry Points

### plphp_call_handler()

**Location**: `plphp.c:540`

The primary entry point called by PostgreSQL's function manager.

**Flow**:
1. Initialize PHP interpreter (`plphp_init_all()`)
2. Connect to SPI manager
3. Determine call type (trigger vs. regular vs. SRF)
4. Compile/retrieve function (`plphp_compile_function()`)
5. Set PHP safe mode based on trust level
6. Dispatch to appropriate handler
7. Handle errors via `zend_try`/`zend_catch`

**Wrapped in**:
- `PG_TRY()`/`PG_CATCH()` - PostgreSQL exception handling
- `zend_try`/`zend_catch` - PHP exception handling

### plphp_validator()

**Location**: `plphp.c:622`

Validates function syntax at CREATE FUNCTION time.

**Process**:
1. Retrieve function source from `pg_proc`
2. Wrap source in temporary function declaration
3. Attempt to compile via `zend_eval_string()`
4. Delete temporary function from PHP function table
5. Raise ERROR if validation fails

**Validation Function Format**:
```c
sprintf(tmpsrc, "function %s($args, $argc){%s}", tmpname, prosrc);
```

## PHP Interpreter Management

### plphp_init()

**Location**: `plphp.c:403`

Initializes the embedded PHP interpreter (called once per backend).

**Steps**:
1. Replace Zend error callback with `plphp_error_cb()`
2. Initialize SAPI module (`sapi_startup()`)
3. Start PHP module (`php_module_startup()`)
4. Initialize procedure cache array (`plphp_proc_array`)
5. Register SPI functions (`zend_register_functions()`)
6. Start PHP request (`php_request_startup()`)
7. Register SPI result resource type
8. Set hardcoded INI values

**Critical INI Settings**:
```c
INI_HARDCODED("register_argc_argv", "0");
INI_HARDCODED("html_errors", "0");
INI_HARDCODED("implicit_flush", "1");
INI_HARDCODED("max_execution_time", "0");
INI_HARDCODED("max_input_time", "-1");
INI_HARDCODED("memory_limit", "1073741824");  // 1GB
```

### SAPI Module (plphp_sapi_module)

**Location**: `plphp.c:346`

Defines the Server API integration for embedded PHP:

```c
static sapi_module_struct plphp_sapi_module = {
    "plphp",                         // name
    "PL/php PostgreSQL Handler",     // pretty name
    NULL,                            // startup
    php_module_shutdown_wrapper,     // shutdown
    NULL,                            // activate
    NULL,                            // deactivate
    sapi_plphp_write,               // unbuffered write
    sapi_plphp_flush,               // flush
    // ... other callbacks
};
```

**SAPI Callbacks**:

#### sapi_plphp_write()
**Location**: `plphp.c:289`

Captures PHP output (from `echo`, `print`, etc.) into a StringInfo buffer.

#### sapi_plphp_flush()
**Location**: `plphp.c:309`

Sends buffered output to PostgreSQL log via `elog(LOG, ...)`. Only flushes if message ends with newline.

## Function Compilation and Caching

### plphp_compile_function()

**Location**: `plphp.c:1180`

Compiles or retrieves a cached function descriptor.

**Cache Lookup**:
1. Build internal name: `plphp_proc_<oid>` or `plphp_proc_<oid>_trigger`
2. Look up in `plphp_proc_array` (PHP associative array)
3. Validate cache entry against `fn_xmin` and `fn_cmin`
4. Return cached descriptor if valid

**Compilation Process**:
1. Allocate `plphp_proc_desc` via `malloc()` (permanent)
2. Determine return type and flags
3. Process arguments (names, modes, types)
4. Build function source with argument aliases
5. Handle OUT/INOUT parameters specially
6. Evaluate source via `zend_eval_string()`
7. Store descriptor pointer in cache

**Function Source Format**:

Regular function:
```c
sprintf(complete_proc_source,
        "function %s($args, $argc){%s %s;%s; %s}",
        internal_proname,
        aliases ? aliases : "",          // $var1 = &$args[0];
        out_aliases ? out_aliases : "",  // Array of OUT args
        proc_source,                     // User source
        out_return_str ? out_return_str : "");
```

Trigger function:
```c
sprintf(complete_proc_source,
        "function %s($_TD){%s}",
        internal_proname,
        proc_source);
```

**Argument Alias Generation**:

Named parameters become variables:
```c
sprintf(aliases + alias_str_end, " $%s = &$args[%d];", argnames[i], i);
```

**OUT Parameter Handling**:

Single OUT parameter:
```c
snprintf(out_return_str, NAMEDATALEN + 32, "return $args[%d];", i);
```

Multiple OUT parameters (creates return array):
```c
snprintf(out_aliases, ..., "$_plphp_ret_%s = array(&$args[%d]", ...);
snprintf(out_return_str, ..., "return $_plphp_ret_%s;", ...);
```

## Function Execution Handlers

### plphp_func_handler()

**Location**: `plphp.c:961`

Handles regular (non-SRF, non-trigger) function calls.

**Flow**:
1. Call `plphp_call_php_func()` to execute PHP
2. Validate return type matches declaration
3. Disconnect from SPI
4. Convert PHP return value to PostgreSQL Datum
5. Handle NULL, scalar, array, and tuple returns

**Return Type Processing**:
- `IS_NULL` → Set `fcinfo->isnull = true`
- `IS_BOOL/IS_DOUBLE/IS_LONG/IS_STRING` → Convert via `plphp_zval_get_cstring()`
- `IS_ARRAY` (array return) → `plphp_convert_to_pg_array()`
- `IS_ARRAY` (tuple return) → `plphp_htup_from_zval()`

### plphp_trigger_handler()

**Location**: `plphp.c:860`

Handles trigger function calls.

**Flow**:
1. Build `$_TD` array via `plphp_trig_build_args()`
2. Call `plphp_call_php_trig()` with `$_TD`
3. Process return value:
   - `"SKIP"` → Skip operation
   - `"MODIFY"` → Modify tuple via `plphp_modify_tuple()`
   - `NULL` → Use original/new tuple
4. Disconnect from SPI
5. Return appropriate tuple

**$_TD Array Structure**:

Built by `plphp_trig_build_args()` (`plphp.c:759`):

```php
$_TD = [
    'name'       => trigger_name,
    'relid'      => relation_oid,
    'relname'    => relation_name,
    'schemaname' => schema_name,
    'event'      => 'INSERT'|'UPDATE'|'DELETE',
    'when'       => 'BEFORE'|'AFTER',
    'level'      => 'ROW'|'STATEMENT',
    'argc'       => arg_count,
    'args'       => [arg1, arg2, ...],  // If tgnargs > 0
    'new'        => [...],               // For INSERT/UPDATE
    'old'        => [...]                // For DELETE/UPDATE
];
```

### plphp_srf_handler()

**Location**: `plphp.c:1087`

Handles set-returning functions.

**Setup**:
1. Set global `current_fcinfo`, `current_tupledesc`, `current_attinmeta`
2. Create per-SRF memory context (`current_memcxt`)
3. Verify `ReturnSetInfo` is valid

**Execution**:
1. Call `plphp_call_php_func()`
2. PHP function calls `return_next()` for each row
3. `return_next()` populates tuplestore
4. Return tuplestore via `ReturnSetInfo`

**Cleanup**:
1. Delete SRF memory context
2. Clear global SRF variables
3. Return `(Datum) 0`

**Global Variables Used**:
```c
FunctionCallInfo current_fcinfo;
TupleDesc current_tupledesc;
AttInMetadata *current_attinmeta;
MemoryContext current_memcxt;
Tuplestorestate *current_tuplestore;
```

## PHP Function Invocation

### plphp_call_php_func()

**Location**: `plphp.c:1732`

Invokes a PHP function with proper symbol table isolation.

**Process**:
1. Create private symbol table (hashtable)
2. Build `$args` array via `plphp_func_build_args()`
3. Create `$argc` scalar
4. Build function name zval
5. Switch to private symbol table
6. Call `call_user_function_ex()`
7. Restore original symbol table
8. Clean up private symbol table

**Symbol Table Isolation**: Prevents variable pollution between function calls.

### plphp_func_build_args()

**Location**: `plphp.c:1603`

Builds the `$args` array passed to PHP functions.

**For each argument**:
1. Skip OUT-only arguments (set to NULL)
2. Handle pseudotypes (resolve actual type)
3. Handle composite types (convert to PHP array)
4. Handle scalars:
   - Get string representation via output function
   - Detect arrays (heuristic: starts with `{`)
   - Convert arrays via `plphp_convert_from_pg_array()`
   - Add to `$args` array

**Array Detection Issue**: Uses heuristic `tmp[0] == '{'` which can misidentify strings starting with '{'.

### plphp_call_php_trig()

**Location**: `plphp.c:1807`

Invokes trigger function with `$_TD` parameter.

**Special Handling**:
- Marks `$_TD` as reference (`Z_SET_ISREF_P`) so PHP function can modify it
- Allows MODIFY return to work by modifying `$_TD['new']`
- Unsets reference flag after call

## Error Handling

### plphp_error_cb()

**Location**: `plphp.c:1854`

Custom PHP error callback that translates PHP errors to PostgreSQL errors.

**Error Level Translation**:
```c
E_ERROR, E_CORE_ERROR, E_COMPILE_ERROR,
E_USER_ERROR, E_PARSE                    → ERROR
E_WARNING, E_CORE_WARNING, E_COMPILE_WARNING,
E_USER_WARNING, E_STRICT                 → WARNING
E_NOTICE, E_USER_NOTICE                  → NOTICE
```

**For ERROR-level problems**:
1. Save error message to `error_msg` global
2. Call `zend_bailout()` to exit PHP execution
3. Caught by outer `zend_catch` block
4. Converted to PostgreSQL `elog(ERROR, ...)`

## Utility Functions

### perm_fmgr_info()

**Location**: `plphp.c:277`

Wrapper around `fmgr_info_cxt()` that allocates in `TopMemoryContext` for permanent storage.

**Purpose**: Function metadata must persist across calls.

### is_valid_php_identifier()

**Location**: `plphp.c:1929`

Validates that a PostgreSQL parameter name can be used as a PHP variable name.

**Rules**:
- Must start with letter
- Subsequent characters: letters, digits, or underscores

### plphp_get_function_tupdesc()

**Location**: `plphp.c:736`

Gets the tuple descriptor for a function's return type.

**For RECORD types**: Extracts from `ReturnSetInfo->expectedDesc`
**For other composite types**: Uses `lookup_rowtype_tupdesc()`

## Version Compatibility Macros

```c
#if (CATALOG_VERSION_NO >= 200709301)
#define PG_VERSION_83_COMPAT
#endif
#if (CATALOG_VERSION_NO >= 200611241)
#define PG_VERSION_82_COMPAT
#endif
#if (CATALOG_VERSION_NO >= 200510211)
#define PG_VERSION_81_COMPAT
#else
#error "Unsupported PostgreSQL version"
#endif
```

**PG 8.3 Changes**:
- Use `HeapTupleHeaderGetRawCommandId()` instead of `HeapTupleHeaderGetCmin()`
- Different transaction visibility rules

**PG 8.2 Changes**:
- Requires `PG_MODULE_MAGIC` declaration

## Memory Management Notes

**Permanent Allocations** (via `malloc`):
- `plphp_proc_desc` structures
- Function names (`proname`)

**Per-call Allocations** (via `palloc`):
- Function source strings
- Argument aliases
- Return value buffers

**PHP Allocations**:
- Managed by Zend memory manager
- Persists until backend exit
- FIXME: Should use per-function contexts for cleanup

## Security Considerations

**Safe Mode**: Controlled by `PG(safe_mode) = desc->trusted`
- Restricts certain PHP functions
- Based on language trust level (trusted vs. untrusted)

**Function Validation**:
- All functions validated at CREATE time
- Prevents syntax errors from causing crashes

**Subtransaction Isolation**: SPI calls use subtransactions (handled in plphp_spi.c)

## Performance Notes

**Function Caching**:
- Compiled functions cached permanently
- Cache key: `plphp_proc_<oid>`
- No eviction policy (cache grows unbounded)

**Cache Invalidation**:
- Only on function redefinition
- Detected via `fn_xmin`/`fn_cmin` changes

**Memory Growth**:
- PHP allocations never freed
- Long-running backends accumulate memory
- Recommendation: Periodic backend recycling for heavy PL/php use

## Known Issues and FIXMEs

1. **Memory Context Management** (`plphp.c:265`): Should use per-function memory contexts instead of permanent malloc allocations

2. **Array Detection** (`plphp.c:1698`): Heuristic `tmp[0] == '{'` incorrectly identifies some strings as arrays

3. **Parameter Freeing** (`plphp.c:1714`): Unclear which parameters need `pfree()` after output function call

4. **sprintf Safety** (`plphp.c:1551`): Comment questions whether sprintf usage is safe (potential buffer overflow)

## Debugging

**Memory Usage Reporting**:
```c
#define DEBUG_PLPHP_MEMORY
```
When defined, reports PHP memory usage at various points via `REPORT_PHP_MEMUSAGE()`.

**Function Source Logging**:
The compiled function source is logged at `LOG` level:
```c
elog(LOG, "complete_proc_source = %s", complete_proc_source);
```

## Common Code Patterns

**Error Handling Pattern**:
```c
PG_TRY();
{
    zend_try
    {
        // PHP code execution
    }
    zend_catch
    {
        // Handle PHP errors
        if (error_msg) {
            // Report error
        }
    }
    zend_end_try();
}
PG_CATCH();
{
    PG_RE_THROW();
}
PG_END_TRY();
```

**Symbol Table Management**:
```c
HashTable *orig_symbol_table = EG(active_symbol_table);
EG(active_symbol_table) = symbol_table;
// ... execute PHP
EG(active_symbol_table) = orig_symbol_table;
zend_hash_clean(symbol_table);
```
