# Low-memory Coolify profile (1 GB VPS)

This fork includes an opt-in profile for small servers. It keeps the web UI,
Horizon queue worker, scheduler, PostgreSQL, Redis and realtime service enabled.
The goal is lower idle RAM, not maximum deployment throughput.

## What changes

- PHP limit: 192 MB
- PHP-FPM: `ondemand`, at most 2 children
- Horizon: 1 worker instead of up to 4
- Horizon worker recycle: 100 jobs
- Horizon worker limit: 96 MB when using an image built from this fork
- PostgreSQL: 32 MB shared buffers, 30 connections, JIT disabled

## Run from this repository

Build/publish the Coolify image from this fork, then use:

```bash
docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  -f docker-compose.low-memory.yml up -d
```

For a normal Coolify installation under `/data/coolify`, copy
`docker-compose.low-memory.yml` to:

```text
/data/coolify/source/docker-compose.custom.yml
```

Then add the values from `.env.low-memory.example` to
`/data/coolify/source/.env` and run the normal Coolify upgrade/restart.
The custom compose file is already recognized by Coolify's upgrade script.

## Recommended host setup

A 1 GB server should also have 1-2 GB swap. Avoid building several images in
parallel. One deployment at a time is the intended operating mode for this
profile. Do not disable Horizon or the scheduler; deployments and maintenance
jobs depend on them.

## Automatic installer

For a fresh server, run the wrapper from this repository:

```bash
sudo bash scripts/install-low-memory.sh
```

It reads `/proc/meminfo` before installation. Servers with 1200 MB RAM or less
are treated as 1 GB-class machines and automatically receive the low-memory
profile after the normal Coolify installer completes. Larger servers use the
normal Coolify configuration.

You can override detection:

```bash
sudo COOLIFY_LOW_MEMORY=true bash scripts/install-low-memory.sh
sudo COOLIFY_LOW_MEMORY=false bash scripts/install-low-memory.sh
```

You can also change the automatic threshold, in MB:

```bash
sudo LOW_MEMORY_THRESHOLD_MB=1500 bash scripts/install-low-memory.sh
```

The installer writes the overlay to
`/data/coolify/source/docker-compose.custom.yml`, which Coolify's normal
upgrade process already includes on future upgrades.
