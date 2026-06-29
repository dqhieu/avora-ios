#!/usr/bin/env bash
# Remove all smoke-test artifacts from the DEPLOYED backend:
#   - storage objects (inputs/<uid>/smoke.png, and any outputs/<uid>/<job>.png)
#   - the test users (smoke+*@avora.test) — deleting the user cascades their
#     profiles + generations rows via FK on delete cascade.
#
# Usage (from your terminal so the service_role key stays local):
#   export SERVICE_ROLE_KEY='...'   # Dashboard -> Settings -> API -> service_role
#   bash supabase/tests/smoke-cleanup.sh
set -euo pipefail

URL="${SUPABASE_URL:-https://dqdsuzmqlnheiokfboyv.supabase.co}"
: "${SERVICE_ROLE_KEY:?set SERVICE_ROLE_KEY}"
SR="$SERVICE_ROLE_KEY"
AUTH="$URL/auth/v1"; STG="$URL/storage/v1"; REST="$URL/rest/v1"

echo "→ finding smoke test users (smoke+*@avora.test)"
USERS=$(curl -s "$AUTH/admin/users?per_page=500" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" \
  | python3 -c 'import sys,json
d=json.load(sys.stdin)
us=d.get("users", d if isinstance(d,list) else [])
for u in us:
    e=(u.get("email") or "")
    if e.startswith("smoke+") and e.endswith("@avora.test"):
        print(u["id"])')

if [ -z "${USERS:-}" ]; then echo "  none found — nothing to clean."; exit 0; fi
N=$(echo "$USERS" | grep -c . || true)
echo "  found $N user(s)"

del_obj() { # bucket path
  curl -s -X DELETE "$STG/object/$1" \
    -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" \
    -d "{\"prefixes\":[\"$2\"]}" >/dev/null || true
}

while read -r U; do
  [ -z "$U" ] && continue
  echo "→ $U"
  # input path is deterministic (the smoke test always uploads smoke.png)
  del_obj inputs "$U/smoke.png"
  # outputs come from this user's generation rows
  OUTS=$(curl -s "$REST/generations?user_id=eq.$U&select=output_path" \
    -H "apikey: $SR" -H "Authorization: Bearer $SR" \
    | python3 -c 'import sys,json
[print(r["output_path"]) for r in json.load(sys.stdin) if r.get("output_path")]' 2>/dev/null || true)
  while read -r O; do [ -n "$O" ] && del_obj outputs "$O"; done <<< "$OUTS"
  # delete the auth user -> cascades profiles + generations
  curl -s -X DELETE "$AUTH/admin/users/$U" -H "apikey: $SR" -H "Authorization: Bearer $SR" >/dev/null || true
  echo "   storage + user removed"
done <<< "$USERS"

echo "✅ cleanup complete ($N user(s))"
