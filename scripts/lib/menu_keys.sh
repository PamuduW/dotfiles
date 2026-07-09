# shellcheck shell=bash
# Keyboard input decoder for interactive menus on /dev/tty.

_menu_keys_decode_escape_sequence() {
	local seq="$1"

	case "$seq" in
	'[A' | 'OA')
		printf '%s\n' 'up'
		;;
	'[B' | 'OB')
		printf '%s\n' 'down'
		;;
	'[C' | 'OC')
		printf '%s\n' 'right'
		;;
	'[D' | 'OD')
		printf '%s\n' 'left'
		;;
	'[5~')
		printf '%s\n' 'page_up'
		;;
	'[6~')
		printf '%s\n' 'page_down'
		;;
	*)
		printf '%s\n' 'ignore'
		;;
	esac
}

menu_read_key() {
	local key seq='' next

	IFS= read -rsn1 key </dev/tty || {
		printf '%s\n' 'confirm'
		return 0
	}

	case "$key" in
	$'\e')
		while IFS= read -rsn1 -t 0.01 next </dev/tty; do
			seq+="$next"
			((${#seq} >= 16)) && break
		done
		if [[ -z "$seq" ]]; then
			printf '%s\n' 'cancel'
		else
			_menu_keys_decode_escape_sequence "$seq"
		fi
		;;
	' ')
		printf '%s\n' 'toggle'
		;;
	'')
		printf '%s\n' 'confirm'
		;;
	a | A)
		printf '%s\n' 'all'
		;;
	n | N)
		printf '%s\n' 'none'
		;;
	q | Q | $'\003')
		printf '%s\n' 'cancel'
		;;
	*)
		printf '%s\n' 'ignore'
		;;
	esac
}
