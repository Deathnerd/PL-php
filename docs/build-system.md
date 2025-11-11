# Build System and Configuration

## Overview

PL/php uses GNU autoconf for configuration and PostgreSQL's PGXS (PostgreSQL Extension Building Infrastructure) for building. This document explains the build system, configuration options, and installation process.

## Build System Components

### configure.in

**Location**: `configure.in` (110 lines)

Autoconf input file that generates the `configure` script.

**Key Checks**:
1. Common programs (CC, AWK, GREP)
2. Header files (fcntl.h, unistd.h)
3. Library functions (strcasecmp, strdup)
4. PostgreSQL installation (pg_config)
5. PHP installation (php-config)
6. PHP configuration (thread-safety, embed SAPI)
7. PHP 5 library availability

### Makefile.in

**Location**: `Makefile.in` (21 lines)

Template for the final Makefile.

**Structure**:
```makefile
MODULE_big = plphp
OBJS = plphp.o plphp_io.o plphp_spi.o
PG_CPPFLAGS = @CPPFLAGS@

SHLIB_LINK = @LDFLAGS@ @LIBS@

REGRESS_OPTS = --dbname=$(PL_TESTDB) --load-language=plphp
REGRESS = base shared trigger spi raise cargs pseudo srf validator

all: all-lib
install: install-lib

PG_CONFIG = @PG_CONFIG@
PGXS = @PGXS@
include $(PGXS)
```

**Variables**:
- `MODULE_big` - Shared library name (plphp.so)
- `OBJS` - Object files to link
- `PG_CPPFLAGS` - Compiler flags from configure
- `SHLIB_LINK` - Linker flags and libraries
- `REGRESS_OPTS` - Options for regression tests
- `REGRESS` - Test files to run
- `PG_CONFIG` - Path to pg_config
- `PGXS` - Path to PostgreSQL PGXS makefile

### config.h.in

**Location**: `config.h.in` (82 lines, generated)

Template for configuration header.

**Defines**:
```c
#define HAVE_FCNTL_H 1
#define HAVE_UNISTD_H 1
#define HAVE_STRCASECMP 1
#define HAVE_STRDUP 1
#define PG_MAJOR_VERSION 9
#define PG_MINOR_VERSION 5
```

## Build Prerequisites

### PostgreSQL Requirements

**Minimum Version**: PostgreSQL 8.1

**Detection** (`configure.in:36-46`):
```bash
AC_PATH_PROG([PG_CONFIG], [pg_config], [], [$PG_PATH:$PG_PATH/bin:$PATH])
```

**Validation** (`configure.in:56-64`):
```bash
if test $PG_MAJOR_VERSION -lt 8 ; then
    STOP="yes"
else
    if test "$PG_MAJOR_VERSION" = 8 -a "$PG_MINOR_VERSION" -lt 1 ; then
        STOP="yes"
    fi
fi
if test "$STOP" = "yes"; then
    AC_MSG_ERROR([PostgreSQL 8.1 or newer required])
fi
```

**Required Files**:
- `pg_config` - PostgreSQL configuration utility
- PGXS makefile (`pg_config --pgxs`)

### PHP Requirements

**Minimum Version**: PHP 5.x

**Required Features**:
1. **Embed SAPI** (`--enable-embed`)
2. **Non-threadsafe** (ZTS disabled)
3. **Shared libphp5.so**

**Detection** (`configure.in:70-73`):
```bash
AC_PATH_PROGS([PHP_CONFIG], [php-config], [],
              [$PHP_PATH:$PHP_PATH/bin:$PATH])
if test "$PHP_CONFIG" = ""; then
    AC_MSG_ERROR([Cannot locate php-config])
fi
```

**Thread-Safety Check** (`configure.in:82-86`):
```bash
AC_CHECK_DECL(ZTS, [zts_enabled="yes"], [zts_enabled="no"],
              [#include "php_config.h"])
if test "$zts_enabled" = "yes"; then
    AC_MSG_ERROR([PL/php requires non thread-safe PHP build.
Please rebuild your PHP library with thread-safe support disabled])
fi
```

**Embed SAPI Check** (`configure.in:88-99`):
```bash
$PHP_CONFIG --php-sapis | $GREP embed >/dev/null 2>&1
if test $? = 0; then
    embed_sapi_present=yes
else
    embed_sapi_present=no
fi
if test "$embed_sapi_present" = "no"; then
    AC_MSG_ERROR([PL/php requires the Embed PHP SAPI.
Please rebuild your PHP library with --enable-embed])
fi
```

**Library Check** (`configure.in:102-105`):
```bash
AC_CHECK_LIB([php5], [php_module_startup],[],
             [have_php5="no"], [$PHP_LDFLAGS])
if test "$have_php5" = "no"; then
    AC_MSG_ERROR([Cannot find PHP 5 SAPI library])
fi
```

## Building PHP with Embed SAPI

### Standard Build

```bash
# Download and extract PHP
tar xfj php-5.2.6.tar.bz2
cd php-5.2.6

# Configure with embed SAPI
./configure \
    --enable-embed \
    --prefix=/usr/local \
    [additional options]

# Build and install
make
make install
```

**Critical**: The `--enable-embed` option is required.

### Thread-Safety

PHP must be built **without** ZTS (Zend Thread Safety).

**Verify Non-Threadsafe**:
```bash
php-config --configure-options | grep -q zts && echo "ZTS enabled (bad)" || echo "ZTS disabled (good)"
```

### Library Location

Ensure PostgreSQL server can find libphp5.so:

**Option 1: System Library Path**
```bash
./configure --prefix=/usr/local
# Library installed to /usr/local/lib (usually in system path)
```

**Option 2: LD_LIBRARY_PATH**
```bash
export LD_LIBRARY_PATH=/custom/php/lib:$LD_LIBRARY_PATH
pg_ctl start
```

**Option 3: Add to ld.so.conf**
```bash
echo "/custom/php/lib" >> /etc/ld.so.conf
ldconfig
```

## Configuration Options

### Custom PostgreSQL Location

```bash
./configure --with-postgres=/path/to/postgresql
```

Looks for `pg_config` in:
- `/path/to/postgresql/pg_config`
- `/path/to/postgresql/bin/pg_config`

### Custom PHP Location

```bash
./configure --with-php=/path/to/php
```

Looks for `php-config` in:
- `/path/to/php/php-config`
- `/path/to/php/bin/php-config`

### Debug Build

```bash
./configure --enable-debug
```

Adds `-g` to CPPFLAGS for debugging symbols.

**Check** (`configure.in:28-34`):
```bash
AC_MSG_CHECKING([whether to build with debug information])
if test "$DEBUG" = "yes"; then
    CPPFLAGS+="-g";
    AC_MSG_RESULT([yes])
else
    AC_MSG_RESULT([no])
fi
```

### Combined Example

```bash
./configure \
    --with-postgres=/usr/local/pgsql \
    --with-php=/opt/php5 \
    --enable-debug
```

## Build Process

### Full Build Sequence

```bash
# 1. Generate configure script (if building from source control)
autoconf

# 2. Run configure
./configure [options]

# 3. Build shared library
make

# 4. Install (requires superuser)
sudo make install

# 5. Run regression tests (optional)
make installcheck
```

### Generated Files

**From autoconf**:
- `configure` - Configuration script

**From configure**:
- `config.h` - Configuration header
- `config.status` - Configuration state
- `config.log` - Configuration log
- `Makefile` - Build makefile

**From make**:
- `plphp.o`, `plphp_io.o`, `plphp_spi.o` - Object files
- `plphp.so` - Shared library

### Compilation Commands

**Typical compilation**:
```bash
gcc -Wall -Wmissing-prototypes -Wpointer-arith \
    -I/usr/include/php -I/usr/include/postgresql \
    -fPIC -c -o plphp.o plphp.c
```

**Linking**:
```bash
gcc -shared plphp.o plphp_io.o plphp_spi.o \
    -L/usr/lib/php -lphp5 \
    -o plphp.so
```

## Installation

### Standard Installation

```bash
make install
```

**Installs to**: `$(pg_config --pkglibdir)/plphp.so`

**Typical Path**: `/usr/lib/postgresql/9.5/lib/plphp.so`

### Custom Installation Location

PostgreSQL determines installation location via `pg_config --pkglibdir`.

**To install elsewhere**, modify `PG_CONFIG` in Makefile:
```bash
make PG_CONFIG=/custom/pgsql/bin/pg_config install
```

### Post-Installation

After installation, create the language in PostgreSQL:

**PostgreSQL 8.2+**:
```sql
CREATE LANGUAGE plphp;
```

Or use the installation script:
```bash
psql -d mydb -f install82.sql
```

**PostgreSQL 8.1**:
```sql
\i install.sql
```

## PGXS Integration

PL/php uses PostgreSQL Extension Building Infrastructure (PGXS).

**Included at** (`Makefile.in:20`):
```makefile
include $(PGXS)
```

**Provides**:
- `all-lib` - Build shared library
- `install-lib` - Install shared library
- `installcheck` - Run regression tests
- `clean` - Remove build artifacts
- `distclean` - Remove all generated files

**Standard Targets**:
```bash
make              # Build library
make install      # Install library
make installcheck # Run tests
make clean        # Clean build files
make distclean    # Clean all generated files
```

## Compiler and Linker Flags

### From PHP

**Retrieved via** `php-config`:

```bash
# Include paths
PHP_INCLUDES=$(php-config --includes)
# -I/usr/include/php -I/usr/include/php/main ...

# Linker flags
PHP_LDFLAGS=$(php-config --ldflags)
PHP_LIBS=$(php-config --libs)

# Library path
PHP_LIBDIR=$(php-config --prefix)/lib
```

**Set in configure.in** (lines 75-76):
```bash
LIBS="$LIBS $($PHP_CONFIG --libs)"
LDFLAGS="$LDFLAGS $($PHP_CONFIG --ldflags) -L$($PHP_CONFIG --prefix)/lib"
```

### From PostgreSQL

**Retrieved via** `pg_config`:

```bash
# Include path
PG_INCLUDEDIR=$(pg_config --includedir-server)

# PGXS provides compiler flags automatically
```

## Platform-Specific Notes

### GNU Make Requirement

**BSD Systems** (FreeBSD, OpenBSD, NetBSD):

```bash
# Use gmake instead of make
gmake
gmake install
gmake installcheck
```

**Note** (`INSTALL:28-30`):
> Note 2: you need GNU make to build PL/php. On systems where GNU make is not the
> default make program (e.g. FreeBSD) you can usually invoke the GNU version with
> gmake.

### Linux

Standard `make` is usually GNU make:
```bash
make
make install
```

### macOS

Install autoconf if building from source:
```bash
brew install autoconf
autoconf
./configure
make
make install
```

## Troubleshooting

### Configure Failures

**PostgreSQL not found**:
```
checking for pg_config... no
configure: error: Cannot locate pg_config
```

**Solution**:
```bash
./configure --with-postgres=/path/to/pgsql
# or
export PATH=/path/to/pgsql/bin:$PATH
./configure
```

**PHP not found**:
```
checking for php-config... no
configure: error: Cannot locate php-config
```

**Solution**:
```bash
./configure --with-php=/path/to/php
```

**Thread-safe PHP**:
```
configure: error: PL/php requires non thread-safe PHP build
```

**Solution**: Rebuild PHP without `--enable-maintainer-zts`:
```bash
./configure --enable-embed [other options without ZTS]
```

**Missing embed SAPI**:
```
configure: error: PL/php requires the Embed PHP SAPI
```

**Solution**: Rebuild PHP with `--enable-embed`:
```bash
./configure --enable-embed --prefix=/usr/local
```

### Build Failures

**Missing headers**:
```
plphp.c:48:10: fatal error: postgres.h: No such file or directory
```

**Solution**: Install PostgreSQL development packages:
```bash
# Debian/Ubuntu
apt-get install postgresql-server-dev-all

# Red Hat/CentOS
yum install postgresql-devel

# macOS
brew install postgresql
```

**Missing libphp5**:
```
/usr/bin/ld: cannot find -lphp5
```

**Solution**: Ensure PHP installed with embed SAPI:
```bash
ls -l $(php-config --prefix)/lib/libphp5.*
```

### Installation Failures

**Permission denied**:
```
/bin/install: cannot create regular file '...': Permission denied
```

**Solution**: Use sudo:
```bash
sudo make install
```

**Wrong PostgreSQL version**:
```
ERROR: incompatible library version
```

**Solution**: Rebuild against correct PostgreSQL version:
```bash
make clean
./configure --with-postgres=/correct/path
make
sudo make install
```

## Cleaning Build Artifacts

### Clean Object Files

```bash
make clean
```

Removes:
- `*.o` (object files)
- `*.so` (shared library)

### Clean All Generated Files

```bash
make distclean
```

Removes:
- Build artifacts (from `make clean`)
- `Makefile`
- `config.h`
- `config.status`
- `config.log`

**Note**: After `distclean`, must re-run `configure`.

## Version Detection

### PostgreSQL Version

Detected at configure time (`configure.in:50-53`):
```bash
PG_VERSION=$($PG_CONFIG --version|$AWK '{ print $2 }')
PG_MAJOR_VERSION=$(echo "$PG_VERSION"|$AWK -F. '{ print $1 }')
PG_MINOR_VERSION=$(echo "$PG_VERSION"|$AWK -F. '{ print substr($2,1,1) }')
```

Stored in `config.h`:
```c
#define PG_MAJOR_VERSION 9
#define PG_MINOR_VERSION 5
```

Used for compatibility macros in `plphp.c`:
```c
#if (CATALOG_VERSION_NO >= 200709301)
#define PG_VERSION_83_COMPAT
#endif
```

### PHP Version

Checked at configure time (`configure.in:102-105`):
```bash
AC_CHECK_LIB([php5], [php_module_startup], ...)
```

No version number stored - only validates PHP 5.x presence.

## Packaging

### For Distribution Packages

**Debian/Ubuntu**:
```bash
./configure
make
make DESTDIR=/tmp/build-root install
# Create .deb from /tmp/build-root
```

**RPM-based**:
```bash
./configure
make
make DESTDIR=$RPM_BUILD_ROOT install
```

### Multi-PostgreSQL Support

To support multiple PostgreSQL versions:

```bash
# Build for PostgreSQL 9.5
./configure --with-postgres=/usr/lib/postgresql/9.5
make
make install

# Clean and rebuild for PostgreSQL 9.6
make distclean
./configure --with-postgres=/usr/lib/postgresql/9.6
make
make install
```

Each version gets its own `plphp.so` in the respective `pkglibdir`.

## Development Setup

### Incremental Builds

After code changes:

```bash
make              # Rebuild modified files only
sudo make install # Reinstall
```

### Debug Build

```bash
./configure --enable-debug
make
sudo make install

# Run under gdb
gdb /usr/lib/postgresql/9.5/bin/postgres
(gdb) run [postgres options]
```

### Test Without Install

Not directly supported - PostgreSQL requires library in `pkglibdir`.

**Workaround**: Create symlink:
```bash
ln -s $(pwd)/plphp.so $(pg_config --pkglibdir)/plphp.so
```

## Dependencies Summary

| Component | Purpose | How to Install |
|-----------|---------|----------------|
| autoconf | Generate configure script | `apt-get install autoconf` |
| gcc | Compile C code | `apt-get install build-essential` |
| make (GNU) | Build automation | `apt-get install make` |
| PostgreSQL | Database server | `apt-get install postgresql` |
| PostgreSQL dev | Headers for building | `apt-get install postgresql-server-dev-all` |
| PHP | PHP interpreter | `apt-get install php5` |
| PHP dev | Headers and php-config | `apt-get install php5-dev` |
| PHP embed | Embed SAPI library | Build PHP with `--enable-embed` |

## Configuration Variables Reference

| Variable | Set By | Purpose |
|----------|--------|---------|
| `PG_CONFIG` | `--with-postgres` | Path to pg_config |
| `PHP_CONFIG` | `--with-php` | Path to php-config |
| `CPPFLAGS` | configure | C preprocessor flags |
| `LDFLAGS` | configure | Linker flags |
| `LIBS` | configure | Libraries to link |
| `DEBUG` | `--enable-debug` | Enable debug build |
| `PG_MAJOR_VERSION` | configure | PostgreSQL major version |
| `PG_MINOR_VERSION` | configure | PostgreSQL minor version |
| `PGXS` | configure | Path to PGXS makefile |
