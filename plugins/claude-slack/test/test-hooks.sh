#!/bin/bash
#
# test-hooks.sh - Integration tests for claude-slack hook handlers
#
# IMPORTANT: Before running this script, you MUST disable the live hook
# integration first, otherwise the hook will intercept the bash command
# that launches the test script and block execution.
#
#   claude-slack disable        # or: echo '{"enabled":false}' > ~/.claude-slack/state.json
#   bash ~/.claude-slack/test-hooks.sh 2 3 5 6 7 8 9 10 11 12 13
#   claude-slack enable         # re-enable when done
#
# The test script itself manages the enabled/disabled state internally
# for each test case, and restores the original state on exit.
#
# Usage:
#   bash test/test-hooks.sh           # Run all tests
#   bash test/test-hooks.sh 2         # Run only test 2
#   bash test/test-hooks.sh 2 3 6     # Run tests 2, 3, and 6
#
# Safe tests (will NOT post to Slack - run freely):
#   2  - Error object rejection (permission-request)
#   3  - Error message rejection (notification)
#   5  - Concurrent lock test (second process rejected)
#   6  - Invalid AskUserQuestion rejection
#   7  - Disabled state rejection (all three hook types)
#   8  - Malformed JSON rejection
#   9  - Error in tool_input rejection (permission-request)
#   10 - Error object in notification rejected
#   11 - rate_limit_error message rejected (notification)
#   12 - Error object in AskUserQuestion rejected
#   13 - Empty tool_name rejected (permission-request)
#
# Dangerous tests (WILL post to Slack - use with caution):
#   1  - Valid permission-request (posts, polls for reply, killed after 10s)
#   4  - Valid notification (posts a test message)
#
# After running, check results:
#   tail -50 ~/.claude-slack/debug.log
#

set -uo pipefail
# NOTE: We intentionally do NOT use set -e because grep returns non-zero
# when a pattern is not found, which is expected in our assertions.

SCRIPT="$(dirname "$0")/../bin/claude-slack"
LOG="$HOME/.claude-slack/debug.log"
LOCK_DIR="$HOME/.claude-slack"
PASS=0
FAIL=0
SKIP=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

separator() {
  echo ""
  echo "================================================================"
}

log_marker() {
  # Insert a visible marker into debug.log so we can isolate each test's output
  local label="$1"
  echo "" >> "$LOG"
  echo "[TEST] ======== $label ========" >> "$LOG"
}

# Get lines from debug.log that appeared AFTER a given marker, stopping at
# the next marker (or EOF). This avoids picking up background process noise
# from other tests.
log_since_marker() {
  local label="$1"
  # Print lines between this marker and the next [TEST] marker (or EOF).
  # AWK: start printing after our marker, stop when we hit another [TEST] marker.
  awk "
    /\\[TEST\\] ======== $label ========/ { found=1; next }
    found && /\\[TEST\\] ========/ { exit }
    found { print }
  " "$LOG"
}

assert_log_contains() {
  local label="$1"
  local pattern="$2"
  local description="$3"
  local log_output
  log_output=$(log_since_marker "$label")

  if echo "$log_output" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}PASS${NC}: $description"
    echo "        (matched: $pattern)"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${NC}: $description"
    echo "        Expected pattern: $pattern"
    echo "        --- Log output since marker ---"
    echo "$log_output" | head -10
    echo "        ---"
    ((FAIL++))
  fi
}

assert_log_not_contains() {
  local label="$1"
  local pattern="$2"
  local description="$3"
  local log_output
  log_output=$(log_since_marker "$label")

  if echo "$log_output" | grep -qE "$pattern"; then
    echo -e "  ${RED}FAIL${NC}: $description"
    echo "        Pattern should NOT appear: $pattern"
    echo "        --- Log output since marker ---"
    echo "$log_output" | head -10
    echo "        ---"
    ((FAIL++))
  else
    echo -e "  ${GREEN}PASS${NC}: $description"
    echo "        (correctly absent: $pattern)"
    ((PASS++))
  fi
}

assert_exit_code() {
  local actual="$1"
  local expected="$2"
  local description="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo -e "  ${GREEN}PASS${NC}: $description (exit=$actual)"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${NC}: $description (expected exit=$expected, got exit=$actual)"
    ((FAIL++))
  fi
}

cleanup_locks() {
  find "$LOCK_DIR" -name 'hook.lock.*' -delete 2>/dev/null || true
}

# Save and restore state
save_state() {
  cp "$LOCK_DIR/state.json" "$LOCK_DIR/state.json.bak" 2>/dev/null || true
}

restore_state() {
  if [ -f "$LOCK_DIR/state.json.bak" ]; then
    cp "$LOCK_DIR/state.json.bak" "$LOCK_DIR/state.json"
    rm -f "$LOCK_DIR/state.json.bak"
  fi
}

# Hide project-local config so it doesn't override global state during tests
hide_local_config() {
  local local_file
  local_file="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/claude-slack.local.md"
  if [ -f "$local_file" ]; then
    cp "$local_file" "${local_file}.test-bak"
    rm -f "$local_file"
    HIDDEN_LOCAL_CONFIG="$local_file"
  fi
}

restore_local_config() {
  if [ -n "${HIDDEN_LOCAL_CONFIG:-}" ] && [ -f "${HIDDEN_LOCAL_CONFIG}.test-bak" ]; then
    mv "${HIDDEN_LOCAL_CONFIG}.test-bak" "$HIDDEN_LOCAL_CONFIG"
    HIDDEN_LOCAL_CONFIG=""
  fi
}

should_run() {
  local test_num="$1"
  # If no arguments given, run all
  if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
    return 0
  fi
  for t in "${SELECTED_TESTS[@]}"; do
    if [ "$t" = "$test_num" ]; then
      return 0
    fi
  done
  return 1
}

# -------------------------------------------------------------------
# Parse arguments: which tests to run
# -------------------------------------------------------------------

SELECTED_TESTS=()
if [ $# -gt 0 ]; then
  SELECTED_TESTS=("$@")
  echo -e "${CYAN}Running selected tests: ${SELECTED_TESTS[*]}${NC}"
else
  echo -e "${CYAN}Running all tests${NC}"
fi

echo "Script: $SCRIPT"
echo "Log:    $LOG"
echo ""

# Ensure the script exists
if [ ! -f "$SCRIPT" ]; then
  echo -e "${RED}ERROR: $SCRIPT not found${NC}"
  exit 1
fi

# Clean up any stale locks before starting
cleanup_locks

# Save original state
save_state

# Rotate the debug log so old entries do not pollute test assertions.
# The old log is preserved as debug.log.prev for reference.
if [ -f "$LOG" ]; then
  cp "$LOG" "${LOG}.prev"
  : > "$LOG"
  echo "[TEST] ======== LOG CLEARED FOR TEST RUN $(date -u +%Y-%m-%dT%H:%M:%SZ) ========" >> "$LOG"
fi

# Ensure enabled for most tests
echo '{"enabled": true}' > "$LOCK_DIR/state.json"


# ===================================================================
# TEST 1: Valid permission-request posts to Slack (WILL POST)
# ===================================================================
if should_run 1; then
  separator
  echo -e "${YELLOW}TEST 1: Valid permission-request -> posts to Slack${NC}"
  echo -e "${YELLOW}  WARNING: This WILL post a message to Slack.${NC}"
  echo -e "${YELLOW}  The process will be killed after 10s (it polls for a reply).${NC}"
  log_marker "TEST1"
  cleanup_locks

  # Run in background with timeout; capture stdout
  STDOUT_FILE=$(mktemp /tmp/test1-stdout.XXXXXX)
  echo '{
    "tool_name": "Bash",
    "tool_input": {"command": "echo test-hooks.sh TEST1 -- ignore this", "description": "Test hook integration"},
    "session_id": "test-hook-00000001"
  }' | timeout 10 node "$SCRIPT" hook permission-request > "$STDOUT_FILE" 2>&1 || true

  # Give a moment for log writes
  sleep 1

  assert_log_contains "TEST1" "hookPermissionRequest: start" \
    "Handler started"
  assert_log_contains "TEST1" "hookPermissionRequest: stdin length=" \
    "Stdin was read"
  # It should NOT be rejected
  assert_log_not_contains "TEST1" "REJECTED" \
    "Input was not rejected"
  # It should start polling (which means the Slack post succeeded)
  assert_log_contains "TEST1" "pollForApproval: start polling" \
    "Slack message posted and polling began"

  STDOUT_CONTENT=$(cat "$STDOUT_FILE")
  rm -f "$STDOUT_FILE"
  echo "  stdout: ${STDOUT_CONTENT:-(empty, expected since killed before reply)}"
  cleanup_locks
fi


# ===================================================================
# TEST 2: Error object is REJECTED (will NOT post)
# ===================================================================
if should_run 2; then
  separator
  echo -e "${CYAN}TEST 2: Error object -> REJECTED (no Slack post)${NC}"
  log_marker "TEST2"
  cleanup_locks

  EXIT_CODE=0
  echo '{"type":"error","error":{"type":"invalid_request_error","message":"tool_use ids must be unique within a single request"}}' \
    | node "$SCRIPT" hook permission-request 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST2" "hookPermissionRequest: start" \
    "Handler started"
  assert_log_contains "TEST2" "REJECTED invalid input" \
    "Input was rejected as invalid"
  assert_log_not_contains "TEST2" "pollForReply" \
    "No Slack post was attempted"
fi


# ===================================================================
# TEST 3: Notification with error message is REJECTED (will NOT post)
# ===================================================================
if should_run 3; then
  separator
  echo -e "${CYAN}TEST 3: Notification with error message -> REJECTED (no Slack post)${NC}"
  log_marker "TEST3"

  EXIT_CODE=0
  echo '{"session_id":"test-hook-00000003","message":"API Error: 400 {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"tool_use ids must be unique\"}}"}' \
    | node "$SCRIPT" hook notification 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST3" "hookNotification: start" \
    "Handler started"
  assert_log_contains "TEST3" "REJECTED error message" \
    "Error message was rejected"
  assert_log_not_contains "TEST3" "posted successfully" \
    "No Slack post was attempted"
fi


# ===================================================================
# TEST 4: Notification with normal message posts to Slack (WILL POST)
# ===================================================================
if should_run 4; then
  separator
  echo -e "${YELLOW}TEST 4: Notification with normal message -> posts to Slack${NC}"
  echo -e "${YELLOW}  WARNING: This WILL post a message to Slack.${NC}"
  log_marker "TEST4"

  EXIT_CODE=0
  echo '{"session_id":"test-hook-00000004","message":"[test-hooks.sh TEST4] Claude Code is waiting for input -- please ignore"}' \
    | node "$SCRIPT" hook notification 2>&1 || EXIT_CODE=$?

  sleep 1

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST4" "hookNotification: start" \
    "Handler started"
  assert_log_not_contains "TEST4" "REJECTED" \
    "Input was not rejected"
  assert_log_contains "TEST4" "posted successfully" \
    "Message was posted to Slack"
fi


# ===================================================================
# TEST 5: Concurrent lock - second permission-request retries
# ===================================================================
if should_run 5; then
  separator
  echo -e "${CYAN}TEST 5: Concurrent lock -> second process retries (no Slack post)${NC}"
  echo -e "  Strategy: create a directory where the lock file should be,"
  echo -e "  making acquireLock fail reliably. Verify retry log messages."
  log_marker "TEST5"
  cleanup_locks

  # Create a directory at the lock path — acquireLock cannot unlink or
  # overwrite a directory, so it reliably returns false on every attempt.
  mkdir -p "$LOCK_DIR/hook.lock.permission"

  EXIT_CODE=0
  echo '{
    "tool_name": "Bash",
    "tool_input": {"command": "echo concurrent-test"},
    "session_id": "test-hook-00000005"
  }' | timeout 12 node "$SCRIPT" hook permission-request 2>&1 || EXIT_CODE=$?

  sleep 0.5

  # Clean up the directory
  rmdir "$LOCK_DIR/hook.lock.permission" 2>/dev/null || rm -rf "$LOCK_DIR/hook.lock.permission"

  assert_log_contains "TEST5" "hookPermissionRequest: start" \
    "Handler started"
  assert_log_contains "TEST5" "waiting for lock" \
    "Retry mechanism triggered"
  assert_log_contains "TEST5" "lock retry attempt" \
    "At least one retry attempt logged"
  assert_log_not_contains "TEST5" "pollForApproval" \
    "No Slack post was attempted"

  cleanup_locks
fi


# ===================================================================
# TEST 6: AskUserQuestion with invalid data is REJECTED (will NOT post)
# ===================================================================
if should_run 6; then
  separator
  echo -e "${CYAN}TEST 6: AskUserQuestion with invalid data -> REJECTED (no Slack post)${NC}"
  log_marker "TEST6"
  cleanup_locks

  # Missing questions array - should be rejected
  EXIT_CODE=0
  echo '{
    "tool_name": "AskUserQuestion",
    "tool_input": {"not_questions": "this is wrong"},
    "session_id": "test-hook-00000006"
  }' | node "$SCRIPT" hook ask-user-question 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST6" "hookAskUserQuestion: start" \
    "Handler started"
  assert_log_contains "TEST6" "REJECTED invalid input" \
    "Invalid AskUserQuestion was rejected"
  assert_log_not_contains "TEST6" "pollForReply" \
    "No Slack post was attempted"
fi


# ===================================================================
# TEST 7: Disabled state - all hooks exit immediately (will NOT post)
# ===================================================================
if should_run 7; then
  separator
  echo -e "${CYAN}TEST 7: Disabled state -> all hooks exit immediately (no Slack post)${NC}"
  log_marker "TEST7"
  cleanup_locks

  # Hide local config (its enabled:true overrides state.json)
  hide_local_config

  # Disable the integration
  echo '{"enabled": false}' > "$LOCK_DIR/state.json"

  # 7a: permission-request while disabled
  EXIT_CODE=0
  echo '{
    "tool_name": "Bash",
    "tool_input": {"command": "echo should-not-post"},
    "session_id": "test-hook-00000007a"
  }' | node "$SCRIPT" hook permission-request 2>&1 || EXIT_CODE=$?

  assert_exit_code "$EXIT_CODE" 0 \
    "permission-request exited cleanly when disabled"

  # 7b: notification while disabled
  EXIT_CODE=0
  echo '{"session_id":"test-hook-00000007b","message":"should not post"}' \
    | node "$SCRIPT" hook notification 2>&1 || EXIT_CODE=$?

  assert_exit_code "$EXIT_CODE" 0 \
    "notification exited cleanly when disabled"

  # 7c: ask-user-question while disabled
  EXIT_CODE=0
  echo '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"test?"}]},"session_id":"test-hook-00000007c"}' \
    | node "$SCRIPT" hook ask-user-question 2>&1 || EXIT_CODE=$?

  assert_exit_code "$EXIT_CODE" 0 \
    "ask-user-question exited cleanly when disabled"

  sleep 0.5

  assert_log_contains "TEST7" "disabled, exit" \
    "All hooks logged disabled state"
  assert_log_not_contains "TEST7" "pollForReply" \
    "No Slack post was attempted"
  assert_log_not_contains "TEST7" "posted successfully" \
    "No Slack post was made"

  # Re-enable for remaining tests
  echo '{"enabled": true}' > "$LOCK_DIR/state.json"

  # Restore local config
  restore_local_config
fi


# ===================================================================
# TEST 8: Malformed JSON -> parse error, no post (will NOT post)
# ===================================================================
if should_run 8; then
  separator
  echo -e "${CYAN}TEST 8: Malformed JSON -> parse error (no Slack post)${NC}"
  log_marker "TEST8"
  cleanup_locks

  EXIT_CODE=0
  echo 'this is not json at all {{{' \
    | node "$SCRIPT" hook permission-request 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly despite bad JSON"
  assert_log_contains "TEST8" "stdin parse error" \
    "Parse error was logged"
  assert_log_not_contains "TEST8" "pollForReply" \
    "No Slack post was attempted"
fi


# ===================================================================
# TEST 9: Error inside tool_input is REJECTED (will NOT post)
# ===================================================================
if should_run 9; then
  separator
  echo -e "${CYAN}TEST 9: Error object in tool_input -> REJECTED (no Slack post)${NC}"
  log_marker "TEST9"
  cleanup_locks

  EXIT_CODE=0
  echo '{
    "tool_name": "Bash",
    "tool_input": {"type": "error", "error": {"message": "something went wrong"}},
    "session_id": "test-hook-00000009"
  }' | node "$SCRIPT" hook permission-request 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST9" "REJECTED invalid input" \
    "Error in tool_input was rejected"
  assert_log_not_contains "TEST9" "pollForReply" \
    "No Slack post was attempted"
fi


# ===================================================================
# TEST 10: Notification with error object (not just message) is REJECTED
# ===================================================================
if should_run 10; then
  separator
  echo -e "${CYAN}TEST 10: Notification error object -> REJECTED (no Slack post)${NC}"
  log_marker "TEST10"

  EXIT_CODE=0
  echo '{"type":"error","error":{"type":"invalid_request_error","message":"something bad"}}' \
    | node "$SCRIPT" hook notification 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST10" "REJECTED error object" \
    "Error object in notification was rejected"
  assert_log_not_contains "TEST10" "posted successfully" \
    "No Slack post was made"
fi


# ===================================================================
# TEST 11: Notification with rate_limit_error message is REJECTED
# ===================================================================
if should_run 11; then
  separator
  echo -e "${CYAN}TEST 11: Notification with rate_limit_error -> REJECTED (no Slack post)${NC}"
  log_marker "TEST11"

  EXIT_CODE=0
  echo '{"session_id":"test-hook-00000011","message":"rate_limit_error: too many requests"}' \
    | node "$SCRIPT" hook notification 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST11" "REJECTED error message" \
    "rate_limit_error message was rejected"
fi


# ===================================================================
# TEST 12: AskUserQuestion with error object is REJECTED
# ===================================================================
if should_run 12; then
  separator
  echo -e "${CYAN}TEST 12: AskUserQuestion error object -> REJECTED (no Slack post)${NC}"
  log_marker "TEST12"
  cleanup_locks

  EXIT_CODE=0
  echo '{"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}' \
    | node "$SCRIPT" hook ask-user-question 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST12" "REJECTED invalid input" \
    "Error object was rejected in ask-user-question"
fi


# ===================================================================
# TEST 13: Permission-request with empty tool_name is REJECTED
# ===================================================================
if should_run 13; then
  separator
  echo -e "${CYAN}TEST 13: Empty tool_name -> REJECTED (no Slack post)${NC}"
  log_marker "TEST13"
  cleanup_locks

  EXIT_CODE=0
  echo '{
    "tool_name": "",
    "tool_input": {"command": "echo hello"},
    "session_id": "test-hook-00000013"
  }' | node "$SCRIPT" hook permission-request 2>&1 || EXIT_CODE=$?

  sleep 0.5

  assert_exit_code "$EXIT_CODE" 0 \
    "Exited cleanly (exit 0)"
  assert_log_contains "TEST13" "REJECTED invalid input" \
    "Empty tool_name was rejected"
fi


# ===================================================================
# Summary
# ===================================================================

separator
echo ""

# Restore original state
restore_state
cleanup_locks

TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC} out of ${TOTAL} assertions"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}SOME TESTS FAILED${NC}"
  echo ""
  echo "Debug log (last 50 lines):"
  echo "  tail -50 $LOG"
  echo ""
  echo "Full debug log since test run:"
  echo "  grep -A1000 'TEST.*========' $LOG | less"
  exit 1
else
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  echo ""
  echo "To review debug log:"
  echo "  tail -100 $LOG"
  exit 0
fi
