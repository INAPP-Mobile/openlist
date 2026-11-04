#!/bin/sh
# OpenList Railway wrapper entrypoint (Alpine /bin/sh — no bash,
# python, curl or jq in the upstream image; busybox wget only).
#
# What it does, in order:
# - PORT: Railway injects PORT at runtime. Upstream runs
#   `./openlist server --no-prefix` (verified in upstream
#   entrypoint.sh), so conf fields map to bare env vars and env wins
#   over config.json. Export HTTP_PORT=$PORT (plus the prefixed
#   spelling defensively) on every boot.
# - DATA: /opt/openlist/data is the single Railway volume; the
#   local file root /opt/openlist/data/files lives inside it
#   (one volume per service on Railway).
# - ADMIN: upstream creates the `admin` account itself on first
#   boot from OPENLIST_ADMIN_PASSWORD (verified in
#   internal/bootstrap/data/user.go: when no admin user exists,
#   the server creates one from that variable; once an admin
#   exists the variable is ignored, so a password changed in the
#   UI is never reset by a redeploy). The wrapper therefore maps
#   the template's ADMIN_PASSWORD onto OPENLIST_ADMIN_PASSWORD
#   on every boot. Without it, first boot creates no admin and
#   the web setup wizard (POST /api/public/init/setup) owns admin
#   creation instead. NOTE: the upstream `openlist admin set` CLI
#   is NOT used for seeding — on a fresh volume no admin exists
#   yet, so it fails silently with exit code 0 (its set function
#   logs the GetAdmin error and returns anyway); the env-var path
#   above is the only reliable first-boot mechanism.
# - FILES STORAGE (marker-gated, best-effort): once the server
#   answers, log in via the admin API with the seeded password
#   and create a `Files` Local storage (mount /Files ->
#   /opt/openlist/data/files). A failed seed only logs a warning
#   — the server keeps running and the README documents adding
#   the storage by hand. The marker is written only on success,
#   so a bad payload retries on the next boot while the
#   service-variable password still matches (the user has not
#   changed it yet at that point).
# - STEADY STATE: exec the server in the foreground, exactly as
#   upstream does (`./openlist server --no-prefix`).

DATA_DIR="/opt/openlist/data"
FILES_DIR="$DATA_DIR/files"
STORAGE_MARKER="$DATA_DIR/.railway-storage-seeded"

cd /opt/openlist || exit 1
umask "${UMASK:-022}"
mkdir -p "$FILES_DIR"

# Legacy marker from the v1 entrypoint's CLI-seeding attempt: that
# mechanism never actually set a password (see header), so the
# marker is meaningless — remove it for tidiness.
rm -f "$DATA_DIR/.railway-admin-seeded"

PORT_VALUE="${PORT:-5244}"
export HTTP_PORT="$PORT_VALUE"
export OPENLIST_HTTP_PORT="$PORT_VALUE"

if [ -n "${ADMIN_PASSWORD:-}" ]; then
  export OPENLIST_ADMIN_PASSWORD="$ADMIN_PASSWORD"
fi

# Defensive writability check, mirroring upstream entrypoint.sh
# (which refuses to start when ./data is not writable). As root on
# Railway's root-owned volume this passes; fail loud if it ever
# does not, instead of crash-looping silently.
if [ ! -w "$DATA_DIR" ] || [ ! -x "$DATA_DIR" ]; then
  echo "OpenList: ERROR $DATA_DIR is not writable/executable for the current user; refusing to start."
  exit 1
fi

if [ ! -f "$STORAGE_MARKER" ] && [ -n "${ADMIN_PASSWORD:-}" ]; then
  echo "OpenList: first-boot storage seeding; starting server in background."
  ./openlist server --no-prefix &
  SERVER_PID=$!

  # Wait for the web UI to answer (up to ~120s). By then the
  # server has finished bootstrap, so the admin account created
  # from OPENLIST_ADMIN_PASSWORD already exists.
  OK=0
  i=0
  while [ $i -lt 60 ]; do
    if wget -q -O /dev/null "http://127.0.0.1:${PORT_VALUE}/" 2>/dev/null; then
      OK=1
      break
    fi
    sleep 2
    i=$((i + 1))
  done
  if [ "$OK" != "1" ]; then
    echo "OpenList: WARNING server did not answer on 127.0.0.1:${PORT_VALUE} after ~120s; storage seeding skipped, waiting on the server."
    wait "$SERVER_PID"
    exit $?
  fi

  LOGIN_JSON=$(printf '{"username":"admin","password":"%s"}' "$ADMIN_PASSWORD")
  TOKEN=$(wget -q -O - --header="Content-Type: application/json" --post-data="$LOGIN_JSON" "http://127.0.0.1:${PORT_VALUE}/api/auth/login" 2>/dev/null | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  if [ -n "$TOKEN" ]; then
    ADDITION='{\"root_folder_path\": \"/opt/openlist/data/files\"}'
    STORAGE_JSON="{\"mount_path\": \"/Files\", \"order\": 0, \"driver\": \"Local\", \"cache_expiration\": 30, \"status\": 1, \"addition\": \"$ADDITION\", \"remark\": \"Local files on the Railway volume (created by the template on first boot).\", \"disabled\": false, \"enable_sign\": false}"
    RESP=$(wget -q -O - --header="Authorization: $TOKEN" --header="Content-Type: application/json" --post-data="$STORAGE_JSON" "http://127.0.0.1:${PORT_VALUE}/api/admin/storage/create" 2>/dev/null)
    echo "OpenList: storage create response: $RESP"
    case "$RESP" in
      *'"code":200'*)
        touch "$STORAGE_MARKER"
        echo "OpenList: Files storage created."
        ;;
      *)
        echo "OpenList: WARNING Files storage not created; add it by hand: Manage -> Storages -> Add, Local driver, mount path /Files, root folder /opt/openlist/data/files."
        ;;
    esac
  else
    echo "OpenList: WARNING could not log in via API for storage seeding (the password may have been changed in the UI); skipping."
  fi

  wait "$SERVER_PID"
  exit $?
fi

echo "OpenList: binding 0.0.0.0:${PORT_VALUE}, data ${DATA_DIR} (volume), files ${FILES_DIR}"
exec ./openlist server --no-prefix
