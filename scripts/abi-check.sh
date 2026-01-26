#!/usr/bin/env bash
set -e

# ABI Stability Check Script
# Ensures event signatures never change and function signatures follow stability rules
#
# Usage: abi-check.sh <check|generate>
#
# Run from the package directory (e.g., packages/coins/)
# Automatically discovers all interfaces (files starting with 'I') in src/
# The .abi-stability snapshot file will be stored in that directory.
#
# Rules:
#   Events:
#     - No modifications allowed (can only add new events)
#     - Removal requires @custom:deprecated annotation first
#
#   Functions:
#     - Can add new functions
#     - Can rename parameters (doesn't affect selector)
#     - Cannot rename functions (creates confusion)
#     - Cannot change parameter types (changes selector)
#     - Can only remove functions marked with @custom:deprecated
#
# Deprecation format (NatSpec):
#   /// @custom:deprecated Use newFunction() instead. Will be removed in vX.Y.
#   function oldFunction(...) external;

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <check|generate>"
  exit 1
fi

COMMAND=$1

# Auto-discover interfaces: find all .sol files starting with 'I' in src/
discover_interfaces() {
  local interfaces=""
  for file in $(find src -name 'I*.sol' -type f 2>/dev/null | sort); do
    local name=$(basename "$file" .sol)
    interfaces="$interfaces $name"
  done
  echo "$interfaces"
}

# Find deprecated functions by parsing source files for @custom:deprecated
# Returns: "InterfaceName:functionName" pairs
find_deprecated() {
  local deprecated=""
  for file in $(find src -name 'I*.sol' -type f 2>/dev/null | sort); do
    local interface_name=$(basename "$file" .sol)
    # Look for @custom:deprecated followed by a function declaration
    # This regex finds deprecated markers and captures the next function name
    while IFS= read -r func_name; do
      [[ -n "$func_name" ]] && deprecated="$deprecated ${interface_name}:${func_name}"
    done < <(grep -B1 -E "^\s*function\s+\w+" "$file" 2>/dev/null | \
             grep -A1 "@custom:deprecated" | \
             grep -oE "function\s+\w+" | \
             sed 's/function //' || true)
  done
  echo "$deprecated"
}

CONTRACTS=$(discover_interfaces)

if [[ -z "${CONTRACTS// /}" ]]; then
  echo "No interfaces found in src/ (files starting with 'I*.sol')"
  exit 1
fi

echo "Discovered interfaces:$CONTRACTS"

generate() {
  local file=$1
  local mode=$2

  echo "=======================" >"$file"
  echo "👁👁 ABI STABILITY snapshot 👁👁" >>"$file"
  echo "=======================" >>"$file"

  # Record deprecated functions
  local deprecated=$(find_deprecated)
  echo -e "\n===============================" >>"$file"
  echo "DEPRECATED FUNCTIONS" >>"$file"
  echo -e "===============================\n" >>"$file"
  if [[ -n "${deprecated// /}" ]]; then
    for item in $deprecated; do
      echo "$item" >>"$file"
    done
  else
    echo "(none)" >>"$file"
  fi

  # Record interface ABIs
  for contract in $CONTRACTS; do
    echo -e "\n===============================" >>"$file"
    echo "➡ $contract" >>"$file"
    echo -e "===============================\n" >>"$file"

    echo "--- EVENTS ---" >>"$file"
    FOUNDRY_PROFILE=dev forge inspect "$contract" events 2>/dev/null >>"$file" || echo "(no events)" >>"$file"

    echo -e "\n--- FUNCTIONS ---" >>"$file"
    FOUNDRY_PROFILE=dev forge inspect "$contract" methods 2>/dev/null >>"$file" || echo "(no methods)" >>"$file"
  done

  if [[ $mode == "generate" ]]; then
    echo "✅ ABI snapshot stored at $file"
    if [[ -n "${deprecated// /}" ]]; then
      echo ""
      echo "📋 Deprecated functions found:"
      for item in $deprecated; do
        echo "   - $item"
      done
      echo ""
      echo "These functions can be removed in a future version."
    fi
  fi
}

# Extract deprecated functions from snapshot file
get_deprecated_from_snapshot() {
  local file=$1
  local in_deprecated=0
  local deprecated=""

  while IFS= read -r line; do
    if [[ "$line" == "DEPRECATED FUNCTIONS" ]]; then
      in_deprecated=1
      continue
    fi
    if [[ $in_deprecated -eq 1 ]]; then
      if [[ "$line" == "==============================="* ]] || [[ "$line" == "➡"* ]]; then
        break
      fi
      if [[ "$line" != "(none)" && -n "$line" && "$line" != "" ]]; then
        deprecated="$deprecated $line"
      fi
    fi
  done <"$file"

  echo "$deprecated"
}

check_abi_changes() {
  local old_file=$1
  local new_file=$2

  # Get deprecated functions from old snapshot (these are allowed to be removed)
  local old_deprecated=$(get_deprecated_from_snapshot "$old_file")
  echo "Previously deprecated:${old_deprecated:- (none)}"

  # Extract event topics
  local old_events=$(grep -E "^\| .+\| 0x[a-f0-9]{64}" "$old_file" 2>/dev/null | awk '{print $2 " " $4}' | sort || true)
  local new_events=$(grep -E "^\| .+\| 0x[a-f0-9]{64}" "$new_file" 2>/dev/null | awk '{print $2 " " $4}' | sort || true)

  # Extract function selectors
  local old_funcs=$(grep -E "^\| .+\| [a-f0-9]{8} +\|?$" "$old_file" 2>/dev/null | awk '{print $2 " " $4}' | sort || true)
  local new_funcs=$(grep -E "^\| .+\| [a-f0-9]{8} +\|?$" "$new_file" 2>/dev/null | awk '{print $2 " " $4}' | sort || true)

  local has_error=0
  local has_warning=0

  echo ""
  echo "Checking event stability..."

  # Find events with changed signatures (BREAKING)
  local old_event_names=$(echo "$old_events" | awk '{print $1}' | sed 's/(.*//' | sort -u)
  for event_name in $old_event_names; do
    [[ -z "$event_name" ]] && continue
    local old_topic=$(echo "$old_events" | grep "^${event_name}(" | awk '{print $2}' | head -1)
    local new_topic=$(echo "$new_events" | grep "^${event_name}(" | awk '{print $2}' | head -1)

    if [[ -n "$old_topic" && -n "$new_topic" && "$old_topic" != "$new_topic" ]]; then
      echo "❌ ERROR: Event '$event_name' signature changed!"
      echo "   Old topic: $old_topic"
      echo "   New topic: $new_topic"
      echo "   This is a BREAKING ABI change. Create a new event instead (e.g., ${event_name}V2)"
      has_error=1
    fi
  done

  # Find removed events
  for event_name in $old_event_names; do
    [[ -z "$event_name" ]] && continue
    local old_sig=$(echo "$old_events" | grep "^${event_name}(" | awk '{print $1}' | head -1)
    local new_sig=$(echo "$new_events" | grep "^${event_name}(" | awk '{print $1}' | head -1)

    if [[ -n "$old_sig" && -z "$new_sig" ]]; then
      echo "❌ ERROR: Event '$event_name' was removed without deprecation"
      echo "   Events should be marked @custom:deprecated before removal"
      has_error=1
    fi
  done

  echo ""
  echo "Checking function stability..."

  # Find functions where selector changed (signature was modified - BREAKING)
  local old_func_names=$(echo "$old_funcs" | awk '{print $1}' | sed 's/(.*//' | sort -u)
  for func_name in $old_func_names; do
    [[ -z "$func_name" ]] && continue
    local old_sigs=$(echo "$old_funcs" | grep -F "${func_name}(" || true)
    local new_sigs=$(echo "$new_funcs" | grep -F "${func_name}(" || true)

    while IFS= read -r old_line; do
      [[ -z "$old_line" ]] && continue
      local old_sig=$(echo "$old_line" | awk '{print $1}')
      local old_sel=$(echo "$old_line" | awk '{print $2}')

      # Use fixed string matching to avoid regex issues with [] brackets
      local new_sel=$(echo "$new_sigs" | grep -F "$old_sig " | awk '{print $2}' || true)

      if [[ -z "$new_sel" ]]; then
        local other_new=$(echo "$new_sigs" | grep -E " ${old_sel}$" || true)
        if [[ -n "$other_new" ]]; then
          echo "❌ ERROR: Function '$func_name' parameter types changed!"
          echo "   Old: $old_sig"
          echo "   New: $(echo "$other_new" | awk '{print $1}')"
          has_error=1
        fi
      fi
    done <<<"$old_sigs"
  done

  # Check for removed/renamed functions
  local new_func_names=$(echo "$new_funcs" | awk '{print $1}' | sed 's/(.*//' | sort -u)
  local removed_funcs=""
  local added_funcs=""

  for func_name in $old_func_names; do
    [[ -z "$func_name" ]] && continue
    if ! echo "$new_func_names" | grep -q "^${func_name}$"; then
      removed_funcs="$removed_funcs $func_name"
    fi
  done

  for func_name in $new_func_names; do
    [[ -z "$func_name" ]] && continue
    if ! echo "$old_func_names" | grep -q "^${func_name}$"; then
      added_funcs="$added_funcs $func_name"
    fi
  done

  # Check if removed functions were deprecated
  for func_name in $removed_funcs; do
    [[ -z "$func_name" ]] && continue
    # Check if this function was in the deprecated list (format: Interface:functionName)
    if echo "$old_deprecated" | grep -qF ":${func_name}"; then
      echo "✅ Function '$func_name' removed (was deprecated)"
    else
      echo "❌ ERROR: Function '$func_name' removed without deprecation!"
      echo "   Functions must be marked @custom:deprecated before removal."
      echo "   Add the annotation, regenerate snapshot, release, then remove in next version."
      has_error=1
    fi
  done

  # Warn about potential renames
  if [[ -n "${added_funcs// /}" ]]; then
    # Check if any added function looks like a rename of a removed one
    for removed in $removed_funcs; do
      [[ -z "$removed" ]] && continue
      for added in $added_funcs; do
        [[ -z "$added" ]] && continue
        # Simple heuristic: if names are similar (contain same root), warn
        if [[ "$removed" == *"$added"* ]] || [[ "$added" == *"$removed"* ]]; then
          echo "⚠️  WARNING: '$removed' removed and '$added' added - possible rename?"
          echo "   Renaming functions is not allowed. Use deprecation instead."
          has_warning=1
        fi
      done
    done
  fi

  echo ""
  if [[ $has_error -eq 1 ]]; then
    echo "❌ ABI stability check FAILED"
    echo ""
    echo "To fix:"
    echo "  1. For modified events/functions: Revert the change, create a new version instead"
    echo "  2. For removed items: First mark with @custom:deprecated, release, then remove"
    return 1
  elif [[ $has_warning -eq 1 ]]; then
    echo "⚠️  ABI stability check PASSED with warnings"
    echo "   Review the warnings above to ensure changes are intentional."
    return 0
  else
    echo "✅ ABI stability check PASSED"
    return 0
  fi
}

# Main
filename=.abi-stability
new_filename=.abi-stability.temp

case "$COMMAND" in
check)
  if [[ ! -f "$filename" ]]; then
    echo "No baseline ABI snapshot found at $filename"
    echo "Run with 'generate' first to create the baseline."
    exit 1
  fi

  echo "Generating current ABI snapshot..."
  generate "$new_filename" "check"

  if cmp -s "$filename" "$new_filename"; then
    echo "✅ ABI unchanged"
    rm "$new_filename"
    exit 0
  fi

  echo "ABI changes detected. Analyzing..."
  check_abi_changes "$filename" "$new_filename"
  result=$?
  rm "$new_filename"
  exit $result
  ;;
generate)
  generate "$filename" "generate"
  ;;
*)
  echo "Unknown command: $COMMAND"
  echo "Usage: $0 <check|generate>"
  exit 1
  ;;
esac
