#!/bin/sh
# Shared by rpcd and init. Validate kernel ancestry and PID start time;
# an inherited environment flag alone never grants ownership.
hv_lock_identity() {
	[ -r "/proc/$1/stat" ] || return 1
	awk '{ sub(/^.*\) /, ""); print $20 }' "/proc/$1/stat"
}

hv_lock_nested() {
	local owner born current actual parent
	[ "${HOMEVPN_SERVICE_LOCK_HELD:-}" = 1 ] || return 1
	read -r owner born < /var/lock/homevpn-service.lock/owner 2>/dev/null || return 1
	case "$owner:$born" in *[!0-9:]*|:*) return 1;; esac
	actual="$(hv_lock_identity "$owner")" || return 1
	[ "$actual" = "$born" ] || return 1
	current=$$
	while [ "$current" -gt 1 ]; do
		[ "$current" != "$owner" ] || return 0
		parent="$(awk '{ sub(/^.*\) /, ""); print $2 }' "/proc/$current/stat" 2>/dev/null)" || return 1
		case "$parent" in ''|*[!0-9]*) return 1;; esac
		[ "$parent" != "$current" ] || return 1
		current="$parent"
	done
	return 1
}

hv_lock_release() {
	local owner born
	read -r owner born < /var/lock/homevpn-service.lock/owner 2>/dev/null || return 0
	[ "$owner" = "$$" ] && [ "$born" = "$(hv_lock_identity "$$")" ] || return 0
	rm -f /var/lock/homevpn-service.lock/owner
	rmdir /var/lock/homevpn-service.lock
}

hv_with_lock() {
	if hv_lock_nested; then "$@"; return $?; fi
	mkdir /var/lock/homevpn-service.lock 2>/dev/null || {
		echo 'HomeVPN service is busy; retry shortly. If interrupted, inspect lock owner before manual recovery.' >&2; return 1;
	}
	local born rc
	born="$(hv_lock_identity "$$")" || { rmdir /var/lock/homevpn-service.lock; return 1; }
	printf '%s %s\n' "$$" "$born" > /var/lock/homevpn-service.lock/owner || { rmdir /var/lock/homevpn-service.lock; return 1; }
	trap 'hv_lock_release' EXIT
	trap 'exit 1' INT TERM
	export HOMEVPN_SERVICE_LOCK_HELD=1
	if "$@"; then rc=0; else rc=$?; fi
	unset HOMEVPN_SERVICE_LOCK_HELD
	trap - EXIT INT TERM
	hv_lock_release
	return "$rc"
}
