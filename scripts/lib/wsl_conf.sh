# shellcheck shell=bash

if [[ "${_DOTFILES_WSL_CONF_LOADED:-0}" == 1 ]]; then
	return 0
fi
_DOTFILES_WSL_CONF_LOADED=1

wsl_conf_has_setting() {
	local conf="$1" section="$2" key="$3" expected="$4"
	awk -v wanted_section="$section" -v wanted_key="$key" -v wanted_value="$expected" '
		function trim(value) { sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value); return value }
		/^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
			current=$0
			gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", current)
			next
		}
		current == wanted_section && index($0, "=") {
			line=$0
			sub(/[[:space:]]*[#;].*$/, "", line)
			equals=index(line, "=")
			name=trim(substr(line, 1, equals - 1))
			value=trim(substr(line, equals + 1))
			if (name == wanted_key && value == wanted_value) found=1
		}
		END { exit(found ? 0 : 1) }
	' "$conf"
}

wsl_conf_set_setting() {
	local conf="$1" section="$2" key="$3" value="$4"
	awk -v wanted_section="$section" -v wanted_key="$key" -v wanted_value="$value" '
		function trim(text) { sub(/^[[:space:]]+/, "", text); sub(/[[:space:]]+$/, "", text); return text }
		function finish_section() {
			if (current == wanted_section && !setting_written) {
				print wanted_key "=" wanted_value
				setting_written=1
			}
		}
		/^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
			finish_section()
			current=$0
			gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", current)
			if (current == wanted_section) section_seen=1
			print
			next
		}
		current == wanted_section && index($0, "=") {
			line=$0
			sub(/[[:space:]]*[#;].*$/, "", line)
			equals=index(line, "=")
			name=trim(substr(line, 1, equals - 1))
			if (name == wanted_key) {
				if (!setting_written) print wanted_key "=" wanted_value
				setting_written=1
				next
			}
		}
		{ print }
		END {
			finish_section()
			if (!section_seen) {
				if (NR > 0) print ""
				print "[" wanted_section "]"
				print wanted_key "=" wanted_value
			}
		}
	' "$conf"
}

wsl_conf_render_required() {
	local conf="$1" tmp
	tmp="$(mktemp)" || return 1
	if [[ -f "$conf" ]]; then
		wsl_conf_set_setting "$conf" boot systemd true >"$tmp" || {
			rm -f "$tmp"
			return 1
		}
	else
		: >"$tmp"
		wsl_conf_set_setting "$tmp" boot systemd true >"${tmp}.next" || {
			rm -f "$tmp" "${tmp}.next"
			return 1
		}
		mv "${tmp}.next" "$tmp"
	fi
	wsl_conf_set_setting "$tmp" interop appendWindowsPath true
	local rc=$?
	rm -f "$tmp"
	return "$rc"
}
