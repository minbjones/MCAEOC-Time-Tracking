# YAML-Only Synology Upload

If Synology Container Manager only allows uploading a compose file, use:

- [docker-compose.upload.yml](</C:/Users/minbj/Documents/MCAEOC Time Tracking/synology_mariadb/docker-compose.upload.yml>)

Before uploading it:

1. Replace `your-github-user-or-org` with your GitHub user or organization name.
2. Keep these exact image names:
   - `ghcr.io/<your-github-user-or-org>/mcaeoc-time-tracking-synology-web:latest`
   - `ghcr.io/<your-github-user-or-org>/mcaeoc-time-tracking-synology-mobile-api:latest`
3. Replace all placeholder passwords and keys.

## GitHub push workflow

This repo now includes:

- [.github/workflows/synology-ghcr-images.yml](</C:/Users/minbj/Documents/MCAEOC Time Tracking/.github/workflows/synology-ghcr-images.yml>)

That workflow builds and pushes these exact tags to GHCR on `master` pushes and manual runs:

```text
ghcr.io/<your-github-user-or-org>/mcaeoc-time-tracking-synology-web:latest
ghcr.io/<your-github-user-or-org>/mcaeoc-time-tracking-synology-web:sha-<short-sha>
ghcr.io/<your-github-user-or-org>/mcaeoc-time-tracking-synology-mobile-api:latest
ghcr.io/<your-github-user-or-org>/mcaeoc-time-tracking-synology-mobile-api:sha-<short-sha>
```

It uses the built-in `GITHUB_TOKEN`, so you do not need separate registry credentials for GHCR if the workflow runs in the same repo.

## Important limitation

This upload-only compose file does **not** mount `schema_mariadb.sql`, because Synology YAML upload mode does not include project-side files.

So you must do one of these first:

- import `schema_mariadb.sql` into MariaDB manually, or
- build an image/workflow that preloads the schema another way

## Example image names

```text
ghcr.io/your-org/mcaeoc-time-tracking-synology-web:latest
ghcr.io/your-org/mcaeoc-time-tracking-synology-mobile-api:latest
```
