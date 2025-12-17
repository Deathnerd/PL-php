#!/bin/bash

echo "=================================================="
echo "PL/php Development Environment Diagnostics"
echo "=================================================="
echo ""

# PHP Diagnostics
echo "PHP Configuration:"
echo "----------------"
if [ -f /opt/php-build/bin/php ]; then
    echo "✓ PHP Binary: /opt/php-build/bin/php"
    /opt/php-build/bin/php -v | head -1

    if [ -f /opt/php-build/lib/libphp5.so ]; then
        echo "✓ Embed SAPI: /opt/php-build/lib/libphp5.so"
        ls -lh /opt/php-build/lib/libphp5.so
    else
        echo "❌ Embed SAPI library not found!"
    fi

    echo ""
    echo "PHP Configuration:"
    /opt/php-build/bin/php-config --version
    /opt/php-build/bin/php-config --configure-options | tr ' ' '\n' | grep -E '(embed|zts)'
else
    echo "❌ PHP not found at /opt/php-build/bin/php"
    echo "   Run: bash .devcontainer/scripts/setup-php.sh"
fi
echo ""

# PostgreSQL Diagnostics
echo "PostgreSQL Configuration:"
echo "----------------"
if command -v psql &> /dev/null; then
    echo "✓ PostgreSQL Client:"
    psql --version

    echo ""
    echo "✓ pg_config:"
    pg_config --version
    echo "  - Binary dir: $(pg_config --bindir)"
    echo "  - Library dir: $(pg_config --pkglibdir)"
    echo "  - Include dir: $(pg_config --includedir-server)"
else
    echo "❌ PostgreSQL client not found"
fi
echo ""

# PostgreSQL Server Status
echo "PostgreSQL Server Status:"
echo "----------------"
if pg_isready > /dev/null 2>&1; then
    echo "✓ Server is running and accepting connections"
    su postgres -c "psql -c 'SELECT version()'" | head -3

    echo ""
    echo "Active Connections:"
    su postgres -c "psql -c 'SELECT count(*) as connections FROM pg_stat_activity'" | head -3

    echo ""
    echo "Databases:"
    su postgres -c "psql -lqt" | cut -d \| -f 1 | sed '/^$/d' | sed 's/^/  - /'
else
    echo "❌ PostgreSQL server is not running"
    echo "   Start with: pgstart"
    echo "   Check logs: cat /tmp/postgres.log"
fi
echo ""

# PL/php Extension
echo "PL/php Extension:"
echo "----------------"
PLPHP_SO="$(pg_config --pkglibdir)/plphp.so"
if [ -f "$PLPHP_SO" ]; then
    echo "✓ Extension installed: $PLPHP_SO"
    ls -lh "$PLPHP_SO"

    echo ""
    echo "Language Status:"
    if pg_isready > /dev/null 2>&1; then
        if su postgres -c "psql -d pl_regression -c '\dL'" 2>/dev/null | grep -q plphp; then
            echo "✓ PL/php language installed in pl_regression database"
        else
            echo "⚠ PL/php language not installed in pl_regression"
            echo "  Install with: psql -d pl_regression -c 'CREATE LANGUAGE plphp'"
        fi
    fi
else
    echo "❌ Extension not installed: $PLPHP_SO"
    echo "   Build and install with:"
    echo "     ./configure --with-php=/opt/php-build"
    echo "     make clean && make"
    echo "     make install"
fi
echo ""

# Build Configuration
echo "Build Configuration:"
echo "----------------"
if [ -f /workspace/configure ]; then
    echo "✓ Configure script exists"
else
    echo "⚠ Configure script not found"
    if [ -f /workspace/configure.in ]; then
        echo "  Generate with: autoconf"
    fi
fi

if [ -f /workspace/Makefile ]; then
    echo "✓ Makefile exists (project configured)"
else
    echo "⚠ Makefile not found (project not configured)"
    echo "  Run: ./configure --with-php=/opt/php-build"
fi
echo ""

# Test Database
echo "Test Database:"
echo "----------------"
if pg_isready > /dev/null 2>&1; then
    if su postgres -c "psql -lqt" | cut -d \| -f 1 | grep -qw pl_regression; then
        echo "✓ Test database 'pl_regression' exists"

        echo ""
        echo "Database Size:"
        su postgres -c "psql -d pl_regression -c 'SELECT pg_size_pretty(pg_database_size(current_database()))'" | head -3
    else
        echo "❌ Test database 'pl_regression' not found"
        echo "   Create with: createdb pl_regression"
    fi
fi
echo ""

# Recent Test Results
echo "Recent Test Results:"
echo "----------------"
if [ -f /workspace/regression.diffs ]; then
    DIFF_SIZE=$(wc -l < /workspace/regression.diffs)
    if [ "$DIFF_SIZE" -eq 0 ]; then
        echo "✓ Last test run: PASSED (no diffs)"
    else
        echo "❌ Last test run: FAILED ($DIFF_SIZE lines of diffs)"
        echo "   View: cat regression.diffs"
    fi
else
    echo "⚠ No test results found"
    echo "  Run tests with: make installcheck"
fi
echo ""

# System Resources
echo "System Resources:"
echo "----------------"
echo "CPU Cores: $(nproc)"
echo "Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Disk Space: $(df -h /workspace | awk 'NR==2 {print $4 " available"}')"
echo ""

# Log Files
echo "Log Files:"
echo "----------------"
echo "PostgreSQL: /tmp/postgres.log"
if [ -f /tmp/postgres.log ]; then
    LINES=$(wc -l < /tmp/postgres.log)
    echo "  ($LINES lines)"
fi

echo "PHP Build: /tmp/php-build.log"
if [ -f /tmp/php-build.log ]; then
    LINES=$(wc -l < /tmp/php-build.log)
    echo "  ($LINES lines)"
fi
echo ""

echo "=================================================="
echo "Diagnostics Complete"
echo "=================================================="
