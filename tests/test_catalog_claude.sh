#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$TEST_DIR/lib/dotfiles_env.sh"
export PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
cat >"$TEST_HARNESS_ROOT/claude" <<'CLAUDE'
#!/usr/bin/env bash
[[ "${DISABLE_UPDATES:-}" == 1 ]] || exit 97
case "${1:-}" in
--version) echo '1.2.3 (Claude Code)' ;;
update|install) echo 'Updates disabled' ;;
*) exit 98 ;;
esac
CLAUDE
digest="$(sha256sum "$TEST_HARNESS_ROOT/claude")"
printf '%s\n' $'claude_cli\towner\tany\tdotfiles' $'claude_cli\tkind\tany\tsoftware' \
	$'claude_cli\tversion\tany\t1.2.3' $'claude_cli\tarchive\tany\traw' \
	$'claude_cli\tbinary\tany\tclaude' $'claude_cli\turl\tany\thttps://fixture.invalid/claude' \
	$'claude_cli\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$TEST_HARNESS_ROOT/catalog"
catalog_fixture_use "$TEST_HARNESS_ROOT/catalog"
curl() {
	while (($#)); do
		if [[ "$1" == -o ]]; then
			cp "$TEST_HARNESS_ROOT/claude" "$2"
			return
		fi
		shift
	done
	return 99
}
install_claude_cli
[[ "$(DISABLE_UPDATES=0 "$HOME/.local/bin/claude" --version)" == '1.2.3 (Claude Code)' ]]
[[ "$(DISABLE_UPDATES=0 "$HOME/.local/bin/claude" update)" == 'Updates disabled' ]]
[[ "$(DISABLE_UPDATES=0 "$HOME/.local/bin/claude" install)" == 'Updates disabled' ]]
printf 'PASS: catalog Claude disables automatic and manual updater paths in its managed launcher\n'
