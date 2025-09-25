#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2025 ImmortalWrt.org

NAME="homeproxy"

RESOURCES_DIR="/etc/$NAME/resources"
mkdir -p "$RESOURCES_DIR"

RUN_DIR="/var/run/$NAME"
LOG_PATH="$RUN_DIR/$NAME.log"
mkdir -p "$RUN_DIR"

log() {
	echo -e "$(date "+%Y-%m-%d %H:%M:%S") $*" >> "$LOG_PATH"
}

to_upper() {
	echo -e "$1" | tr "[a-z]" "[A-Z]"
}

check_list_update() {
	local LIST_FILE="$1"
	local REPO_NAME="$2"
	local REPO_BRANCH="$3"
	local REPO_FILE="$4"
	local LOCK_FILE="$RUN_DIR/update_resources-$LIST_FILE.lock"
	local GITHUB_TOKEN="$(uci -q get homeproxy.config.github_token)"

	exec 200>"$LOCK_FILE"
	if ! flock -n 200 &> "/dev/null"; then
		log "[$(to_upper "$LIST_FILE")] A task is already running."
		return 2
	fi

	local AUTH_HEADER=""
	[ -n "$GITHUB_TOKEN" ] && AUTH_HEADER="--header=Authorization: Bearer $GITHUB_TOKEN"

	local NEW_VER=$(curl -sL $AUTH_HEADER "https://api.github.com/repos/$REPO_NAME/releases/latest" | jsonfilter -e "@.tag_name")
	if [ -z "$NEW_VER" ]; then
		log "[$(to_upper "$LIST_FILE")] Failed to get the latest version, please retry later."

		return 1
	fi

	local OLD_VER=$(cat "$RESOURCES_DIR/$LIST_FILE.ver" 2>/dev/null || echo "NOT FOUND")
	if [ "$OLD_VER" = "$NEW_VER" ]; then
		log "[$(to_upper "$LIST_FILE")] Current version: $NEW_VER."
		log "[$(to_upper "$LIST_FILE")] You're already at the latest version."

		return 3
	else
		log "[$(to_upper "$LIST_FILE")] Local version: $OLD_VER, latest version: $NEW_VER."
	fi

	if ! curl -sL -o "$RUN_DIR/$REPO_FILE" "https://cdn.jsdelivr.net/gh/$REPO_NAME@$REPO_BRANCH/$REPO_FILE" || [ ! -s "$RUN_DIR/$REPO_FILE" ]; then
		rm -f "$RUN_DIR/$REPO_FILE"
		log "[$(to_upper "$LIST_FILE")] Update failed."

		return 1
	fi

	mv -f "$RUN_DIR/$REPO_FILE" "$RESOURCES_DIR/$LIST_FILE.${REPO_FILE##*.}"
	echo -e "$NEW_VER" > "$RESOURCES_DIR/$LIST_FILE.ver"
	log "[$(to_upper "$LIST_FILE")] Successfully updated."

	return 0
}

case "$1" in
"china_ip4")
	check_list_update "$1" "Loyalsoldier/surge-rules" "release" "cncidr.txt" && \
		sed -i "/IP-CIDR6,/d; s/IP-CIDR,//g" "$RESOURCES_DIR/china_ip4.txt"
	;;
"china_ip6")
	check_list_update "$1" "Loyalsoldier/surge-rules" "release" "cncidr.txt" && \
		sed -i "/IP-CIDR,/d; s/IP-CIDR6,//g" "$RESOURCES_DIR/china_ip6.txt"
	;;
"gfw_list")
	check_list_update "$1" "Loyalsoldier/surge-rules" "release" "gfw.txt" && \
		sed -i "s/^\.//g" "$RESOURCES_DIR/gfw_list.txt"
	;;
"china_list")
	check_list_update "$1" "Loyalsoldier/surge-rules" "release" "direct.txt" && \
		sed -i "s/^\.//g" "$RESOURCES_DIR/china_list.txt"
	;;
*)
	echo -e "Usage: $0 <china_ip4 / china_ip6 / gfw_list / china_list>"
	exit 1
	;;
esac