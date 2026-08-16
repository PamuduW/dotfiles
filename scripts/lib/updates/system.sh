# shellcheck shell=bash
# --- apt ---
apt_upgradable_count() {
	if ! command -v apt-get >/dev/null 2>&1; then
		echo 0
		return
	fi
	local count
	# Use cached indices for the pre-confirmation preview; refresh during apply.
	count="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || true)"
	echo "${count:-0}"
}

check_apt() {
	local count installed available action upgradable=0
	count="$(apt_upgradable_count)"
	if command -v apt-get >/dev/null 2>&1; then
		installed="system packages"
	else
		installed="$NOT_INSTALLED"
	fi
	if [[ "$count" -gt 0 ]]; then
		available="${count} package(s) (cached)"
		action="upgrade"
		upgradable=1
	else
		available="none (cached)"
		action="refresh on apply"
	fi
	printf '%s|%s|%s|%s\n' "apt packages" "$installed" "$available" "$action"
	[[ $upgradable -eq 1 ]]
}
