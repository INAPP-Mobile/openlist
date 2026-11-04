# OpenList on Railway — wrapper around the pinned upstream image.
#
# Why a wrapper at all (house style: bake constants, keep the deploy
# form zero-field, and survive Railway's root-owned volumes):
# - PORT: OpenList binds http_port from its config (default 5244) but
#   reads configuration from environment variables FIRST (upstream
#   runs `./openlist server --no-prefix`, verified in upstream
#   entrypoint.sh, so conf fields map to bare env vars). entrypoint.sh
#   therefore exports HTTP_PORT=$PORT (plus OPENLIST_HTTP_PORT
#   defensively) on every boot. Railway injects PORT at runtime.
# - USER root: upstream runs as uid 1001 (openlist) and its own
#   entrypoint.sh REFUSES to start when ./data is not writable and
#   executable for the current user. Railway mounts volumes
#   root-owned, so the stock image exits on first boot — this is why
#   both existing marketplace OpenList templates sit at 0% health.
#   The wrapper runs as root, so /opt/openlist/data is writable.
# - DATA: a single Railway volume at /opt/openlist/data holds
#   config.json, data.db (users, storages, settings) and the local
#   storage root /opt/openlist/data/files. Railway allows one volume
#   per service, so the file root lives inside the data volume.
# - ADMIN: there is no setup wizard when a password is provided:
#   upstream creates the `admin` account itself on first boot from
#   OPENLIST_ADMIN_PASSWORD (verified in
#   internal/bootstrap/data/user.go: when no admin user exists, the
#   server creates one from that variable; once an admin exists the
#   variable is ignored, so a password changed in the UI is never
#   reset by a redeploy). entrypoint.sh therefore maps the
#   template's ADMIN_PASSWORD onto OPENLIST_ADMIN_PASSWORD on
#   every boot. Without it, first boot creates no admin and the
#   web setup wizard (POST /api/public/init/setup) owns admin
#   creation instead. The upstream `openlist admin set` CLI is
#   deliberately NOT used for seeding: on a fresh volume no admin
#   exists yet, so it fails silently with exit code 0.
# - STORAGE: entrypoint.sh also creates a `Files` Local storage
#   (mount /Files, root /opt/openlist/data/files) exactly once per
#   volume via the admin API, best-effort — a failed seed never
#   blocks boot, and the README documents the manual path.
# - S3/FTP/SFTP servers stay off (upstream defaults). Railway's
#   public edge is HTTP-only, so only the web UI and WebDAV at /dav
#   are reachable; the optional servers have no public port here.
# - No Docker HEALTHCHECK: rely on Railway's external
#   healthcheckPath (/ serves the SPA login page unauthenticated).
#
# Upstream: OpenList v4.2.9 (AGPL-3.0), image pinned by manifest
# digest, verified 2026-11-04 via the Docker Hub registry API
# (multi-arch index digest below; amd64 image digest
# sha256:e346ed04eae6e82db290cb31f727e71772e32c370750468630da6aaab3a99729).

FROM openlistteam/openlist:v4.2.9@sha256:897563beb674e7ad04edff14b0037dc8443ca3978570614005519df7eae06434

USER root

COPY entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

# Documentation only: Railway routes to $PORT at runtime (see
# entrypoint.sh); 5244 is the upstream default the image would use
# without the wrapper's HTTP_PORT mapping.
EXPOSE 5244

CMD ["/railway-entrypoint.sh"]
