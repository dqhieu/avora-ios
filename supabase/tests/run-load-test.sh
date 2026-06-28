#!/usr/bin/env bash
# Parallel-submit concurrency load test.
#
# Fires N simultaneous POST /submit-generation requests against an account
# seeded with exactly 25 credits (one generation's worth).  The row-locking
# inside deduct_credit must serialise the burst so that EXACTLY ONE request
# receives a 202 and the remaining N-1 receive 402.
#
# REQUIREMENTS
#   - supabase CLI on $PATH (local stack already running)
#   - curl, python3 available
#   - The local stack exposes its API at http://127.0.0.1:54341
#     and its DB at postgresql://postgres:postgres@127.0.0.1:54342/postgres
#
# USAGE (self-contained — the script creates and tears down its own test user)
#   bash supabase/tests/run-load-test.sh
#
# ENVIRONMENT OVERRIDES (optional)
#   API_URL        — default: http://127.0.0.1:54341
#   PARALLEL_N     — number of parallel requests to fire (default: 10)
#   TEST_EMAIL     — email for the ephemeral test user
#   TEST_PASSWORD  — password for the ephemeral test user

set -euo pipefail

# ── configuration ────────────────────────────────────────────────────────────
API_URL="${API_URL:-http://127.0.0.1:54341}"
PARALLEL_N="${PARALLEL_N:-10}"
TEST_EMAIL="${TEST_EMAIL:-loadtest-concurrency@avora.test}"
TEST_PASSWORD="${TEST_PASSWORD:-AvoraLoad#2025}"

ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
FUNCTIONS_URL="$API_URL/functions/v1"
AUTH_URL="$API_URL/auth/v1"

# ── helpers ───────────────────────────────────────────────────────────────────
pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; exit 1; }

# ── 1. create test user (admin API, email already confirmed) ──────────────────
echo ""
echo "=== [1/5] Create ephemeral test user ==="

CREATE_RESP=$(curl -s -X POST "$AUTH_URL/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\",\"email_confirm\":true}")

# If user already exists (re-running the script) the call returns a 422 with
# a "User already exists" message — extract id from that path too.
USER_ID=$(echo "$CREATE_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# new user: top-level 'id'; duplicate: may be inside 'msg' which is not JSON —
# fall through to the lookup below.
uid = d.get('id') or d.get('user', {}).get('id', '')
print(uid)
" 2>/dev/null || true)

if [ -z "$USER_ID" ]; then
  # User already exists — fetch by email via admin list
  USER_ID=$(curl -s "$AUTH_URL/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    | python3 -c "
import sys, json
users = json.load(sys.stdin).get('users', [])
match = next((u for u in users if u.get('email') == '$TEST_EMAIL'), None)
print(match['id'] if match else '')
")
fi

[ -n "$USER_ID" ] || fail "Could not create or locate test user"
pass "test user id: $USER_ID"

# ── 2. sign in to get a JWT ───────────────────────────────────────────────────
echo ""
echo "=== [2/5] Obtain user JWT ==="

JWT=$(curl -s -X POST "$AUTH_URL/token?grant_type=password" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

[ -n "$JWT" ] || fail "Sign-in failed — no access_token"
pass "JWT obtained (${JWT:0:30}...)"

# ── 3. upload a 1 × 1 PNG to inputs/<uid>/test.png ──────────────────────────
echo ""
echo "=== [3/5] Upload test PNG to storage ==="

# Smallest valid 1×1 PNG (70 bytes, base64-encoded)
TINY_PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
TMPFILE=$(mktemp /tmp/avora-test-XXXXXX.png)
python3 -c "import base64; open('$TMPFILE','wb').write(base64.b64decode('$TINY_PNG_B64'))"

UPLOAD_RESP=$(curl -s -X POST "$API_URL/storage/v1/object/inputs/$USER_ID/test.png" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: image/png" \
  --data-binary @"$TMPFILE")
rm -f "$TMPFILE"

echo "$UPLOAD_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# success → has 'Key'; duplicate (already exists in MinIO) → may have 'error'
if 'Key' in d or 'Id' in d:
    print('  uploaded:', d.get('Key',''))
else:
    # could be 'Duplicate' if the bucket already holds the file — that's fine
    print('  storage response:', json.dumps(d))
" 2>/dev/null || echo "  (response was not JSON — storage upload may still be ok)"

pass "PNG at inputs/$USER_ID/test.png"

# ── 4. reset credits: weekly=0, extra=25 (exactly one generation) ─────────────
echo ""
echo "=== [4/5] Seed credits: weekly_credits=0, extra_credits=25 ==="

supabase db query "UPDATE public.profiles SET weekly_credits=0, extra_credits=25 WHERE id='$USER_ID';" \
  2>/dev/null | grep -v "^A new version" | grep -v "^We recommend" | grep -v "^Connecting" || true

CREDITS=$(supabase db query \
  "SELECT weekly_credits, extra_credits FROM public.profiles WHERE id='$USER_ID';" \
  2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin).get('rows', [])
r = rows[0] if rows else {}
print(f\"weekly={r.get('weekly_credits')}, extra={r.get('extra_credits')}\")
" 2>/dev/null || echo "(could not read)")

pass "credits after reset: $CREDITS"

# ── 5. fire N parallel POST requests ─────────────────────────────────────────
echo ""
echo "=== [5/5] Fire $PARALLEL_N parallel submit-generation requests ==="

codes=$(for i in $(seq 1 "$PARALLEL_N"); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST "$FUNCTIONS_URL/submit-generation" \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    -d "{\"style_id\":\"ghibli\",\"input_path\":\"$USER_ID/test.png\"}" &
done; wait)

echo ""
echo "--- HTTP code tally ---"
echo "$codes" | sort | uniq -c
echo "-----------------------"

count_202=$(echo "$codes" | grep -c "^202$" || true)
count_402=$(echo "$codes" | grep -c "^402$" || true)
count_other=$(echo "$codes" | grep -vcE "^(202|402)$" || true)

echo ""
echo "  202 (accepted):             $count_202"
echo "  402 (insufficient_credits): $count_402"
echo "  other (unexpected):         $count_other"
echo ""

# ── assert exactly-one semantics ─────────────────────────────────────────────
FAIL=0

if [ "$count_202" -ne 1 ]; then
  echo "FAIL  Expected exactly 1 x 202, got $count_202"
  FAIL=1
fi

expected_402=$(( PARALLEL_N - 1 ))
if [ "$count_402" -ne "$expected_402" ]; then
  echo "FAIL  Expected $expected_402 x 402, got $count_402"
  FAIL=1
fi

if [ "$count_other" -ne 0 ]; then
  echo "FAIL  Unexpected HTTP codes present"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS  Atomic deduction verified: exactly 1 of $PARALLEL_N concurrent"
  echo "      submit-generation requests succeeded (202); the rest were"
  echo "      correctly rejected with 402 (insufficient_credits)."
else
  echo ""
  echo "DOUBLE-SPEND DETECTED or unexpected error — review deduct_credit."
  exit 1
fi
