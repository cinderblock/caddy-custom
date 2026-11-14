# caddy-custom

[Caddy](https://caddyserver.com) with [FrankenPHP](https://frankenphp.dev) and a
fixed set of plugins, for `linux/amd64` and `linux/arm64`.

```
ghcr.io/cinderblock/caddy-custom
```

## What's in it

| Plugin                                                                  | For                                    |
| ----------------------------------------------------------------------- | -------------------------------------- |
| [FrankenPHP](https://github.com/dunglas/frankenphp)                     | PHP apps (PHP built from source here)  |
| [Mercure](https://github.com/dunglas/mercure)                           | Server-sent push                       |
| [Vulcain](https://github.com/dunglas/vulcain)                           | Preload and push hints                 |
| [cbrotli](https://github.com/dunglas/caddy-cbrotli)                     | Brotli compression                     |
| [cache-handler](https://github.com/caddyserver/cache-handler)           | HTTP caching                           |
| [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)         | ACME DNS-01 through Cloudflare         |
| [caddy-cloudflare-ip](https://github.com/WeidiDeng/caddy-cloudflare-ip) | Cloudflare's ranges as trusted proxies |
| [caddy-events-exec](https://github.com/mholt/caddy-events-exec)         | Run commands on Caddy events           |
| [caddy-librespeed](https://github.com/cinderblock/caddy-librespeed)     | LibreSpeed speed test                  |
| [caddy-onlink](https://github.com/cinderblock/caddy-onlink)             | Match clients on the local network     |

Every version (Caddy, each plugin, Go, xcaddy, PHP, watcher, the Ubuntu base)
is pinned in the [`Dockerfile`](Dockerfile). Renovate proposes bumps: patches
merge on their own once the build and smoke test pass, minor and major releases
wait for a manual go-ahead.

## Tags

Each build of `master` is published as `<caddy version>-<short commit>` (for
example `2.11.9-a1b2c3d`) and as `latest`. Tags move; **pin the digest** in
anything you deploy:

```
ghcr.io/cinderblock/caddy-custom@sha256:…
```

Each build's job summary shows the digest it published. The image carries
`org.opencontainers.image.revision` (the commit it was built from) and
`org.opencontainers.image.version` (the Caddy version).

## Running it

The entrypoint is `caddy`, and the default command is `run --resume`. Caddy's
state lives at `/config` and `/data` (`XDG_CONFIG_HOME` and `XDG_DATA_HOME`), so
mount volumes there:

```sh
docker run -d -p 80:80 -p 443:443 -p 443:443/udp \
  -v caddy_config:/config -v caddy_data:/data \
  -v ./Caddyfile:/etc/caddy/Caddyfile:ro \
  ghcr.io/cinderblock/caddy-custom:latest run --config /etc/caddy/Caddyfile
```

## Building

```sh
docker buildx build --platform linux/amd64 -t caddy-custom .
test/smoke.sh caddy-custom
```

A cold build compiles PHP, watcher and Caddy from source and takes a while. In
CI each platform builds natively on its own runner, with the layer cache in
GitHub Actions' cache, so a plugin bump doesn't rebuild PHP.

`test/smoke.sh` checks that the binary is the pinned Caddy version, that every
plugin is in it at its pinned version, and that `caddy validate` accepts
[`test/Caddyfile`](test/Caddyfile) (which provisions FrankenPHP, Mercure,
Vulcain and Brotli).

## License

MIT for this repository's files. The image contains Caddy, PHP and the plugins
above, each under its own license.
