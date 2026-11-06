# shellcheck shell=bash

# Activate a staged file or tree, retaining the previous install until its
# optional command link and version stamp have both been published.
activate_managed_install() (
	local staged="$1" destination="$2" link="$3" stamp="$4" executable="$5" version="$6"
	local staged_device destination_device target backup link_tmp='' stamp_tmp='' started=0 committed=0 had_destination=0
	local had_link=0 had_stamp=0
	[[ ! -L "$destination" && ! -d "$link" && ! -d "$stamp" ]] || return 1
	if [[ -e "$destination" ]]; then
		had_destination=1
		[[ -d "$staged" && -d "$destination" || ! -d "$staged" && ! -d "$destination" ]] || return 1
	fi
	staged_device="$(stat -c '%d' -- "$staged")" || return 1
	destination_device="$(stat -c '%d' -- "$(dirname -- "$destination")")" || return 1
	[[ "$staged_device" == "$destination_device" ]] || return 1
	backup="$(mktemp -d "$(dirname -- "$destination")/.activation.XXXXXX")" || return 1

	_activation_finish() {
		local rc="$1" failed=0
		trap - EXIT
		if ((started && !committed)); then
			if [[ -e "$backup/previous" ]]; then
				rm -rf -- "$destination" || failed=1
				mv -T -- "$backup/previous" "$destination" || failed=1
			elif ((!had_destination)); then
				rm -rf -- "$destination" || failed=1
			fi
			if [[ -n "$link" ]]; then
				if ((had_link)); then
					cp -aT --remove-destination -- "$backup/link" "$link" || failed=1
				else
					rm -f -- "$link" || failed=1
				fi
			fi
			if [[ -n "$stamp" ]]; then
				if ((had_stamp)); then
					cp -aT --remove-destination -- "$backup/stamp" "$stamp" || failed=1
				else
					rm -f -- "$stamp" || failed=1
				fi
			fi
		fi
		rm -rf -- "$staged" || failed=1
		[[ -z "$link_tmp" ]] || rm -f -- "$link_tmp" || failed=1
		[[ -z "$stamp_tmp" ]] || rm -f -- "$stamp_tmp" || failed=1
		if ((failed)); then
			printf '  Installation recovery needs attention; previous files retained at %s\n' "$backup" >&2
			rc=1
		else
			rm -rf -- "$backup"
		fi
		exit "$rc"
	}
	trap '_activation_finish "$?"' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM

	if [[ -n "$link" ]]; then
		if [[ -e "$link" || -L "$link" ]]; then
			cp -a -- "$link" "$backup/link" || return $?
			had_link=1
		fi
		link_tmp="$(mktemp "${link}.XXXXXX")" || return 1
		target="$destination"
		[[ -z "$executable" ]] || target="$destination/$executable"
		ln -sfnT -- "$target" "$link_tmp" || return $?
	fi
	if [[ -n "$stamp" ]]; then
		install -d -m 0755 "$(dirname -- "$stamp")" || return $?
		if [[ -e "$stamp" || -L "$stamp" ]]; then
			cp -a -- "$stamp" "$backup/stamp" || return $?
			had_stamp=1
		fi
		stamp_tmp="$(mktemp "${stamp}.XXXXXX")" || return 1
		printf '%s\n' "$version" >"$stamp_tmp" || return $?
		chmod 0644 "$stamp_tmp" || return $?
	fi
	started=1
	if ((had_destination)); then
		mv -T -- "$destination" "$backup/previous" || return $?
	fi
	mv -T -- "$staged" "$destination" || return $?
	[[ -z "$link" ]] || mv -fT -- "$link_tmp" "$link" || return $?
	[[ -z "$stamp" ]] || mv -fT -- "$stamp_tmp" "$stamp" || return $?
	committed=1
	_activation_finish 0
)
