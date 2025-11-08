# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PL/php is a procedural language extension for PostgreSQL that allows creating stored procedures, triggers, and set-returning functions using PHP. It embeds the PHP interpreter within PostgreSQL, enabling PHP code to be stored in the database and executed as stored procedures.

## Build System

PL/php uses GNU autoconf/configure with PostgreSQL's PGXS extension build system.

### Building from Source

1. **Generate configure script** (if building from git/SVN):
   ```bash
   autoconf
   ```

2. **Configure the build**:
   ```bash
   ./configure
   ```

   If PostgreSQL or PHP are not found automatically:
   ```bash
   ./configure --with-postgres=/path/to/pg --with-php=/path/to/php
   ```

   For debug builds:
   ```bash
   ./configure --enable-debug
   ```

3. **Build and install**:
   ```bash
   make
   make install
   ```

   Note: GNU make is required (use `gmake` on BSD systems).

### Prerequisites

- **PostgreSQL**: 8.1 or newer
- **PHP**: 5.x with embed SAPI (`--enable-embed`)
- **PHP must be non-threadsafe** (ZTS disabled)
- The configure script validates these requirements

## Testing

### Running All Tests

```bash
make installcheck
```

This runs the PostgreSQL regression test suite against a live database.

### Test Configuration

- Test SQL files: `sql/*.sql`
- Expected output: `expected/*.out`
- Some tests have multiple expected outputs (e.g., `base.out`, `base_2.out`) for different PostgreSQL versions
- Tests are run in this order: `base shared trigger spi raise cargs pseudo srf validator`
- Environment variable `PL_TESTDB` can specify the test database name

### Running Individual Tests

```bash
make installcheck REGRESS="base"
```

Replace "base" with any test name from the REGRESS list.

## Code Architecture

The codebase is organized into three main C modules:

### plphp.c - Core Language Handler

The main entry point and procedural language handler. Responsibilities:

- Initializing the embedded PHP interpreter
- Function call handler (`plphp_call_handler`) - invoked when a PL/php function is called
- Trigger handler (`plphp_trigger_handler`) - processes trigger events
- Function validation (`plphp_validator`) - validates function syntax
- Managing PostgreSQL/PHP interoperation and type conversion
- Handling function compilation and caching
- Managing memory contexts between PostgreSQL and PHP

### plphp_io.c/h - Type Conversion Layer

Handles bidirectional conversion between PostgreSQL and PHP data types:

- `plphp_zval_from_tuple()` - Convert PostgreSQL tuple to PHP zval
- `plphp_htup_from_zval()` - Convert PHP zval to PostgreSQL HeapTuple
- `plphp_convert_to_pg_array()` - Convert PHP arrays to PostgreSQL array format
- `plphp_convert_from_pg_array()` - Convert PostgreSQL arrays to PHP arrays
- `plphp_zval_get_cstring()` - Extract C string from PHP zval
- `plphp_build_tuple_argument()` - Build function arguments from tuples
- `plphp_modify_tuple()` - Modify tuples in trigger context

### plphp_spi.c/h - Server Programming Interface

Provides PHP functions for executing SQL from within PL/php procedures:

- `spi_exec()` - Execute SQL queries from PHP code
- `spi_fetch_row()` - Fetch next row from query result
- `spi_processed()` - Get number of rows processed
- `spi_status()` - Get query execution status
- `spi_rewind()` - Reset result set cursor
- `pg_raise()` - Raise PostgreSQL errors/notices from PHP
- `return_next()` - Return rows in set-returning functions (SRF)

The SPI layer uses PHP's resource type system (`php_SPIresult`) to manage query results.

## Key Technical Details

### PostgreSQL Version Compatibility

The code uses catalog version checks to support different PostgreSQL versions:

- `PG_VERSION_81_COMPAT` - PostgreSQL 8.1+
- `PG_VERSION_82_COMPAT` - PostgreSQL 8.2+ (requires `PG_MODULE_MAGIC`)
- `PG_VERSION_83_COMPAT` - PostgreSQL 8.3+

### Header Inclusion Order

Critical: PostgreSQL headers must be included before PHP headers. The code undefines conflicting macros (`PACKAGE_*`) between the two to avoid compilation warnings.

### Memory Management

PL/php must carefully manage memory between two systems:

- PostgreSQL's memory context system
- PHP's Zend memory manager

The `saved_symbol_table` in SPI layer preserves PHP's global state across function calls.

### Set-Returning Functions (SRF)

SRF support uses PostgreSQL's `FunctionCallInfo` and `Tuplestorestate` mechanisms. Global variables in `plphp_spi.h` track SRF execution state across PHP calls.
