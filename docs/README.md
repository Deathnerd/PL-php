# PL/php Documentation

Comprehensive documentation for PL/php, a procedural language extension for PostgreSQL that allows writing stored procedures, triggers, and functions in PHP.

## Documentation Structure

### Getting Started

| Document | Description |
|----------|-------------|
| [README](../README) | Project overview and quick start |
| [INSTALL](../INSTALL) | Installation instructions |
| [Build System](build-system.md) | Detailed build and configuration guide |

### Architecture and Internals

| Document | Description |
|----------|-------------|
| [Architecture Overview](architecture.md) | High-level system architecture and component interaction |
| [Core Handler](core-handler.md) | `plphp.c` - Language handler and PHP interpreter management |
| [Type Conversion](type-conversion.md) | `plphp_io.c/h` - Data marshaling between PostgreSQL and PHP |
| [SPI Interface](spi-interface.md) | `plphp_spi.c/h` - SQL execution from PHP code |

### Development

| Document | Description |
|----------|-------------|
| [Testing Framework](testing.md) | Regression test suite and testing procedures |
| [API Reference](api-reference.md) | PHP API available within PL/php functions |

## Quick Reference

### Building PL/php

```bash
# Generate configure script
autoconf

# Configure
./configure [--with-postgres=/path] [--with-php=/path]

# Build and install
make
sudo make install

# Run tests
make installcheck
```

See [Build System](build-system.md) for details.

### Available PHP Functions

PL/php provides these functions for database interaction:

| Function | Purpose |
|----------|---------|
| `spi_exec($query, $limit)` | Execute SQL query |
| `spi_fetch_row($result)` | Fetch next result row |
| `spi_processed($result)` | Get row count |
| `spi_status($result)` | Get execution status |
| `spi_rewind($result)` | Reset result cursor |
| `pg_raise($level, $msg)` | Raise notice/warning/error |
| `return_next($row)` | Return row in set-returning function |

See [API Reference](api-reference.md) for complete details.

### Code Organization

PL/php consists of three main C modules:

```
plphp.c       - Core language handler (1953 lines)
├─ plphp_call_handler()    - Main entry point
├─ plphp_validator()       - Function validation
├─ plphp_compile_function() - Compilation and caching
└─ PHP interpreter init    - Embedded PHP setup

plphp_io.c    - Type conversion layer (571 lines)
├─ PostgreSQL → PHP        - Tuple to zval conversion
├─ PHP → PostgreSQL        - zval to tuple conversion
└─ Array handling          - Array marshaling

plphp_spi.c   - SPI interface (542 lines)
├─ spi_exec()             - Query execution
├─ spi_fetch_row()        - Result iteration
└─ return_next()          - SRF support
```

See [Architecture Overview](architecture.md) for details.

## Common Tasks

### Understanding Function Execution

**Regular Function Flow**:
1. PostgreSQL calls `plphp_call_handler()` (plphp.c:540)
2. Function compiled/cached by `plphp_compile_function()` (plphp.c:1180)
3. Handler dispatches to `plphp_func_handler()` (plphp.c:961)
4. PHP code executed via `plphp_call_php_func()` (plphp.c:1732)
5. Arguments built by `plphp_func_build_args()` (plphp.c:1603)
6. Return value converted via type conversion layer

See [Core Handler](core-handler.md) for details.

### Understanding Type Conversion

**PostgreSQL to PHP**:
- Tuples → Associative arrays
- Arrays → PHP arrays
- Scalars → Strings (requires casting in PHP)
- NULL → NULL

**PHP to PostgreSQL**:
- Arrays → PostgreSQL arrays or tuples
- Scalars → Type-specific conversion
- NULL → NULL

See [Type Conversion](type-conversion.md) for details.

### Understanding SPI Queries

**Query Execution**:
```php
$result = spi_exec("SELECT * FROM users");  // Execute
while ($row = spi_fetch_row($result)) {     // Iterate
    // Process row
}
$count = spi_processed($result);            // Get count
```

**Subtransactions**:
- Each `spi_exec()` runs in subtransaction
- Failed queries don't abort entire function
- Automatic rollback on error

See [SPI Interface](spi-interface.md) for details.

### Adding New Features

**To add a new PHP function**:

1. Define in `plphp_spi.c`:
   ```c
   ZEND_FUNCTION(my_new_func) {
       // Implementation
   }
   ```

2. Declare in `plphp_spi.h`:
   ```c
   ZEND_FUNCTION(my_new_func);
   ```

3. Register in `spi_functions[]` array:
   ```c
   zend_function_entry spi_functions[] = {
       // ... existing functions ...
       ZEND_FE(my_new_func, NULL)
       {NULL, NULL, NULL}
   };
   ```

See [SPI Interface](spi-interface.md) and [Architecture](architecture.md) for extension points.

### Running Tests

```bash
# Run all tests
make installcheck

# Run specific test
make installcheck REGRESS="base"

# Run multiple tests
make installcheck REGRESS="base trigger spi"

# View differences on failure
cat regression.diffs
```

See [Testing Framework](testing.md) for details.

## Key Concepts

### Function Caching

Compiled PHP functions are cached permanently (until backend exit) using:
- Cache key: `plphp_proc_<oid>` or `plphp_proc_<oid>_trigger`
- Invalidation: On function redefinition (detected via xmin/cmin)
- Storage: PHP associative array (`plphp_proc_array`)

See [Core Handler - Function Compilation](core-handler.md#plphp_compile_function) for details.

### Memory Management

PL/php must coordinate two memory systems:
- **PostgreSQL**: Memory contexts (palloc/pfree)
- **PHP**: Zend memory manager (emalloc/efree)

Critical patterns:
- Permanent data: Use `malloc()` (function descriptors)
- Per-call data: Use `palloc()` (converted values)
- Temporary work: Create/delete memory contexts

See [Architecture - Memory Management](architecture.md#memory-management) for details.

### Trigger Functions

Special handling for trigger execution:
- Receives `$_TD` array with trigger data
- Can modify rows (BEFORE triggers)
- Return values: NULL, "SKIP", or "MODIFY"

Structure of `$_TD`:
```php
[
    'name', 'relid', 'relname', 'schemaname',
    'event' => 'INSERT'|'UPDATE'|'DELETE',
    'when' => 'BEFORE'|'AFTER',
    'level' => 'ROW'|'STATEMENT',
    'new' => [...], 'old' => [...],
    'args' => [...], 'argc' => N
]
```

See [Core Handler - Trigger Handler](core-handler.md#plphp_trigger_handler) for details.

### Set-Returning Functions

Special execution model for returning multiple rows:
- PHP function calls `return_next()` repeatedly
- Rows accumulated in tuplestore
- Two modes: explicit row array or implicit variables

See [SPI Interface - return_next()](spi-interface.md#return_next) for details.

## Version Compatibility

### PostgreSQL Versions

Supported: PostgreSQL 8.1+

Version-specific code controlled by macros:
```c
#define PG_VERSION_81_COMPAT  // 8.1+
#define PG_VERSION_82_COMPAT  // 8.2+ (requires PG_MODULE_MAGIC)
#define PG_VERSION_83_COMPAT  // 8.3+ (different xmin/cmin access)
```

See [Core Handler - Version Compatibility](core-handler.md#version-compatibility-macros) for details.

### PHP Versions

Supported: PHP 5.x with embed SAPI

Requirements:
- **Embed SAPI**: Must be built with `--enable-embed`
- **Non-threadsafe**: ZTS must be disabled
- **Shared library**: libphp5.so must be available

See [Build System - PHP Requirements](build-system.md#php-requirements) for details.

## Debugging

### Enable Debug Build

```bash
./configure --enable-debug
make
sudo make install
```

### Enable Memory Reporting

In source code, uncomment:
```c
#define DEBUG_PLPHP_MEMORY
```

Rebuilds with memory usage logging at various points.

### Function Source Logging

Compiled function source logged at LOG level:
```
LOG:  complete_proc_source = function plphp_proc_12345($args, $argc){...}
```

Check PostgreSQL logs for function compilation details.

### Using GDB

```bash
# Start PostgreSQL under gdb
gdb /usr/lib/postgresql/bin/postgres
(gdb) run -D /var/lib/postgresql/data

# Set breakpoints
(gdb) break plphp_call_handler
(gdb) break spi_exec

# Trigger from client
psql -c "SELECT my_plphp_function()"
```

## Known Issues

### Major Limitations

1. **Memory leaks**: Function cache never freed (FIXME in plphp.c:265)
2. **Array detection**: Heuristic `tmp[0] == '{'` is fragile (plphp.c:1698)
3. **No prepared statements**: SQL injection risk
4. **Type loss**: All values arrive as strings in PHP
5. **Memory growth**: Long-running backends accumulate memory

See individual module documentation for details.

### Security Considerations

1. **SQL Injection**: No parameterized queries - validate all inputs
2. **Safe Mode**: Limited effectiveness for security isolation
3. **Privilege Escalation**: SECURITY DEFINER functions run with owner privileges

See [SPI Interface - Security](spi-interface.md#security-considerations) for details.

## Contributing

### Testing Changes

```bash
# Make changes to source
vim plphp.c

# Rebuild
make clean
make
sudo make install

# Run tests
make installcheck

# Check for failures
cat regression.diffs
```

### Adding Tests

1. Create SQL test in `sql/mytest.sql`
2. Run and capture output: `psql -f sql/mytest.sql > expected/mytest.out`
3. Add to `Makefile.in`: `REGRESS = ... mytest`
4. Verify: `make installcheck REGRESS="mytest"`

See [Testing Framework](testing.md) for details.

### Documentation

When adding features, update relevant documentation:
- API changes → [API Reference](api-reference.md)
- Core changes → [Core Handler](core-handler.md) or [Architecture](architecture.md)
- Type system → [Type Conversion](type-conversion.md)
- SPI functions → [SPI Interface](spi-interface.md)

## Additional Resources

### External Documentation

- PostgreSQL SPI: https://www.postgresql.org/docs/current/spi.html
- PHP Embed SAPI: https://www.php.net/manual/en/install.php.embed.php
- PGXS: https://www.postgresql.org/docs/current/extend-pgxs.html

### Source Code Organization

```
PL-php/
├── plphp.c           - Core language handler
├── plphp_io.c/h      - Type conversion
├── plphp_spi.c/h     - SPI interface
├── configure.in      - Autoconf configuration
├── Makefile.in       - Build configuration
├── config.h.in       - Config header template
├── sql/              - Test SQL scripts
├── expected/         - Expected test outputs
└── docs/             - This documentation
```

### Getting Help

- GitHub Issues: https://public.commandprompt.com/projects/plphp
- Mailing List: plphp@lists.commandprompt.com

## Document Index

1. **[Architecture Overview](architecture.md)** - System design and component interaction
2. **[Core Handler](core-handler.md)** - plphp.c deep dive
3. **[Type Conversion](type-conversion.md)** - plphp_io.c/h deep dive
4. **[SPI Interface](spi-interface.md)** - plphp_spi.c/h deep dive
5. **[Build System](build-system.md)** - Building and configuration
6. **[Testing Framework](testing.md)** - Test suite and procedures
7. **[API Reference](api-reference.md)** - PHP API documentation

---

**Last Updated**: 2025-01-09
**PL/php Version**: 1.4dev
**Documentation Version**: 1.0
