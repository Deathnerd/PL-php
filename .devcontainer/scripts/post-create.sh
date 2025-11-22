#!/bin/bash
set -euo pipefail
set -x

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=================================================="
echo "PL/php Development Container Initialization"
echo "=================================================="
echo ""
echo "Workspace: $WORKSPACE_ROOT"
echo ""

# Step 1: Build/verify PHP installation
echo "Step 1: PHP Setup"
echo "----------------"
bash "$SCRIPT_DIR/setup-php.sh"
echo ""

# Step 2: Initialize PostgreSQL
echo "Step 2: PostgreSQL Initialization"
echo "----------------"

if [ ! -d /var/lib/postgresql/data/base ]; then
    echo "Initializing PostgreSQL data directory..."
    su postgres -c "initdb -D /var/lib/postgresql/data"
    echo "✓ PostgreSQL data directory initialized"
else
    echo "✓ PostgreSQL data directory already exists"
fi
echo ""

# Step 3: Start PostgreSQL
echo "Step 3: Starting PostgreSQL"
echo "----------------"

# Kill any stale postgres processes
if lsof -i:5432 > /dev/null 2>&1; then
    echo "⚠ Port 5432 in use, killing stale processes..."
    pkill -9 postgres || true
    sleep 2
fi

# Fix permissions
chown -R postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

# Start PostgreSQL
echo "Starting PostgreSQL server..."
su postgres -c "pg_ctl -D /var/lib/postgresql/data -l /tmp/postgres.log start"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if pg_isready > /dev/null 2>&1; then
        echo "✓ PostgreSQL is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ PostgreSQL failed to start"
        echo "Log output:"
        cat /tmp/postgres.log
        exit 1
    fi
    sleep 1
done
echo ""

# Step 4: Create test database
echo "Step 4: Database Setup"
echo "----------------"

if su postgres -c "psql -lqt" | cut -d \| -f 1 | grep -qw pl_regression; then
    echo "✓ Test database 'pl_regression' already exists"
else
    echo "Creating test database 'pl_regression'..."
    su postgres -c "createdb pl_regression"
    echo "✓ Test database created"
fi
echo ""

# Step 5: Generate configure script
echo "Step 5: Workspace Setup"
echo "----------------"

cd "$WORKSPACE_ROOT"

if [ -f configure.in ] && [ ! -f configure ]; then
    echo "Generating configure script..."
    autoconf
    echo "✓ Configure script generated"
elif [ -f configure ]; then
    echo "✓ Configure script already exists"
else
    echo "⚠ No configure.in found - skipping autoconf"
fi
echo ""

# Final status
echo "=================================================="
echo "Development Environment Ready!"
echo "=================================================="
echo ""
echo "Quick Start:"
echo "  1. Configure PL/php:"
echo "     ./configure --with-php=/opt/php-build"
echo ""
echo "  2. Build:"
echo "     make clean && make"
echo ""
echo "  3. Install:"
echo "     make install"
echo ""
echo "  4. Run tests:"
echo "     make installcheck"
echo ""
echo "PostgreSQL:"
echo "  - Status: Running"
echo "  - Port: 5432"
echo "  - Test DB: pl_regression"
echo "  - Commands: pgstart, pgstop, pgstatus, pgrestart"
echo ""
echo "PHP:"
echo "  - Version: $(
/opt/php-build/bin/php -v | head -1 | awk '{print $2}')"
echo "  - Location: /opt/php-build"
echo "  - Embed SAPI: Enabled"
echo ""
echo "Diagnostics:"
echo "  Run: bash .devcontainer/scripts/diagnose.sh"
echo ""
