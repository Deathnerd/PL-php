# Use Debian 10 (Buster) for compatibility with legacy PostgreSQL/PHP versions
FROM debian:buster

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential build tools and dependencies
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    gcc \
    g++ \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config \
    # PostgreSQL 9.6 server and development files
    postgresql-9.6 \
    postgresql-server-dev-9.6 \
    postgresql-client-9.6 \
    # PHP build dependencies
    libxml2-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libbz2-dev \
    libpng-dev \
    libjpeg-dev \
    # Debugging and development tools
    gdb \
    valgrind \
    strace \
    ltrace \
    # Utilities
    wget \
    curl \
    ca-certificates \
    git \
    vim \
    nano \
    less \
    psmisc \
    procps \
    lsof \
    && rm -rf /var/lib/apt/lists/*

# Configure PostgreSQL to allow local connections
RUN echo "local   all             all                                     trust" > /etc/postgresql/9.6/main/pg_hba.conf && \
    echo "host    all             all             127.0.0.1/32            trust" >> /etc/postgresql/9.6/main/pg_hba.conf && \
    echo "host    all             all             ::1/128                 trust" >> /etc/postgresql/9.6/main/pg_hba.conf

# Create postgres data directory with correct permissions
RUN mkdir -p /var/lib/postgresql/data && \
    chown -R postgres:postgres /var/lib/postgresql/data && \
    chmod 700 /var/lib/postgresql/data

# Create PHP build cache directory
RUN mkdir -p /opt/php-build && chmod 755 /opt/php-build

# Set up shell aliases for PostgreSQL management
RUN echo 'alias pgstart="su postgres -c \"pg_ctl -D /var/lib/postgresql/data start\""' >> /root/.bashrc && \
    echo 'alias pgstop="su postgres -c \"pg_ctl -D /var/lib/postgresql/data stop\""' >> /root/.bashrc && \
    echo 'alias pgstatus="su postgres -c \"pg_ctl -D /var/lib/postgresql/data status\""' >> /root/.bashrc && \
    echo 'alias pgrestart="su postgres -c \"pg_ctl -D /var/lib/postgresql/data restart\""' >> /root/.bashrc

# Set working directory
WORKDIR /workspace

# Keep container running
CMD ["sleep", "infinity"]
