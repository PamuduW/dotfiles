#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
source "$ROOT/scripts/lib/managed_tool_state.sh"
root="$HOME/.local/share/dotfiles-catalog/codex_cli"
mkdir -p "$root/releases/test" "$HOME/.local/bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-cli 1.2.3"' >"$root/releases/test/command"
chmod +x "$root/releases/test/command"
printf '1.2.3\n%064d\n%040d\n' 0 0 >"$root/releases/test/.catalog-receipt"
ln -s "$root/releases/test" "$root/current"
ln -s "$root/current/command" "$HOME/.local/bin/codex"
[[ "$(codex_cli_install_state)" == standalone ]] || {
	echo 'FAIL: read-only ownership probe misclassified catalog Codex' >&2
	exit 1
}
if declare -F dotfiles_catalog_install >/dev/null; then
	echo 'FAIL: read-only ownership loaded software installation code' >&2
	exit 1
fi
cp "$root/releases/test/.catalog-receipt" "$TEST_HARNESS_ROOT/receipt.before"
for malformed in '' 'arbitrary receipt' $'1.2.3\ninvalid-digest\ninvalid-revision'; do
	printf '%s\n' "$malformed" >"$root/releases/test/.catalog-receipt"
	if dotfiles_catalog_owned codex_cli; then
		echo 'FAIL: malformed receipt adopted a catalog command' >&2
		exit 1
	fi
done
cp "$TEST_HARNESS_ROOT/receipt.before" "$root/releases/test/.catalog-receipt"
# A receipt at the expected pathname cannot adopt an escaping release.
mkdir "$HOME/external"
cp "$root/releases/test/command" "$HOME/external/command"
cp "$root/releases/test/.catalog-receipt" "$HOME/external/.catalog-receipt"
rm "$root/current"
ln -s "$HOME/external" "$root/current"
[[ "$(codex_cli_install_state)" == external ]]
# A historical compatibility stamp cannot replace a missing catalog receipt.
missing_receipt_failures=0
for key in boost_cli kubeconform graphify_cli; do
	case "$key" in
	boost_cli)
		binary=boost
		stamp=boost-cli.version
		ownership=(boost_cli_is_dotfiles_owned)
		;;
	kubeconform)
		binary=kubeconform
		stamp=kubeconform.version
		ownership=(release_cli_is_dotfiles_owned kubeconform)
		;;
	graphify_cli)
		binary=graphify
		stamp=graphify.version
		ownership=(graphify_cli_is_uv_owned)
		printf '%s\n' '#!/usr/bin/env bash' 'echo "graphifyy v1.2.3"' >"$TEST_FAKE_BIN/uv"
		chmod +x "$TEST_FAKE_BIN/uv"
		;;
	esac
	root="$HOME/.local/share/dotfiles-catalog/$key"
	mkdir -p "$root/releases/test" "$HOME/.local/share/dotfiles"
	printf '%s\n' '#!/usr/bin/env bash' 'echo 1.2.3' >"$root/releases/test/command"
	chmod +x "$root/releases/test/command"
	printf '1.2.3\n%064d\n%040d\n' 0 0 >"$root/releases/test/.catalog-receipt"
	printf 'v1.2.3\n' >"$HOME/.local/share/dotfiles/$stamp"
	ln -s "$root/releases/test" "$root/current"
	ln -s "$root/current/command" "$HOME/.local/bin/$binary"
	"${ownership[@]}"
	rm "$root/current/.catalog-receipt"
	if "${ownership[@]}"; then
		echo "FAIL: legacy metadata adopted $key without its catalog receipt" >&2
		missing_receipt_failures=$((missing_receipt_failures + 1))
	fi
done
[[ "$missing_receipt_failures" == 0 ]]
printf 'PASS: read-only probes recognize owned catalog commands and reject escaping releases\n'
