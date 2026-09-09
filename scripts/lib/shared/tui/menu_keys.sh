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

# How many keystrokes may be applied before a frame is drawn regardless.
#
# A held arrow delivers about thirty keys a second and a full page costs ~37 ms
# to draw, so one frame per key leaves the list torn for as long as the key is
# down. Applying what is already waiting first collapses that; the bound is what
# keeps a long hold showing progress rather than freezing until release.
MENU_KEY_COALESCE_LIMIT="${MENU_KEY_COALESCE_LIMIT:-16}"

# Is a keystroke already waiting?
#
# `read -t 0` reports readiness without consuming anything -- but only on a
# terminal is that the question worth asking. A file-backed seam reads ready
# even at EOF, so a menu driven from a file would coalesce for ever and draw
# nothing; and a file has no key repeat to coalesce in the first place. Terminal
# only, therefore, which is also the only place the problem exists.
menu_key_pending() {
	local input_path
	if tty_use_input_fd; then
		[[ -t "$DOTFILES_TTY_IN_FD" ]] || return 1
		read -r -t 0 -u "$DOTFILES_TTY_IN_FD" 2>/dev/null
		return $?
	fi
	tty_input_available || return 1
	input_path="$(tty_input_path)"
	[[ -c "$input_path" ]] || return 1
	read -r -t 0 <"$input_path" 2>/dev/null
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
