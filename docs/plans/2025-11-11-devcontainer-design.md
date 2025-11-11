# Devcontainer Design for PL/php Development

**Date:** 2025-11-11
**Status:** Approved
**Goal:** Provide a devcontainer for C development of PL/php with full debugging support

## Overview

This design creates a VSCode devcontainer for PL/php development that prioritizes:
1. **Baseline verification** - Build existing codebase and pass tests with legacy versions
2. **Debugging capability** - Full gdb integration for C code debugging
3. **Migration readiness** - Built-in mechanisms for upgrading PostgreSQL/PHP versions later

## Architecture

### Single Container Approach

The devcontainer runs all services in one container to enable direct debugging with gdb:

**Development Container (Debian 10 Buster):**
- Build tools: gcc, make, autoconf, gdb, valgrind
- PostgreSQL 9.6 server + development headers
- PHP 5.6 with embed SAPI (cached in volume)
- VSCode C/C++ extensions for IntelliSense
- Source code via workspace mount

**Named Volumes:**
- `php-build-cache`: Persists compiled PHP 5.6 installation across rebuilds
- `postgres-data`: Persists PostgreSQL databases across rebuilds

**Rationale for Single Container:**

We initially considered separate containers for PostgreSQL service versus development tools (better separation of concerns), but debugging requirements require running everything in one container. Docker container isolation prevents gdb in one container from attaching to PostgreSQL backend processes in another container. Since active C development requires frequent debugging, we prioritized debugging ease over architectural purity.

## Target Versions

### Phase 1: Baseline (Initial Implementation)

- **PostgreSQL:** 9.6
- **PHP:** 5.6.40
- **Goal:** Verify current codebase compiles and all tests pass

### Phase 2: Migration (Future)

- **PostgreSQL:** 15+
- **PHP:** 8.2+
- **Mechanism:** Change environment variables in `.env` file, rebuild containers

The design includes migration mechanisms from the start, but defers migration until we establish baseline.

## File Structure

```
.devcontainer/
├── devcontainer.json          # Main VSCode configuration
├── Dockerfile                 # Dev container image
├── scripts/
│   ├── setup-php.sh          # PHP build script (checks cache, builds if needed)
│   ├── post-create.sh        # Post-creation setup
│   └── diagnose.sh           # Diagnostic helper
└── .env.example              # Environment variables template

.vscode/
├── c_cpp_properties.json     # IntelliSense configuration
├── tasks.json                # Build tasks
├── launch.json               # Debugging configuration
└── extensions.json           # Recommended extensions
```

## Build Process

### Initial Setup (First Time)

When you open the project in VSCode:

1. **Container starts** - Debian 10 base with all dev tools installed
2. **postCreateCommand runs** (`post-create.sh`):
   - Checks if `/opt/php-build/bin/php` exists
   - If not: Downloads PHP 5.6.40 source → configures with `--enable-embed --disable-zts` → compiles (~15 min) → installs to `/opt/php-build`
   - If found: Skips build (cached from previous run)
3. **PostgreSQL initialization**:
   - Checks if `/var/lib/postgresql/data/base` exists
   - If not: Runs `initdb -D /var/lib/postgresql/data`
   - If found: Skips initialization (existing database)
4. **Start PostgreSQL** - `pg_ctl start` as background service
5. **Generate configure script** - Runs `autoconf` in workspace

### Daily Development Cycle

```bash
# 1. Configure PL/php (first time or after configure.in changes)
./configure --with-php=/opt/php-build --with-postgres=/usr

# 2. Build PL/php (after C code changes)
make clean && make

# 3. Install into PostgreSQL
make install

# 4. Run tests
make installcheck

# 5. Debug failures
cat regression.diffs
```

### Container Rebuilds

When you rebuild the devcontainer (e.g., to add new tools):
- PHP build cache persists → rebuild becomes unnecessary
- PostgreSQL data persists → test databases remain intact
- Only the rebuild touches the dev container filesystem

## VSCode Integration

### IntelliSense Configuration

`.vscode/c_cpp_properties.json` configures include paths:

```json
{
  "includePath": [
    "${workspaceFolder}/**",
    "/usr/include/postgresql/9.6/server",
    "/opt/php-build/include/php",
    "/opt/php-build/include/php/main",
    "/opt/php-build/include/php/Zend",
    "/opt/php-build/include/php/TSRM"
  ],
  "defines": ["PG_VERSION_NUM=90600"],
  "compilerPath": "/usr/bin/gcc"
}
```

This configuration gives full autocomplete and navigation through PostgreSQL and PHP headers.

### Build Tasks

`.vscode/tasks.json` provides keyboard shortcuts:
- **Build PL/php** - `make clean && make` (Ctrl+Shift+B)
- **Install & Test** - `make install && make installcheck`
- **Run Single Test** - Prompts for test name, runs `make installcheck REGRESS="testname"`

### Debugging with GDB

The C/C++ extension supports attaching to PostgreSQL backend processes:

1. Set breakpoints in VSCode
2. Run a PL/php function that triggers your code
3. Attach GDB to the backend process (find PID with `ps aux | grep postgres`)
4. Step through C code with full source visibility

`.vscode/launch.json` includes sample attach configuration.

### Recommended Extensions

`.vscode/extensions.json`:
- C/C++ IntelliSense (ms-vscode.cpptools)
- PostgreSQL (ckolkman.vscode-postgres)
- GitLens (eamodio.gitlens)

## PostgreSQL Management

### Auto-start

PostgreSQL starts automatically via `postCreateCommand` when you open the container.

### Manual Control

Shell aliases for manual control:
```bash
alias pgstart='su postgres -c "pg_ctl -D /var/lib/postgresql/data start"'
alias pgstop='su postgres -c "pg_ctl -D /var/lib/postgresql/data stop"'
alias pgstatus='su postgres -c "pg_ctl -D /var/lib/postgresql/data status"'
```

### Database Access

```bash
# Connect to test database
psql pl_regression

# Create the language (if not already done)
CREATE LANGUAGE plphp;
```

## Error Handling & Diagnostics

### PHP Build Failures

`setup-php.sh` checks for dependencies before building:
- Verifies `build-essential`, `libxml2-dev`, `libssl-dev` exist
- Detects incomplete builds (missing `libphp5.so`)
- Cleans `/opt/php-build` and rebuilds from scratch on failure

### PostgreSQL Startup Issues

`post-create.sh` handles common problems:
- Kills stale postgres processes on port 5432
- Fixes data directory permissions (owner: postgres, mode: 700)
- Tails `/tmp/postgres.log` if startup fails

### Extension Installation Verification

After `make install`, verify `plphp.so` exists:
```bash
if [ ! -f "$(pg_config --pkglibdir)/plphp.so" ]; then
    echo "❌ plphp.so not found after install!"
    exit 1
fi
```

### Diagnostic Script

`diagnose.sh` provides environment overview:
```bash
=== PL/php Development Environment Diagnostics ===
PHP: 5.6.40
PostgreSQL: PostgreSQL 9.6.24
pg_config: PostgreSQL 9.6.24
plphp.so: -rwxr-xr-x 1 root root 123K /usr/lib/postgresql/9.6/lib/plphp.so
PostgreSQL status: pg_ctl: server is running (PID: 123)
Test database: pl_regression
```

### Log Locations

- PostgreSQL: `/tmp/postgres.log`
- PHP build: `/tmp/php-build.log`
- Test output: `regression.diffs`

## Migration Path

### Environment Variables

`.devcontainer/.env` defines versions:
```bash
POSTGRES_VERSION=9.6
PHP_VERSION=5.6.40
```

### Migration Process (Future)

When ready to upgrade:

1. **Update versions** - Edit `.env` to specify new PostgreSQL/PHP versions
2. **Rebuild container** - VSCode rebuilds with new versions
3. **Fix compatibility issues** - Address any build or test failures
4. **Verify tests** - Run `make installcheck` to validate changes
5. **Repeat** - Increment versions gradually (e.g., 9.6 → 12 → 15)

### Version-Aware Build Scripts

`setup-php.sh` supports multiple PHP versions:
- Installs to `/opt/php-build-${PHP_VERSION}`
- Detects version changes and rebuilds
- Preserves old versions for comparison

## Daily Workflow Reference

### Opening Project

1. Open folder in VSCode
2. Click "Reopen in Container"
3. Wait ~30 seconds (PostgreSQL auto-starts, PHP cached)
4. Start coding

### Standard Development Loop

```bash
# Configure (first time only)
./configure --with-php=/opt/php-build

# Edit C code → Build → Install → Test
make clean && make
make install
make installcheck
```

### Debugging

```bash
# Connect to database
psql pl_regression

# Run function that triggers your code
SELECT my_plphp_function();

# In VSCode: attach debugger to postgres backend PID
# Set breakpoints, step through C code
```

### Resetting State

```bash
# Reset test database
dropdb pl_regression
createdb pl_regression

# Restart PostgreSQL
pgstop && pgstart

# Complete reset (delete volumes via Docker Desktop, rebuild container)
```

## Success Criteria

**You achieve baseline when:**
1. Container opens without errors in ~30 seconds (after initial PHP build)
2. `./configure --with-php=/opt/php-build` succeeds
3. `make clean && make` compiles without errors
4. `make install` installs `plphp.so` successfully
5. `make installcheck` passes all tests
6. `regression.diffs` is empty
7. Breakpoints in C code work with gdb

**You validate migration readiness when:**
1. Changing `POSTGRES_VERSION` in `.env` rebuilds with new version
2. Changing `PHP_VERSION` in `.env` triggers PHP rebuild
3. Documentation exists for migration process

## Notes

- This design prioritizes debugging experience over container purity
- PostgreSQL development headers in dev container enable building extensions
- Volumes persist across rebuilds to avoid re-compiling PHP and re-initializing databases
- Migration mechanisms exist but remain dormant until you verify baseline
