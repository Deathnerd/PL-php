#!/bin/bash
set -eou pipefail
set -x

# Setup PHP with embed SAPI for PL/php development
# This script checks if PHP is already built in the cache volume,
# and if not, downloads and compiles PHP 5.6.40 with the required configuration.

PHP_VERSION="${PHP_VERSION:-5.6.40}"
PHP_PREFIX="/opt/php-build"
PHP_BUILD_LOG="/tmp/php-build.log"

echo "=================================================="
echo "PHP Setup for PL/php Development"
echo "=================================================="
echo "PHP Version: $PHP_VERSION"
echo "Install Prefix: $PHP_PREFIX"
echo ""

# Check if PHP is already built
if [ -f "$PHP_PREFIX/bin/php" ] && [ -f "$PHP_PREFIX/lib/libphp5.so" ]; then
    INSTALLED_VERSION=$($PHP_PREFIX/bin/php -v | head -1 | awk '{print $2}')
    echo "✓ PHP already built: $INSTALLED_VERSION"
    echo "✓ Location: $PHP_PREFIX"
    echo "✓ Embed SAPI library: $PHP_PREFIX/lib/libphp5.so"
    echo ""

    # Verify it's the correct version
    if [[ "$INSTALLED_VERSION" == "$PHP_VERSION"* ]]; then
        echo "✓ Version matches requested version ($PHP_VERSION)"
        exit 0
    else
        echo "⚠ Version mismatch! Installed: $INSTALLED_VERSION, Requested: $PHP_VERSION"
        echo "  Cleaning and rebuilding..."
        rm -rf "$PHP_PREFIX"/*
    fi
fi

# Check if incomplete build exists
if [ -d "$PHP_PREFIX" ] && [ ! -f "$PHP_PREFIX/lib/libphp5.so" ]; then
    echo "⚠ Incomplete PHP build detected, cleaning..."
    rm -rf "$PHP_PREFIX"/*
fi

echo "Building PHP $PHP_VERSION from source..."
echo "This will take approximately 15-20 minutes."
echo "Log file: $PHP_BUILD_LOG"
echo ""

# Build in the cache volume so partial builds are cached
BUILD_DIR="$PHP_PREFIX/build-${PHP_VERSION}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download source if not already present
if [ ! -f "php-${PHP_VERSION}.tar.gz" ]; then
    echo "[1/5] Downloading PHP $PHP_VERSION source..."
    wget -q --show-progress "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz"
else
    echo "[1/5] Using cached PHP $PHP_VERSION source..."
fi

# Extract if not already extracted
if [ ! -d "php-${PHP_VERSION}" ]; then
    echo "[2/5] Extracting source archive..."
    tar xzf "php-${PHP_VERSION}.tar.gz"
else
    echo "[2/5] Using extracted PHP $PHP_VERSION source..."
fi

cd "php-${PHP_VERSION}"

echo "[3/5] Configuring PHP build..."
echo "  - Embed SAPI: enabled"
echo "  - Thread Safety (ZTS): disabled"
echo "  - CLI/CGI: disabled"
echo ""

# Fix Debian multiarch paths for PHP's build system
# PHP 5.6 expects headers in /usr/include/curl but Debian uses /usr/include/x86_64-linux-gnu/curl
if [ -d /usr/include/x86_64-linux-gnu/curl ] && [ ! -e /usr/include/curl ]; then
    echo "  - Creating symlink for curl headers (Debian multiarch compatibility)"
    ln -s /usr/include/x86_64-linux-gnu/curl /usr/include/curl
fi

./configure \
    --prefix="$PHP_PREFIX" \
    --enable-embed \
    --disable-cli \
    --disable-cgi \
    --with-config-file-path="$PHP_PREFIX/etc" \
    --with-zlib \
    --with-curl \
    --with-readline \
    --enable-mbstring \
    --with-mysqli \
    --with-pdo-mysql \
    >> "$PHP_BUILD_LOG" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Configuration failed! Check log: $PHP_BUILD_LOG"
    tail -50 "$PHP_BUILD_LOG"
    exit 1
fi

echo "[4/5] Compiling PHP (this takes ~15 minutes)..."
echo "  Progress will be logged to: $PHP_BUILD_LOG"
echo "  You can monitor with: tail -f $PHP_BUILD_LOG"
echo ""

make -j$(nproc) >> "$PHP_BUILD_LOG" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed! Check log: $PHP_BUILD_LOG"
    tail -50 "$PHP_BUILD_LOG"
    exit 1
fi

echo "[5/5] Installing PHP to $PHP_PREFIX..."
make install >> "$PHP_BUILD_LOG" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Installation failed! Check log: $PHP_BUILD_LOG"
    tail -50 "$PHP_BUILD_LOG"
    exit 1
fi

# Cleanup build directory
cd /
rm -rf "$BUILD_DIR"

# Verify installation
echo ""
echo "=================================================="
echo "PHP Build Complete!"
echo "=================================================="
echo ""

if [ -f "$PHP_PREFIX/bin/php" ]; then
    echo "✓ PHP binary: $PHP_PREFIX/bin/php"
    $PHP_PREFIX/bin/php -v | head -1
else
    echo "❌ PHP binary not found!"
    exit 1
fi

if [ -f "$PHP_PREFIX/lib/libphp5.so" ]; then
    echo "✓ Embed SAPI library: $PHP_PREFIX/lib/libphp5.so"
    ls -lh "$PHP_PREFIX/lib/libphp5.so"
else
    echo "❌ Embed SAPI library not found!"
    exit 1
fi

echo ""
echo "✓ PHP setup complete and cached in volume"
echo "  Future container rebuilds will reuse this installation"
echo ""
