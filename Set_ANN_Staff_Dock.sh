#!/bin/zsh

set -euo pipefail

readonly STAT="/usr/bin/stat"
readonly DSCL="/usr/bin/dscl"
readonly AWK="/usr/bin/awk"
readonly ID="/usr/bin/id"
readonly LAUNCHCTL="/bin/launchctl"
readonly SUDO="/usr/bin/sudo"
readonly KILLALL="/usr/bin/killall"

typeset -a DOCK_APPS=(
  "/Applications/Google Chrome.app"
  "/Applications/zoom.us.app"
  "/Applications/Microsoft Teams.app"
  "/Applications/Microsoft Outlook.app"
  "/Applications/Microsoft Word.app"
  "/Applications/Self Service.app"
)

log() {
  /bin/echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*"
}

get_dockutil() {
  local candidate

  for candidate in "/usr/local/bin/dockutil" "/opt/homebrew/bin/dockutil"; do
    if [[ -x "$candidate" ]]; then
      /bin/echo "$candidate"
      return 0
    fi
  done

  if command -v dockutil >/dev/null 2>&1; then
    command -v dockutil
    return 0
  fi

  return 1
}

get_logged_in_user() {
  local user
  user=$("$STAT" -f "%Su" /dev/console)

  if [[ -z "$user" || "$user" == "root" || "$user" == "loginwindow" ]]; then
    return 1
  fi

  /bin/echo "$user"
}

get_user_home() {
  local user="$1"
  "$DSCL" . -read "/Users/${user}" NFSHomeDirectory | "$AWK" '{print $2}'
}

run_as_user() {
  if [[ "$EUID" -eq 0 ]]; then
    "$LAUNCHCTL" asuser "$logged_in_uid" "$SUDO" -u "$logged_in_user" "$@"
  else
    "$@"
  fi
}

validate_apps() {
  local app_path
  local missing_count=0

  for app_path in "${DOCK_APPS[@]}"; do
    if [[ ! -d "$app_path" ]]; then
      log "Missing required app: $app_path"
      missing_count=$((missing_count + 1))
    fi
  done

  if [[ "$missing_count" -gt 0 ]]; then
    log "One or more required apps are missing. Exiting before changing the Dock."
    exit 1
  fi
}

main() {
  local dockutil_bin
  local dock_plist
  local user_home
  local app_path

  if ! dockutil_bin=$(get_dockutil); then
    log "dockutil was not found. Install dockutil before running this script."
    exit 1
  fi

  if ! logged_in_user=$(get_logged_in_user); then
    log "No active console user found. Exiting without changes."
    exit 1
  fi

  logged_in_uid=$("$ID" -u "$logged_in_user")
  user_home=$(get_user_home "$logged_in_user")
  dock_plist="${user_home}/Library/Preferences/com.apple.dock.plist"

  validate_apps

  log "Configuring Dock for $logged_in_user"
  run_as_user "$dockutil_bin" --remove all --no-restart "$dock_plist"

  for app_path in "${DOCK_APPS[@]}"; do
    log "Adding $app_path"
    run_as_user "$dockutil_bin" --add "$app_path" --position end --no-restart "$dock_plist"
  done

  run_as_user "$KILLALL" cfprefsd >/dev/null 2>&1 || true
  run_as_user "$KILLALL" Dock >/dev/null 2>&1 || true
  log "Dock configuration complete."
}

main "$@"
