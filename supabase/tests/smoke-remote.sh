#!/usr/bin/env bash
# End-to-end smoke test against the DEPLOYED Avora backend.
# Proves: submit-generation -> pgmq -> cron worker pump (Vault) -> gpt-image-2 -> stored result.
#
# Runs ONE real generation at quality=low to minimize cost. Temporarily sets the
# 'ghibli' style to quality=low, then restores it to medium on exit.
#
# Usage (from your terminal so the service_role key stays local):
#   export SERVICE_ROLE_KEY='...'   # Dashboard -> Settings -> API -> service_role (secret)
#   export ANON_KEY='...'           # Dashboard -> Settings -> API -> anon public
#   bash supabase/tests/smoke-remote.sh
set -euo pipefail

URL="${SUPABASE_URL:-https://dqdsuzmqlnheiokfboyv.supabase.co}"
: "${SERVICE_ROLE_KEY:?set SERVICE_ROLE_KEY}"
: "${ANON_KEY:?set ANON_KEY}"
REST="$URL/rest/v1"; AUTH="$URL/auth/v1"; FN="$URL/functions/v1"; STG="$URL/storage/v1"
STYLE="ghibli"
EMAIL="smoke+$(date +%s)@avora.test"; PASS="Password123!"
PNG="$(mktemp -t avora-smoke).png"

restore() {
  echo "→ restoring $STYLE quality to medium"
  curl -s -X PATCH "$REST/styles?id=eq.$STYLE" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" -H "Prefer: return=minimal" \
    -d '{"default_quality":"medium"}' >/dev/null || true
  rm -f "$PNG"
}
trap restore EXIT

echo "→ generating a 512x512 test PNG"
python3 - "$PNG" <<'PY'
import zlib, struct, sys
w=h=512
raw=bytearray()
row=bytes([100,150,200])*w
for _ in range(h):
    raw.append(0); raw+=row
def chunk(t,d):
    c=t+d
    return struct.pack(">I",len(d))+c+struct.pack(">I",zlib.crc32(c)&0xffffffff)
png=b"\x89PNG\r\n\x1a\n"
png+=chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,2,0,0,0))
png+=chunk(b"IDAT",zlib.compress(bytes(raw),9))
png+=chunk(b"IEND",b"")
open(sys.argv[1],"wb").write(png)
PY

echo "→ set $STYLE quality to low (temporary)"
curl -s -X PATCH "$REST/styles?id=eq.$STYLE" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"default_quality":"low"}' >/dev/null

echo "→ creating confirmed test user $EMAIL"
USER_ID=$(curl -s -X POST "$AUTH/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\",\"email_confirm\":true}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
echo "   uid=$USER_ID"

echo "→ signing in for a JWT"
JWT=$(curl -s -X POST "$AUTH/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

echo "→ uploading input to inputs/$USER_ID/smoke.png"
curl -s -X POST "$STG/object/inputs/$USER_ID/smoke.png" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "Content-Type: image/png" \
  --data-binary "@$PNG" >/dev/null

echo "→ submitting generation"
SUBMIT=$(curl -s -X POST "$FN/submit-generation" \
  -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d "{\"style_id\":\"$STYLE\",\"input_path\":\"$USER_ID/smoke.png\"}")
echo "   submit response: $SUBMIT"
JOB=$(echo "$SUBMIT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["job_id"])')
echo "   job_id=$JOB"

echo "→ polling get-generation (worker pump runs every minute; waiting up to 4 min)"
STATUS=pending
for i in $(seq 1 48); do
  sleep 5
  RESP=$(curl -s "$FN/get-generation?id=$JOB" -H "Authorization: Bearer $JWT")
  STATUS=$(echo "$RESP" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status","?"))')
  printf "   [%3ds] %s\n" "$((i*5))" "$STATUS"
  [ "$STATUS" = "completed" ] && break
  [ "$STATUS" = "failed" ] && break
done

echo "→ generation row detail (tokens/size for cost):"
curl -s "$REST/generations?id=eq.$JOB&select=status,quality,size,input_tokens,output_tokens,error_code,output_path" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" | python3 -m json.tool

echo ""
if [ "$STATUS" = "completed" ]; then
  echo "✅ SMOKE TEST PASSED — full cloud pipeline produced an image."
else
  echo "⚠️  Final status: $STATUS — see error_code above. Pipeline plumbing exercised; check the detail."
fi
