# caddy-custom: Caddy with FrankenPHP (PHP built from source) and a fixed set
# of plugins, for linux/amd64 and linux/arm64.
#
# Every version is pinned here and only here, and Renovate (renovate.json)
# proposes each bump: the Caddy core, every plugin, Go, xcaddy, PHP, watcher and
# the Ubuntu base. Unpinned, a rebuild for an unrelated change once pulled in a
# FrankenPHP minor that rejected a working config and took two servers down.
#
# Stages: php and watcher compile their libraries from source, then caddy links
# against them. Each platform builds natively (no emulation) on its own runner;
# see .github/workflows/build.yml.

ARG UBUNTU=ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8

# ---------------------------------------------------------------------------
FROM ${UBUNTU} AS toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    ca-certificates \
    cmake \
    curl \
    g++ \
    gcc \
    git \
    libbrotli-dev \
    libsqlite3-dev \
    libxml2-dev \
    make \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# PHP as an embeddable, thread-safe library: what FrankenPHP links against.
#
# libphp.so is stripped of debug info (more than half its size; nothing in the
# image runs a debugger). --strip-debug keeps the symbol table, so a PHP crash
# backtrace still names functions.
FROM toolchain AS php
ARG PHP_VERSION=8.5.13
WORKDIR /src
RUN curl -fsSL "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" | tar -xz --strip-components=1 \
    && ./configure \
        --enable-embed \
        --enable-zts \
        --disable-zend-signals \
        --enable-zend-max-execution-timers \
    && make -j"$(nproc)" \
    && make install \
    && strip --strip-debug /usr/local/lib/libphp.so

# ---------------------------------------------------------------------------
# watcher: FrankenPHP's file-watching library.
FROM toolchain AS watcher
ARG WATCHER_VERSION=0.14.5
RUN git clone --depth 1 --branch "${WATCHER_VERSION}" https://github.com/e-dant/watcher.git /src \
    && cmake -S /src -B /build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/watcher \
        -DCMAKE_INSTALL_LIBDIR=lib \
    && cmake --build /build -j"$(nproc)" \
    && cmake --install /build

# ---------------------------------------------------------------------------
FROM toolchain AS caddy
ARG TARGETARCH
ARG GO_VERSION=1.27.4
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"

ARG XCADDY_VERSION=v0.4.7
RUN go install "github.com/caddyserver/xcaddy/cmd/xcaddy@${XCADDY_VERSION}"

# Only the embed library and headers: FrankenPHP's cgo build links -lphp and
# reads the headers through CGO_CFLAGS below.
COPY --from=php /usr/local/lib/libphp.so /usr/local/lib/
COPY --from=php /usr/local/include/php /usr/local/include/php
COPY --from=watcher /opt/watcher/lib/ /usr/local/lib/
COPY --from=watcher /opt/watcher/include/ /usr/local/include/
RUN ldconfig

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-I/usr/local/include/php -I/usr/local/include/php/main -I/usr/local/include/php/TSRM -I/usr/local/include/php/Zend"
ENV CGO_LDFLAGS="-L/usr/local/lib"

ARG CADDY_VERSION=2.11.9
WORKDIR /build
RUN xcaddy build "v${CADDY_VERSION}" \
    --with github.com/caddyserver/cache-handler@v0.17.0 \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/mholt/caddy-events-exec@v0.1.0 \
    --with github.com/WeidiDeng/caddy-cloudflare-ip@v0.0.0-20231130002422-f53b62aa13cb \
    --with github.com/dunglas/frankenphp/caddy@v1.13.5 \
    --with github.com/dunglas/mercure/caddy@v1.1.6 \
    --with github.com/dunglas/vulcain/caddy@v1.4.6 \
    --with github.com/dunglas/caddy-cbrotli@v1.0.1 \
    --with github.com/cinderblock/caddy-librespeed@v0.1.0 \
    --with github.com/cinderblock/caddy-onlink@v0.1.0

# ---------------------------------------------------------------------------
# Runtime: the same Ubuntu as the build, so glibc matches.
FROM ${UBUNTU}
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libbrotli1 \
    libsqlite3-0 \
    libxml2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=caddy /build/caddy /usr/bin/caddy
COPY --from=caddy /usr/local/lib/ /usr/local/lib/
RUN ldconfig && caddy version

# Caddy autosaves its admin-API config under $XDG_CONFIG_HOME/caddy and keeps
# TLS assets under $XDG_DATA_HOME/caddy. The official caddy image points these
# at /config and /data, so volumes mounted there hold them; without this they
# land on the container's own layer and every new image drops them.
ENV XDG_CONFIG_HOME=/config XDG_DATA_HOME=/data

# Mount named volumes at /config and /data. Don't declare VOLUME on
# /config/caddy or /data/caddy: Docker would create anonymous volumes there that
# shadow those mounts.
VOLUME ["/var/www", "/var/log/caddy"]

EXPOSE 80 443 443/udp

ENTRYPOINT ["caddy"]
CMD ["run", "--resume"]
