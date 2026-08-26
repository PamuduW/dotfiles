# shellcheck shell=bash
# Keyboard input decoder for the shared terminal input adapter.

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
	'[Z')
		printf '%s\n' 'shift_tab'
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

	tty_read_key_char key || {
		printf '%s\n' 'confirm'
		return 0
	}

	case "$key" in
	$'\e')
		while tty_read_key_char next -t 0.01; do
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
	$'\t')
		printf '%s\n' 'tab'
		;;
	*)
		printf '%s\n' 'ignore'
		;;
	esac
}
