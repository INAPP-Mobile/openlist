# OpenList

OpenList is a self-hosted file list and file manager — one web interface in front of local disk, S3 buckets, SFTP and SMB shares, WebDAV servers, and dozens of cloud drives (Google Drive, OneDrive, Dropbox, and more). It is the community-run AGPL-3.0 fork of AList, actively developed after AList's mid-2025 sale, with the same Go backend and web UI. Deploy it on Railway and your files stay on your own volume and your own storage accounts, not a third-party file host.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/openlist?utm_campaign=openlist)

![OpenList file browser showing the pre-created Files storage with a test file](assets/openlist-files.png)

*OpenList file browser — screenshot captured from this template's own deployment during end-to-end testing, showing the pre-created Files storage with test data.*

## Source Repository

[https://github.com/INAPP-Mobile/openlist](https://github.com/INAPP-Mobile/openlist)

## Deploy and Host

One-click deploy creates a single OpenList service with a persistent volume. No companion database is needed: OpenList stores users, storages, and settings in an embedded SQLite database file on the volume. On first boot the wrapper maps Railway's injected `PORT` onto OpenList's HTTP port, seeds the `admin` account exactly once from the generated deploy password, and pre-creates a `Files` Local storage pointing at `/opt/openlist/data/files` on the volume — so the deploy is usable immediately, with no storage setup before the first upload.

After deploy, open the public URL and sign in as `admin` with the generated `ADMIN_PASSWORD` (find it in your Railway project's variables). Only the admin account exists after deploy; the admin creates additional users from Manage -> Users. The built-in `guest` account ships disabled, so anonymous visitors see nothing.

## Why Deploy

- Browse many backends from one UI: local disk, S3, SFTP, SMB, WebDAV, Google Drive, OneDrive, Dropbox, and dozens more, each mounted at a path you choose.
- WebDAV server at `/dav` with the same login — mount your files in Finder, Explorer, or any WebDAV client.
- Local files on the volume: upload straight into the pre-created `Files` storage, no cloud account needed.
- Previews in the browser for images, video, audio, and text, plus password-protected paths per folder.
- No database service to run: one always-on Go service with an embedded SQLite file on a persistent volume.
- Self-hosted data: your files stay on your Railway volume and your own storage accounts.

## Common Use Cases

- A single front door for scattered storage: one bucket, one Drive account, and local files behind one login.
- Family or team file sharing over WebDAV without handing out cloud-drive credentials.
- A private upload drop on the volume for files you want off third-party hosts.
- Browse a cloud drive from a phone or a second machine through the web UI instead of vendor apps.

## Configuration

Only one variable appears on the deploy form, and it is generated:

| Variable | Default | Description |
| --- | --- | --- |
| `ADMIN_PASSWORD` | `${{secret(24)}}` | Password for the `admin` account. Generated on deploy; seeded exactly once per volume on first boot. Changing it later does not change the password — change it in the OpenList UI instead (Manage -> Profile). If left empty, the server generates a random password printed in the deploy logs. |

Everything else is baked into the image. Applicable upstream variables and their baked values:

| Variable | Value | Description |
| --- | --- | --- |
| `PORT` | Railway-injected | OpenList's HTTP port: the wrapper exports it as `HTTP_PORT` on every boot (upstream default is 5244). |
| `HTTP_PORT` | `$PORT` | The port OpenList binds, derived from Railway's injected `PORT` (upstream reads config from env vars first). |
| `OPENLIST_ADMIN_PASSWORD` | not set | Upstream's own admin-password env var is deliberately not wired: the wrapper seeds the password exactly once via the upstream CLI instead, so a password changed in the UI is never reset by a redeploy. |
| `TZ` | `UTC` (container default) | Add `TZ` as a custom service variable if you want local timestamps; the Go binary honors it. |
| Data directory | `/opt/openlist/data` | The single Railway volume: `config.json`, `data.db` (SQLite: users, storages, settings), and the `files/` local storage root. |
| WebDAV | `/dav` | Built-in WebDAV server on the same port, same login as the web UI. |
| S3 / FTP / SFTP servers | off (upstream defaults) | Optional upstream servers that need their own public ports; Railway's public edge is HTTP-only, so they stay off here. |
| Offline download | not included | Offline download tasks need aria2, which the standard upstream image does not bundle (`RUN_ARIA2=false`); use the `aio` upstream image variant if you need it. |

## Persistence

One volume mounted at `/opt/openlist/data` holds `config.json`, `data.db`, and `files/` (the `Files` storage root). Restarts and redeploys keep accounts, storages, settings, and uploaded files. Back up the volume to back up OpenList.

## Deployment Dependencies

- Plan tier: works on Railway's entry tiers; a single always-on service with a persistent volume.
- RAM needs: light — one Go service, typically well under 256 MB at rest, no companion database or cache service.
- Upstream: [OpenList v4.2.9](https://github.com/OpenListTeam/OpenList) (AGPL-3.0), image pinned by manifest digest.
