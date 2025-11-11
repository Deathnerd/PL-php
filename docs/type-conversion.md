# Type Conversion Layer (plphp_io.c/h)

## Overview

The type conversion layer handles all data marshaling between PostgreSQL's internal representation and PHP's zval system. This bidirectional conversion is critical for passing arguments to PHP functions and returning results to PostgreSQL.

Files:
- `plphp_io.c` (571 lines)
- `plphp_io.h` (41 lines)

## Public API

### Tuple Conversion

#### plphp_zval_from_tuple()
**Location**: `plphp_io.c:29`
**Signature**: `zval *plphp_zval_from_tuple(HeapTuple tuple, TupleDesc tupdesc)`

Converts a PostgreSQL tuple into a PHP associative array.

**Process**:
1. Create new PHP array (`array_init()`)
2. For each attribute in tuple:
   - Get attribute name from `tupdesc`
   - Get attribute value via `SPI_getvalue()`
   - Add to array as `$array[attribute_name] = value`
3. NULL values stored as PHP NULL

**Usage**: Building trigger `$_TD['new']` and `$_TD['old']`, SPI result rows

**Return**: Newly allocated zval (caller must free)

#### plphp_htup_from_zval()
**Location**: `plphp_io.c:72`
**Signature**: `HeapTuple plphp_htup_from_zval(zval *val, TupleDesc tupdesc)`

Converts a PHP array into a PostgreSQL HeapTuple.

**Two Modes**:
1. **Named Access**: Looks up array elements by attribute name
2. **Positional Access**: If no names match, uses first N elements in order

**Process**:
1. Create temporary memory context
2. Allocate `values` array (one per attribute)
3. Try named lookup for each attribute (`plphp_array_get_elem()`)
4. If all NULL (no names found), fall back to positional access
5. Build tuple via `BuildTupleFromCStrings()`
6. Delete temporary context
7. Return tuple (allocated in caller's context)

**Usage**: Function return values, trigger row modification

**Memory**: Tuple allocated in current context, temp context cleaned up

#### plphp_srf_htup_from_zval()
**Location**: `plphp_io.c:139`
**Signature**: `HeapTuple plphp_srf_htup_from_zval(zval *val, AttInMetadata *attinmeta, MemoryContext cxt)`

Specialized tuple builder for set-returning functions.

**Differences from plphp_htup_from_zval()**:
- Uses provided memory context (reset per row, not deleted)
- Always uses positional access (not named)
- Takes `AttInMetadata` instead of `TupleDesc`
- Handles single-element arrays specially for array-type returns

**Special Case**: If return type has one element and it's an array type, uses entire array as single value instead of iterating elements.

**Usage**: Called by `return_next()` in SRF execution

### Array Conversion

#### plphp_convert_to_pg_array()
**Location**: `plphp_io.c:232`
**Signature**: `char *plphp_convert_to_pg_array(zval *array)`

Converts a PHP array to PostgreSQL text array representation.

**Process**:
1. Initialize StringInfo buffer
2. Append opening `{`
3. For each array element:
   - `IS_LONG` → Append number
   - `IS_DOUBLE` → Append float
   - `IS_STRING` → Append `"string"`
   - `IS_ARRAY` → Recursive call for nested arrays
   - Separate elements with `,`
4. Append closing `}`

**Return**: Palloc'ed string (caller must free)

**Example Conversions**:
```php
[1, 2, 3]              → "{1,2,3}"
["a", "b"]             → '{"a","b"}'
[[1,2], [3,4]]         → "{{1,2},{3,4}}"
[1, "hello", 2.5]      → '{1,"hello",2.5}'
```

#### plphp_convert_from_pg_array()
**Location**: `plphp_io.c:297`
**Signature**: `zval *plphp_convert_from_pg_array(char *input TSRMLS_DC)`

Converts PostgreSQL text array representation to PHP array.

**Process**:
1. Transform `{...}` to `array(...)`
2. Pass to `zend_eval_string()`
3. Return resulting PHP array

**Example Transformations**:
```
"{1,2,3}"              → "array(1,2,3);"
'{"a","b"}'            → 'array("a","b");'
"{{1,2},{3,4}}"        → "array(array(1,2),array(3,4));"
```

**Known Issues**:
- FIXME: Doesn't work if embedded `{` in string values
- FIXME: Doesn't properly quote/dequote values
- Security: Uses `eval()` which could be dangerous with untrusted input

### Scalar Conversion

#### plphp_zval_get_cstring()
**Location**: `plphp_io.c:365`
**Signature**: `char *plphp_zval_get_cstring(zval *val, bool do_array, bool null_ok)`

Converts a PHP zval to a C string.

**Parameters**:
- `val` - The PHP value to convert
- `do_array` - If true, convert arrays; if false, error on arrays
- `null_ok` - If true, return NULL for NULL values; if false, error on NULL

**Conversions**:
- `IS_NULL` → NULL (if null_ok) or ERROR
- `IS_LONG` → `snprintf("%ld")`
- `IS_DOUBLE` → `snprintf("%f")`
- `IS_BOOL` → `"true"` or `"false"`
- `IS_STRING` → Copy string
- `IS_ARRAY` → Call `plphp_convert_to_pg_array()` (if do_array)

**Return**: Palloc'ed string (except for NULL), caller must free

**Buffer Sizes**:
- Numbers/bools: 64 bytes (fixed)
- Strings: Exact size + 1
- Arrays: Variable (built by `plphp_convert_to_pg_array()`)

### Helper Functions

#### plphp_array_get_elem()
**Location**: `plphp_io.c:333`
**Signature**: `zval *plphp_array_get_elem(zval *array, char *key)`

Retrieves an element from a PHP array by key.

**Process**:
1. Validate array is actually an array
2. Use `zend_symtable_find()` for lookup
3. Return element zval or NULL if not found

**Usage**: Looking up named parameters, tuple attributes

#### plphp_build_tuple_argument()
**Location**: `plphp_io.c:418`
**Signature**: `zval *plphp_build_tuple_argument(HeapTuple tuple, TupleDesc tupdesc)`

Builds a PHP associative array from a tuple, using output functions.

**Differs from plphp_zval_from_tuple()**:
- Uses type-specific output functions instead of `SPI_getvalue()`
- Skips dropped attributes
- Looks up `typoutput` from system cache for each attribute
- More robust for complex types

**Process**:
1. Create PHP array
2. For each attribute:
   - Skip if dropped
   - Get attribute value via `heap_getattr()`
   - If NULL, add as PHP NULL
   - Look up type's output function from syscache
   - Call output function to get string representation
   - Add to PHP array as `$array[attname] = value_string`
3. Return array

**Usage**: Building composite type arguments

#### plphp_modify_tuple()
**Location**: `plphp_io.c:494`
**Signature**: `HeapTuple plphp_modify_tuple(zval *outdata, TriggerData *tdata)`

Returns a modified tuple for BEFORE trigger row modification.

**Process**:
1. Create temporary memory context
2. Extract `$_TD['new']` from outdata
3. Validate it's an array
4. Get tuple descriptor from trigger data
5. Allocate values array
6. For each tuple attribute:
   - Look up value in `$_TD['new']` by attribute name
   - Convert via `plphp_zval_get_cstring()`
   - Store in values array
7. Build tuple from values
8. Delete temporary context
9. Return tuple (allocated in caller's context)

**Usage**: BEFORE trigger MODIFY return

**Error Conditions**:
- `$_TD['new']` not found → ERROR
- `$_TD['new']` not an array → ERROR
- Missing required attribute → ERROR
- Insufficient attributes → ERROR

## Memory Management

### Allocation Strategies

**Temporary Contexts**:
Many functions create temporary `AllocSetContext` for working memory:
```c
tmpcxt = AllocSetContextCreate(TopTransactionContext,
                               "context name",
                               ALLOCSET_DEFAULT_MINSIZE,
                               ALLOCSET_DEFAULT_INITSIZE,
                               ALLOCSET_DEFAULT_MAXSIZE);
```

**Context Cleanup**:
- `MemoryContextDelete(tmpcxt)` - Used by most functions
- `MemoryContextReset(cxt)` - Used by SRF functions (reused context)

**Return Values**:
Functions allocate return values in caller's context by switching back before allocation:
```c
MemoryContextSwitchTo(oldcxt);
ret = BuildTupleFromCStrings(attinmeta, values);
```

### PHP zval Management

**Allocation**:
```c
MAKE_STD_ZVAL(array);   // Allocate new zval
array_init(array);      // Initialize as array
```

**Population**:
```c
add_assoc_string(array, key, value, 1);  // 1 = duplicate string
add_assoc_null(array, key);
add_next_index_string(array, value, 1);
add_next_index_unset(array);  // Add NULL element
```

**Cleanup**:
```c
zval_dtor(val);   // Destroy zval contents
FREE_ZVAL(val);   // Free zval structure
```

## Type System Mapping

### PostgreSQL → PHP

| PostgreSQL Type | PHP Type | Conversion Method |
|----------------|----------|------------------|
| integer, bigint | IS_LONG | `snprintf("%ld")` |
| real, double | IS_DOUBLE | `snprintf("%f")` |
| boolean | IS_BOOL | `"true"`/`"false"` |
| text, varchar | IS_STRING | Direct copy |
| NULL | IS_NULL | NULL |
| composite | IS_ARRAY | Assoc array (attr → value) |
| array | IS_ARRAY | Nested array |

### PHP → PostgreSQL

| PHP Type | PostgreSQL Conversion |
|----------|---------------------|
| IS_LONG | String via `snprintf()` → input function |
| IS_DOUBLE | String via `snprintf()` → input function |
| IS_BOOL | `"true"`/`"false"` → input function |
| IS_STRING | Pass to input function |
| IS_NULL | NULL datum |
| IS_ARRAY (array ret) | `{...}` format → input function |
| IS_ARRAY (tuple ret) | `BuildTupleFromCStrings()` |

## Data Flow Examples

### Function Argument (PostgreSQL → PHP)

```
PostgreSQL int4 value: 42
    ↓
FunctionCall3(&arg_out_func, datum, ...)
    ↓
C string: "42"
    ↓
add_next_index_string($args, "42", 1)
    ↓
PHP: $args[0] == "42" (string!)
```

**Note**: All PostgreSQL values arrive in PHP as strings, requiring explicit casts if needed.

### Function Return (PHP → PostgreSQL)

```
PHP: return 42;  (IS_LONG)
    ↓
plphp_zval_get_cstring(phpret, false, false)
    ↓
C string: "42"
    ↓
FunctionCall3(&result_in_func, "42", ...)
    ↓
PostgreSQL int4 datum
```

### Array Argument (PostgreSQL → PHP)

```
PostgreSQL: ARRAY[1,2,3] → output function → "{1,2,3}"
    ↓
plphp_convert_from_pg_array("{1,2,3}")
    ↓
Transform to "array(1,2,3);"
    ↓
zend_eval_string("array(1,2,3);", retval, ...)
    ↓
PHP: [1, 2, 3]
```

### Tuple Argument (PostgreSQL → PHP)

```
PostgreSQL: (name => 'Alice', age => 30)
    ↓
plphp_build_tuple_argument(tuple, tupdesc)
    ↓
For each attribute:
  - heap_getattr() → Datum
  - typoutput() → C string
  - add_assoc_string()
    ↓
PHP: ['name' => 'Alice', 'age' => '30']
```

### Tuple Return (PHP → PostgreSQL)

```
PHP: return ['name' => 'Bob', 'age' => 25];
    ↓
plphp_htup_from_zval(phpret, tupdesc)
    ↓
For each attribute in tupdesc:
  - plphp_array_get_elem($phpret, 'name')
  - plphp_zval_get_cstring()
  - values[i] = "Bob"
    ↓
BuildTupleFromCStrings(attinmeta, values)
    ↓
PostgreSQL HeapTuple
```

## Edge Cases and Special Handling

### NULL Handling

**PostgreSQL NULL → PHP**:
```c
if (isnull)
    add_assoc_null(array, attname);
```

**PHP NULL → PostgreSQL**:
```c
case IS_NULL:
    return NULL;  // Caller interprets as NULL
```

### Dropped Attributes

Skipped in `plphp_build_tuple_argument()`:
```c
if (tupdesc->attrs[i]->attisdropped)
    continue;
```

### Single-Element Array Returns (SRF)

Special handling for array-type single-column returns:
```c
if (attinmeta->tupdesc->natts == 1) {
    // Check if it's actually an array type
    if (attinmeta->tupdesc->attrs[0]->attndims != 0 ||
        !OidIsValid(get_element_type(...)))
    {
        // Use first array element as the value
    }
    else
        // Use entire array as single value
}
```

### OUT Parameter Arrays

When function has multiple OUT parameters, builds associative array for RETURNS TABLE:
```c
if (out_aliases)
    sprintf(out_aliases, "$%s = array(&$args[%d]", ...);
```

## Known Issues and Limitations

### 1. Array String Heuristic
**Location**: Used in `plphp_func_build_args()` in plphp.c

Incorrectly identifies strings starting with `{` as arrays:
```c
if (tmp[0] == '{')
    hashref = plphp_convert_from_pg_array(tmp TSRMLS_CC);
```

**Problem**: String value `"{hello}"` treated as array

### 2. Array Conversion eval()
**Location**: `plphp_convert_from_pg_array()` (`plphp_io.c:319`)

Uses `zend_eval_string()` which:
- Fails on embedded `{` characters
- Security risk with untrusted input
- Doesn't handle complex escaping

### 3. Number Type Loss
All PostgreSQL values converted to strings when passed to PHP:
```php
// PostgreSQL: 42::int4
// PHP receives: "42" (string)
// Need explicit cast: (int)$args[0]
```

### 4. Float Precision
Double formatting uses simple `%f`:
```c
snprintf(ret, 64, "%f", Z_DVAL_P(val));
```
May lose precision or produce unexpected formatting.

### 5. Boolean Representation
Booleans converted to strings `"true"`/`"false"`:
```c
snprintf(ret, 8, "%s", Z_BVAL_P(val) ? "true": "false");
```
PostgreSQL input function must handle these strings.

## Testing Considerations

### Round-Trip Tests

Verify data integrity through conversion cycles:
```sql
-- Scalar round-trip
CREATE FUNCTION test_int(i int) RETURNS int AS $$
    return $args[0];
$$ LANGUAGE plphp;

-- Array round-trip
CREATE FUNCTION test_array(a int[]) RETURNS int[] AS $$
    return $args[0];
$$ LANGUAGE plphp;

-- Tuple round-trip
CREATE TYPE mytype AS (name text, value int);
CREATE FUNCTION test_tuple(t mytype) RETURNS mytype AS $$
    return $args[0];
$$ LANGUAGE plphp;
```

### NULL Tests

```sql
CREATE FUNCTION test_null() RETURNS int AS $$
    return NULL;
$$ LANGUAGE plphp;

CREATE FUNCTION accept_null(i int) RETURNS text AS $$
    return $args[0] === NULL ? 'null' : 'not null';
$$ LANGUAGE plphp;
```

### Nested Array Tests

```sql
SELECT test_array(ARRAY[[1,2],[3,4]]);
```

## Performance Considerations

### String Allocations

Each conversion allocates new strings:
- `snprintf()` for numbers → palloc(64)
- String copies → palloc(len + 1)
- Array conversions → StringInfo (dynamic)

**Impact**: High allocation rate for large datasets

### eval() Overhead

Array conversion uses `zend_eval_string()`:
- Full PHP parser invocation
- Compiler overhead
- Much slower than direct construction

**Alternative**: Direct zval manipulation would be faster

### Memory Contexts

Temporary contexts created per-conversion:
- Creation/deletion overhead
- Helps prevent leaks
- Trade-off: safety vs. performance

## Optimization Opportunities

1. **Cache type output functions**: Currently looked up on every call
2. **Direct zval array construction**: Avoid eval() for array parsing
3. **Reuse memory contexts**: Reset instead of delete/create
4. **Binary protocol**: Skip string conversion for binary-compatible types
5. **Type-specific fast paths**: Hardcode conversions for common types (int4, text, etc.)

## Debugging Tips

**Inspect zval contents**:
```c
php_var_dump(&array, 1 TSRMLS_CC);  // Dump to output
```

**Check memory context**:
```c
elog(NOTICE, "Current context: %s",
     CurrentMemoryContext->name);
```

**Trace allocations**:
Enable `DEBUG_PLPHP_MEMORY` to track PHP memory usage

**Verify tuple structure**:
```c
elog(NOTICE, "Tuple has %d attributes", tupdesc->natts);
for (int i = 0; i < tupdesc->natts; i++)
    elog(NOTICE, "Attr %d: %s (type %u)",
         i, tupdesc->attrs[i]->attname.data,
         tupdesc->attrs[i]->atttypid);
```
