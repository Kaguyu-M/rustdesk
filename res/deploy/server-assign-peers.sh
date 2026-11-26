#!/bin/sh
# Server-side auto-assignment for lejianwen/rustdesk-api (free API).
# Every host that reports to the API but belongs to no user is given to OWNER
# (and optionally to a device group), so it shows up in "Accessible devices" for
# every member of OWNER's *share* user group. Hosts need no credentials.
#
# Usage (cron, every minute):
#   * * * * * /opt/rustdesk/server-assign-peers.sh /opt/rustdesk/data/rustdesk/api/rustdeskapi.db host-generique
#   optional 3rd arg: device group name
set -eu
DB="${1:?path to rustdeskapi.db}"
OWNER="${2:?owner username}"
DEVICE_GROUP="${3:-}"

command -v sqlite3 >/dev/null || { echo "sqlite3 is required (apt install sqlite3)" >&2; exit 1; }
esc() { printf "%s" "$1" | sed "s/'/''/g"; }

sqlite3 -cmd ".timeout 5000" "$DB" <<SQL
UPDATE peers
   SET user_id = (SELECT id FROM users WHERE username = '$(esc "$OWNER")')
 WHERE user_id = 0
   AND EXISTS (SELECT 1 FROM users WHERE username = '$(esc "$OWNER")');
SQL

if [ -n "$DEVICE_GROUP" ]; then
sqlite3 -cmd ".timeout 5000" "$DB" <<SQL
UPDATE peers
   SET group_id = (SELECT id FROM device_groups WHERE name = '$(esc "$DEVICE_GROUP")')
 WHERE group_id = 0
   AND EXISTS (SELECT 1 FROM device_groups WHERE name = '$(esc "$DEVICE_GROUP")');
SQL
fi
