# Devcontainer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a complete VSCode devcontainer for PL/php development with PostgreSQL 9.6, PHP 5.6, and full debugging support.

**Architecture:** Single-container approach running PostgreSQL server, PHP build environment, and all development tools. Uses volume caching for PHP builds and PostgreSQL data persistence.

**Tech Stack:**
- Debian 10 Buster
- PostgreSQL 9.6 + development headers
- PHP 5.6.40 with embed SAPI
- GDB, Valgrind for debugging
- VSCode C/C++ extension for IntelliSense

---

## Completed Implementation

All core devcontainer files have been created and are ready for testing:

### Directory Structure
```
.devcontainer/
├── devcontainer.json          ✓ Main VSCode configuration
├── Dockerfile                 ✓ Container image definition
├── .env.example               ✓ Environment variables template
└── scripts/
    ├── setup-php.sh          ✓ PHP 5.6 build script with caching
    ├── post-create.sh        ✓ Container initialization orchestrator
    └── diagnose.sh           ✓ Diagnostic and troubleshooting tool

.vscode/
├── c_cpp_properties.json     ✓ IntelliSense configuration
├── tasks.json                ✓ Build/test/debug tasks
├── launch.json               ✓ GDB debugging configuration
└── extensions.json           ✓ Recommended extensions

.gitignore                    ✓ Updated with devcontainer artifacts
```

### Implementation Details

**Dockerfile Features:**
- Based on Debian 10 (Buster) for compatibility
- PostgreSQL 9.6 server + postgresql-server-dev-9.6
- Build tools: gcc, make, autoconf, gdb, valgrind
- PHP build dependencies pre-installed
- PostgreSQL configured for local trust authentication
- Shell aliases for pg management (pgstart, pgstop, pgstatus)

**setup-php.sh Features:**
- Detects existing PHP builds in /opt/php-build volume
- Downloads PHP 5.6.40 source if needed
- Configures with --enable-embed --disable-zts (required for PL/php)
- Compiles with parallel make (uses all CPU cores)
- Verifies libphp5.so (embed SAPI library) exists
- Comprehensive error handling and logging

**post-create.sh Features:**
- Calls setup-php.sh (15-20 min first time, instant if cached)
- Initializes PostgreSQL data directory if needed
- Starts PostgreSQL server
- Creates pl_regression test database
- Runs autoconf to generate configure script
- Displays quick start instructions

**diagnose.sh Features:**
- Verifies PHP installation and embed SAPI
- Checks PostgreSQL server status
- Shows database list and connections
- Verifies plphp.so extension installation
- Displays build configuration status
- Shows recent test results
- Lists log file locations

**VSCode Integration:**
- IntelliSense includes PostgreSQL 9.6 and PHP 5.6 headers
- Build task (Ctrl+Shift+B) runs make clean && make
- Tasks for install, test, configure, diagnostics
- GDB attach configurations for debugging
- Recommended extensions: C/C++, PostgreSQL, GitLens

### Volume Mounts

**plphp-php-build-cache** → /opt/php-build
- Persists compiled PHP 5.6 installation
- Eliminates 15-20 minute rebuild on container recreation
- Version-aware (can support multiple PHP versions)

**plphp-postgres-data** → /var/lib/postgresql/data
- Persists PostgreSQL database files
- Preserves test databases across container rebuilds
- Maintains pl_regression database state

### Environment Variables

Defined in .env.example (copy to .env):
```bash
POSTGRES_VERSION=9.6
PHP_VERSION=5.6.40
POSTGRES_DB=pl_regression
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
```

## Testing & Verification Tasks

### Task 1: Initial Container Build

**Step 1: Copy environment template**
```bash
cd /projects/mine/PL-php/.worktrees/devcontainer
cp .devcontainer/.env.example .devcontainer/.env
```

**Step 2: Open in VSCode**
- Open /projects/mine/PL-php/.worktrees/devcontainer in VSCode
- Click "Reopen in Container" when prompted
- Wait for initial build (first time: ~20-25 minutes including PHP build)

**Expected Results:**
- Container builds successfully
- PHP 5.6.40 compiles without errors
- PostgreSQL initializes and starts
- post-create.sh completes with "Development Environment Ready!"

**Step 3: Verify initial state**
```bash
# Should be inside container now
bash .devcontainer/scripts/diagnose.sh
```

**Expected Output:**
- ✓ PHP 5.6.40 at /opt/php-build
- ✓ Embed SAPI library exists
- ✓ PostgreSQL 9.6 running
- ✓ Test database pl_regression exists
- ✓ Configure script generated

---

### Task 2: Build PL/php

**Step 1: Configure project**
```bash
./configure --with-php=/opt/php-build
```

**Expected Output:**
- checking for PostgreSQL version... 9.6
- checking for PHP embed SAPI... yes
- checking for PHP version... 5.6.40
- configure: creating ./config.status

**Step 2: Build extension**
```bash
make clean && make
```

**Expected Output:**
- Compilation succeeds without errors
- plphp.so created

**Step 3: Install extension**
```bash
make install
```

**Expected Output:**
- plphp.so installed to $(pg_config --pkglibdir)

**Step 4: Verify installation**
```bash
ls -lh $(pg_config --pkglibdir)/plphp.so
```

**Expected:** File exists and is ~100-150KB

---

### Task 3: Run Tests

**Step 1: Run all regression tests**
```bash
make installcheck
```

**Expected Output:**
- All tests pass
- regression.diffs is empty or doesn't exist

**Step 2: Check for failures**
```bash
if [ -f regression.diffs ]; then
    cat regression.diffs
else
    echo "All tests passed!"
fi
```

**Step 3: Run individual test**
```bash
make installcheck REGRESS="base"
```

**Expected:** base test passes

---

### Task 4: Verify Debugging

**Step 1: Create test function**
```bash
psql pl_regression << 'EOF'
CREATE LANGUAGE plphp;

CREATE FUNCTION debug_test(x int) RETURNS int AS $$
    return $x * 2;
$$ LANGUAGE plphp;
EOF
```

**Step 2: Set breakpoint in VSCode**
- Open plphp.c
- Set breakpoint in plphp_call_handler function (around line with "php_embed_init")

**Step 3: Run function in psql**
```bash
psql pl_regression -c "SELECT debug_test(5);"
```

**Step 4: Attach debugger**
- In VSCode: Run > Start Debugging > "Attach to PostgreSQL Backend"
- Select postgres backend process
- Debugger should hit breakpoint

**Expected:** Breakpoint hits, can step through C code

---

### Task 5: Verify Volume Persistence

**Step 1: Note current state**
```bash
/opt/php-build/bin/php -v
psql -l | grep pl_regression
```

**Step 2: Rebuild container**
- VSCode: Command Palette > "Dev Containers: Rebuild Container"
- Wait for rebuild (should be ~30 seconds, not 20 minutes)

**Step 3: Verify persistence**
```bash
# PHP should still be built
/opt/php-build/bin/php -v

# Database should still exist
psql -l | grep pl_regression
```

**Expected:** Both PHP and database persist, no rebuild needed

---

### Task 6: Verify VSCode Integration

**Step 1: Test IntelliSense**
- Open plphp.c
- Type `Datum` - should show autocomplete from PostgreSQL headers
- Ctrl+Click on `plphp_call_handler` - should navigate to definition

**Step 2: Test build task**
- Press Ctrl+Shift+B
- Should run "Build PL/php" task
- Compilation output shown in terminal

**Step 3: Test other tasks**
- View > Command Palette > "Tasks: Run Task"
- Try "Run All Tests"
- Try "Run Diagnostics"

**Expected:** All tasks execute correctly

---

## Success Criteria

✓ **Implementation Complete:**
- All files created and committed
- Directory structure matches design
- Scripts are executable
- Configuration files are valid JSON

**Testing Phase (Current):**
- [ ] Container builds successfully on first run
- [ ] PHP 5.6 compiles and caches correctly
- [ ] PostgreSQL starts and creates test database
- [ ] PL/php configures, builds, and installs
- [ ] All regression tests pass
- [ ] Breakpoints work with GDB
- [ ] Volumes persist across rebuilds
- [ ] IntelliSense works for C code
- [ ] Build tasks execute correctly

## Known Limitations

1. **First Build Time:** Initial container creation takes 20-25 minutes due to PHP compilation
   - Subsequent rebuilds: ~30 seconds (PHP cached)

2. **PostgreSQL Version:** Currently hardcoded to 9.6 in Dockerfile
   - Future: Make version configurable via .env

3. **PHP Version:** Currently hardcoded to 5.6.40 in scripts
   - Future: Support multiple versions via .env

4. **Container Size:** ~2GB after full build
   - Debian base + PostgreSQL + build tools + PHP sources

## Troubleshooting

**Container fails to build:**
- Check Docker daemon is running
- Check disk space (needs ~5GB free)
- View Docker build output for specific errors

**PHP build fails:**
- Check /tmp/php-build.log for details
- Verify internet connection (downloads from php.net)
- Try: `rm -rf /opt/php-build/* && bash .devcontainer/scripts/setup-php.sh`

**PostgreSQL won't start:**
- Check /tmp/postgres.log
- Verify port 5432 is not in use: `lsof -i:5432`
- Try: `pkill postgres && pgstart`

**Tests fail:**
- Run diagnostics: `bash .devcontainer/scripts/diagnose.sh`
- View diffs: `cat regression.diffs`
- Check plphp.so installed: `ls $(pg_config --pkglibdir)/plphp.so`

**Debugging doesn't work:**
- Verify GDB installed: `which gdb`
- Check process running: `ps aux | grep postgres`
- Try attaching to specific PID instead of picking from list

## Next Steps

After successful testing and verification:

1. **Merge to main branch:**
   ```bash
   git add .
   git commit -m "feat: add devcontainer for PL/php development"
   # Use finishing-a-development-branch skill
   ```

2. **Update README.md** with devcontainer usage instructions

3. **Test migration path:** Try upgrading to PostgreSQL 12 and PHP 7.4

4. **Document debugging workflow** with screenshots/examples

5. **Create video walkthrough** of setup and usage

## Migration Path (Future)

When ready to test modern versions:

1. Edit .devcontainer/.env:
   ```bash
   POSTGRES_VERSION=12
   PHP_VERSION=7.4.33
   ```

2. Rebuild container (will compile new PHP version)

3. Fix any compatibility issues in C code

4. Verify all tests still pass

5. Repeat for PostgreSQL 15 + PHP 8.2

## Files Reference

All files created in this implementation:

- `.devcontainer/devcontainer.json` - 52 lines
- `.devcontainer/Dockerfile` - 69 lines
- `.devcontainer/.env.example` - 15 lines
- `.devcontainer/scripts/setup-php.sh` - 134 lines
- `.devcontainer/scripts/post-create.sh` - 92 lines
- `.devcontainer/scripts/diagnose.sh` - 161 lines
- `.vscode/c_cpp_properties.json` - 32 lines
- `.vscode/tasks.json` - 134 lines
- `.vscode/launch.json` - 54 lines
- `.vscode/extensions.json` - 8 lines
- `.gitignore` - Updated, added 3 lines

**Total:** ~750 lines of configuration and scripting
