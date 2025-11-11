# PL/php - PHP Procedural Language for PostgreSQL

PL/php is a procedural language extension for PostgreSQL that allows you to write stored procedures, triggers, and functions in PHP. By embedding the PHP interpreter within PostgreSQL, you can leverage PHP's extensive library ecosystem and familiar syntax to implement complex database logic.

## Features

- **Write stored procedures in PHP** - Use PHP syntax and functions within PostgreSQL
- **Trigger support** - Implement BEFORE and AFTER triggers for INSERT, UPDATE, and DELETE operations
- **Set-returning functions** - Return multiple rows from a single function call
- **SPI integration** - Execute SQL queries from within PHP code using the Server Programming Interface
- **Type conversion** - Automatic marshaling between PostgreSQL and PHP data types
- **IN/OUT/INOUT parameters** - Support for various parameter modes including named parameters

## Quick Start

### Prerequisites

- **PostgreSQL** 8.1 or newer
- **PHP** 5.x built with:
  - Embed SAPI (`--enable-embed`)
  - Non-threadsafe (ZTS disabled)
- **GNU autoconf** (for building from source)
- **GNU make** or `gmake` on BSD systems

### Installation

```bash
# 1. Generate configure script (if building from git)
autoconf

# 2. Configure
./configure

# 3. Build and install
make
sudo make install

# 4. Run tests (optional but recommended)
make installcheck
```

### Custom Installation Paths

If PostgreSQL or PHP are not in standard locations:

```bash
./configure \
  --with-postgres=/path/to/postgresql \
  --with-php=/path/to/php

make
sudo make install
```

### Enable PL/php in Your Database

```sql
-- PostgreSQL 8.2+
CREATE LANGUAGE plphp;

-- Or use the installation script
\i /path/to/install82.sql
```

## Usage Examples

### Simple Function

```sql
CREATE FUNCTION hello_world() RETURNS text AS $$
    return "Hello from PHP!";
$$ LANGUAGE plphp;

SELECT hello_world();
-- Returns: "Hello from PHP!"
```

### Function with Arguments

```sql
CREATE FUNCTION add_numbers(int, int) RETURNS int AS $$
    return (int)$args[0] + (int)$args[1];
$$ LANGUAGE plphp;

SELECT add_numbers(5, 7);
-- Returns: 12
```

### Named Parameters

```sql
CREATE FUNCTION greet(name text, age int) RETURNS text AS $$
    return "Hello $name, you are $age years old!";
$$ LANGUAGE plphp;

SELECT greet('Alice', 30);
-- Returns: "Hello Alice, you are 30 years old!"
```

### Executing SQL Queries

```sql
CREATE FUNCTION count_users() RETURNS int AS $$
    $result = spi_exec("SELECT COUNT(*) AS total FROM users");
    $row = spi_fetch_row($result);
    return (int)$row['total'];
$$ LANGUAGE plphp;

SELECT count_users();
```

### Trigger Function

```sql
CREATE TABLE audit_log (
    action text,
    table_name text,
    changed_at timestamp
);

CREATE FUNCTION log_changes() RETURNS trigger AS $$
    $action = $_TD['event'];
    $table = $_TD['relname'];

    spi_exec("INSERT INTO audit_log VALUES (
        '$action',
        '$table',
        NOW()
    )");

    return NULL;  -- For AFTER triggers
$$ LANGUAGE plphp;

CREATE TRIGGER users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE PROCEDURE log_changes();
```

### Set-Returning Function

```sql
CREATE FUNCTION generate_series_php(start int, stop int)
RETURNS SETOF int AS $$
    for ($i = $args[0]; $i <= $args[1]; $i++) {
        return_next([$i]);
    }
$$ LANGUAGE plphp;

SELECT * FROM generate_series_php(1, 10);
-- Returns rows: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
```

## Available PHP Functions

PL/php provides these built-in functions for database interaction:

| Function | Description |
|----------|-------------|
| `spi_exec($query, $limit)` | Execute SQL query and return result resource |
| `spi_fetch_row($result)` | Fetch next row as associative array |
| `spi_processed($result)` | Get number of rows processed |
| `spi_status($result)` | Get query execution status |
| `spi_rewind($result)` | Reset result cursor to beginning |
| `pg_raise($level, $message)` | Raise PostgreSQL notice/warning/error |
| `return_next($row)` | Return next row in set-returning function |

See the [API Reference](docs/api-reference.md) for complete documentation.

## Special Variables

### Function Arguments

- `$args` - Array of function arguments
- `$argc` - Count of arguments
- Named parameters available as variables (e.g., `$name`, `$age`)

### Trigger Data

- `$_TD` - Array containing trigger information:
  - `$_TD['event']` - INSERT, UPDATE, or DELETE
  - `$_TD['when']` - BEFORE or AFTER
  - `$_TD['level']` - ROW or STATEMENT
  - `$_TD['new']` - New row data (INSERT/UPDATE)
  - `$_TD['old']` - Old row data (UPDATE/DELETE)
  - `$_TD['relname']` - Table name
  - And more...

## Building PHP with Embed SAPI

PL/php requires PHP built with the embed SAPI. Here's how to build it:

```bash
# Download PHP
wget https://www.php.net/distributions/php-5.6.40.tar.gz
tar xzf php-5.6.40.tar.gz
cd php-5.6.40

# Configure with embed SAPI (critical!)
./configure \
    --enable-embed \
    --prefix=/usr/local/php \
    --disable-cli \
    --disable-cgi

# Build and install
make
sudo make install
```

**Important**: PHP must be **non-threadsafe** (no `--enable-maintainer-zts`).

### Verify Embed SAPI

```bash
php-config --php-sapis | grep embed
# Should output: embed
```

## Development Setup

### Debug Build

```bash
./configure --enable-debug
make
sudo make install
```

### Running Tests

```bash
# Run all tests
make installcheck

# Run specific test
make installcheck REGRESS="base"

# View test failures
cat regression.diffs
```

### Test Files

- SQL scripts: `sql/*.sql`
- Expected output: `expected/*.out`
- Actual output: `results/*.out`

## Documentation

Comprehensive documentation is available in the [`docs/`](docs/) directory:

- **[Architecture Overview](docs/architecture.md)** - System design and component interaction
- **[Core Handler](docs/core-handler.md)** - Language handler internals (plphp.c)
- **[Type Conversion](docs/type-conversion.md)** - Data marshaling between PostgreSQL and PHP
- **[SPI Interface](docs/spi-interface.md)** - SQL execution from PHP code
- **[Build System](docs/build-system.md)** - Detailed build and configuration guide
- **[Testing Framework](docs/testing.md)** - Test suite and procedures
- **[API Reference](docs/api-reference.md)** - Complete PHP API documentation

## Architecture

PL/php consists of three main C modules:

```
plphp.c       - Core language handler
├─ Function compilation and caching
├─ Trigger handling
├─ Set-returning function support
└─ PHP interpreter initialization

plphp_io.c    - Type conversion layer
├─ PostgreSQL → PHP data conversion
├─ PHP → PostgreSQL data conversion
└─ Array and tuple handling

plphp_spi.c   - SPI interface
├─ SQL query execution (spi_exec)
├─ Result iteration (spi_fetch_row)
└─ Error handling (pg_raise)
```

See [Architecture Overview](docs/architecture.md) for detailed information.

## Configuration Options

```bash
./configure [OPTIONS]

Options:
  --with-postgres=DIR   Specify PostgreSQL installation path
  --with-php=DIR        Specify PHP installation path
  --enable-debug        Build with debug symbols
```

## Platform Support

| Platform | Make Command | Notes |
|----------|--------------|-------|
| Linux | `make` | Standard GNU make |
| FreeBSD | `gmake` | Use GNU make |
| OpenBSD | `gmake` | Use GNU make |
| macOS | `make` | May need to install autoconf via Homebrew |

## Troubleshooting

### Configure Fails to Find PostgreSQL

```bash
# Solution 1: Specify path
./configure --with-postgres=/usr/local/pgsql

# Solution 2: Add to PATH
export PATH=/usr/local/pgsql/bin:$PATH
./configure
```

### Configure Fails to Find PHP

```bash
# Solution: Specify path
./configure --with-php=/usr/local/php
```

### PHP Thread-Safety Error

```
configure: error: PL/php requires non thread-safe PHP build
```

**Solution**: Rebuild PHP without ZTS:
```bash
./configure --enable-embed [--other-options without --enable-maintainer-zts]
```

### Missing Embed SAPI

```
configure: error: PL/php requires the Embed PHP SAPI
```

**Solution**: Rebuild PHP with `--enable-embed`:
```bash
./configure --enable-embed --prefix=/usr/local
```

### Tests Fail

```bash
# View differences
cat regression.diffs

# Run individual test with verbose output
psql -d pl_regression -f sql/base.sql
```

## Performance Considerations

- **Function Caching**: Compiled functions are cached permanently in backend memory
- **Type Conversion**: All PostgreSQL values arrive in PHP as strings - explicit casting recommended
- **Memory**: Long-running backends may accumulate memory - consider periodic backend recycling
- **Subtransactions**: Each `spi_exec()` uses a subtransaction - batch operations when possible

## Known Limitations

1. **No prepared statements** - Must construct SQL strings manually (SQL injection risk)
2. **No cursor support** - All query results loaded into memory
3. **String types** - All PostgreSQL values arrive as PHP strings
4. **Memory growth** - Function cache never freed until backend exit
5. **Thread safety** - PHP must be built non-threadsafe

See [Architecture Overview - Known Limitations](docs/architecture.md#known-limitations) for details.

## Security Considerations

### SQL Injection

PL/php does not support prepared statements. Always validate input:

```php
// UNSAFE - vulnerable to SQL injection
$name = $args[0];
$result = spi_exec("SELECT * FROM users WHERE name = '$name'");

// Better - validate input
if (!preg_match('/^[a-zA-Z0-9_]+$/', $args[0])) {
    pg_raise('ERROR', 'Invalid input');
}
$result = spi_exec("SELECT * FROM users WHERE name = '{$args[0]}'");
```

### Privilege Escalation

Functions created with `SECURITY DEFINER` run with owner privileges. Use carefully:

```sql
-- Runs with owner privileges
CREATE FUNCTION sensitive_operation() RETURNS void
SECURITY DEFINER AS $$
    -- Validate caller has appropriate permissions
    $result = spi_exec("SELECT current_user");
    $row = spi_fetch_row($result);
    if ($row['current_user'] != 'trusted_user') {
        pg_raise('ERROR', 'Permission denied');
    }
    -- Perform operation
$$ LANGUAGE plphp;
```

## Contributing

### Running Tests

```bash
make installcheck
```

### Adding Tests

1. Create SQL file in `sql/mytest.sql`
2. Run and capture output: `psql -f sql/mytest.sql > expected/mytest.out`
3. Add to `Makefile.in`: `REGRESS = ... mytest`
4. Verify: `make installcheck REGRESS="mytest"`

### Code Style

Follow the existing code style in the codebase. Key points:
- 4-space indentation (tabs for Makefiles)
- Function names: `plphp_*` prefix
- Comment complex logic
- Use PostgreSQL's memory management (`palloc`/`pfree`)

## Version History

See [HISTORY](HISTORY) for changelog.

**Current Version**: 1.4dev

**Major Milestones**:
- 1.4 (2010): PostgreSQL 8.4, 9.0 and PHP 5.3 support
- 1.3.5 (2007): Named parameters, PostgreSQL 8.3 support
- 1.3.2 (2007): Switch to PHP Embed SAPI

## License

PL/php is distributed under a permissive license. See source files for details.

Copyright (c) Command Prompt Inc.

## Support

- **Issue Tracker**: https://public.commandprompt.com/projects/plphp
- **Mailing List**: plphp@lists.commandprompt.com
- **Documentation**: [docs/](docs/)

## Related Projects

- **PL/Perl**: Perl procedural language for PostgreSQL
- **PL/Python**: Python procedural language for PostgreSQL
- **PL/pgSQL**: PostgreSQL's built-in procedural language

## Links

- PostgreSQL: https://www.postgresql.org/
- PHP: https://www.php.net/
- PGXS Documentation: https://www.postgresql.org/docs/current/extend-pgxs.html
- SPI Documentation: https://www.postgresql.org/docs/current/spi.html

---

**Quick Links**:
[Installation](#installation) |
[Usage Examples](#usage-examples) |
[Documentation](docs/) |
[API Reference](docs/api-reference.md) |
[Troubleshooting](#troubleshooting)
