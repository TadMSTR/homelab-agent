#!/bin/bash
# send-matrix.sh — post a message to a Matrix room via the bot account
# Usage: send-matrix.sh <room> <message>
#
# <room> accepts short names: sysadmin, research, developer, dev, writer,
#   security, announcements, alerts, agents, plane
#   or a full room ID starting with !
set -euo pipefail

ENV_FILE="${HOME}/.secrets/matrix-forge.env"
[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$ENV_FILE"

ROOM="${1:-}"
MESSAGE="${2:-}"
[[ -n "$ROOM" && -n "$MESSAGE" ]] || { echo "Usage: send-matrix.sh <room> <message>" >&2; exit 1; }

case "$ROOM" in
    sysadmin)      ROOM_ID="${MATRIX_ROOM_SYSADMIN}" ;;
    research)      ROOM_ID="${MATRIX_ROOM_RESEARCH}" ;;
    developer|dev) ROOM_ID="${MATRIX_ROOM_DEV}" ;;
    writer)        ROOM_ID="${MATRIX_ROOM_WRITER}" ;;
    security)      ROOM_ID="${MATRIX_ROOM_SECURITY}" ;;
    announcements) ROOM_ID="${MATRIX_ROOM_ANNOUNCEMENTS}" ;;
    alerts)        ROOM_ID="${MATRIX_ROOM_ALERTS}" ;;
    agents)        ROOM_ID="${MATRIX_ROOM_AGENTS}" ;;
    plane)         ROOM_ID="${MATRIX_ROOM_PLANE}" ;;
    !*)            ROOM_ID="$ROOM" ;;
    *)             echo "ERROR: Unknown room: $ROOM" >&2; exit 1 ;;
esac

TXN_ID="$(date +%s%3N)-$$"
ENCODED_ROOM=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$ROOM_ID")
BODY_JSON=$(python3 -c "import sys,json; print(json.dumps({'msgtype':'m.notice','body':sys.argv[1]}))" "$MESSAGE")

curl -sf \
    -X PUT \
    -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$BODY_JSON" \
    "${MATRIX_HOMESERVER_URL}/_matrix/client/v3/rooms/${ENCODED_ROOM}/send/m.room.message/${TXN_ID}" \
    > /dev/null
