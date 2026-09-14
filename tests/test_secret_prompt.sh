#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# A pasted secret must never reach the screen.
#
# read_tty_secret masks with `*`, and that held for a typed token. A pasted one
# leaked: tty_read_key_char reads with `read -rsn1`, and -s suppresses echo for
# that one call only, so Bash restores the terminal's echo setting between every
# character. A paste arrives as one burst into the terminal's input buffer, and
# the driver echoes whatever is still buffered during those windows. The
# operator saw the leading characters of their token in clear text, followed by
# asterisks for the rest, with the whole thing left in the scrollback.
#
# The fix disables echo once, around the whole prompt. This test pastes into a
# real pty -- the bug is invisible without one, because a pipe has no echo
# setting to restore.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
passed=0
failed=0

check() {
	local label="$1"
	shift
	if "$@"; then
		printf 'ok - %s\n' "$label"
		passed=$((passed + 1))
	else
		printf 'not ok - %s\n' "$label"
		failed=$((failed + 1))
	fi
}

# Drives read_tty_secret under a pty, pasting only once the prompt is actually
# on screen -- the window the reported leak came through. Prints the captured
# length and whether the secret body appeared in the terminal stream.
_paste_into_secret_prompt() {
	python3 - "$REPO_DIR" <<'PY'
import os, pty, select, sys, time

repo = sys.argv[1]
secret = "github_pat_11SECRETSECRETSECRETSE_" + "Z" * 59
script = (
    f"cd {repo}\n"
    "source scripts/lib/shared/tui/tty.sh\n"
    'read_tty_secret value "  token (q cancels): "\n'
    'printf "\\nLEN=%s\\n" "${#value}"\n'
)
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", "-c", script])

seen = b""
deadline = time.time() + 10
while b"q cancels" not in seen and time.time() < deadline:
    if select.select([fd], [], [], 0.1)[0]:
        seen += os.read(fd, 4096)
os.write(fd, (secret + "\n").encode())

out = seen
deadline = time.time() + 10
while time.time() < deadline:
    if select.select([fd], [], [], 0.3)[0]:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    elif b"LEN=" in out:
        break
os.close(fd)

text = out.decode(errors="replace")
# A distinctive slice of the body, so a stray prefix match cannot pass for it.
print("LEAKED" if secret[11:45] in text else "MASKED")
for line in text.splitlines():
    if line.startswith("LEN="):
        print(line)
PY
}

test_a_pasted_secret_is_never_echoed() (
	local output
	output="$(_paste_into_secret_prompt)" || return 1
	[[ "$output" == *MASKED* ]] || return 1
	# And it still arrives intact: masking that ate characters would be its own
	# defect, and a shorter token fails the shape check with nothing to explain
	# why.
	[[ "$output" == *"LEN=93"* ]]
)

test_the_terminal_is_left_usable() (
	# Echo is restored after the prompt. A screen that stops echoing is the
	# failure mode of disabling it without putting it back.
	local state
	state="$(
		python3 - "$REPO_DIR" <<'PY'
import os, pty, select, sys, time

repo = sys.argv[1]
script = (
    f"cd {repo}\n"
    "source scripts/lib/shared/tui/tty.sh\n"
    'read_tty_secret value "  token: "\n'
    'stty -a | head -1 | tr " " "\\n" | grep -c "^-echo$" | sed "s/^/ECHO_OFF=/"\n'
)
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", "-c", script])
seen = b""
deadline = time.time() + 10
while b"token:" not in seen and time.time() < deadline:
    if select.select([fd], [], [], 0.1)[0]:
        seen += os.read(fd, 4096)
os.write(fd, b"abc\n")
out = seen
deadline = time.time() + 10
while time.time() < deadline:
    if select.select([fd], [], [], 0.3)[0]:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    elif b"ECHO_OFF=" in out:
        break
os.close(fd)
for line in out.decode(errors="replace").splitlines():
    if line.startswith("ECHO_OFF="):
        print(line.strip())
PY
	)" || return 1
	[[ "$state" == *"ECHO_OFF=0"* ]]
)

check 'a pasted secret is masked, not echoed' test_a_pasted_secret_is_never_echoed
check 'the terminal still echoes after the prompt' test_the_terminal_is_left_usable

printf '\nRan %d secret-prompt test(s); %d failure(s).\n' "$((passed + failed))" "$failed"
((failed == 0))
