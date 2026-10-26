#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/lib/harness.sh"
test_harness_init
source "$TEST_DIR/lib/dotfiles_env.sh"
for key in lazygit lazydocker; do
	export HOME="$TEST_HARNESS_ROOT/$key"
	export PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
	root="$(dotfiles_catalog_root "$key")"
	mkdir -p "$HOME/.local/bin" "$root/releases/baseline"
	printf '#!/usr/bin/env bash\necho "%s 1.0.0"\n' "$key" >"$root/releases/baseline/command"
	chmod +x "$root/releases/baseline/command"
	printf '1.0.0\n%064d\n%040d\n' 0 0 >"$root/releases/baseline/.catalog-receipt"
	ln -s "$root/releases/baseline" "$root/current"
	ln -s "$root/current/command" "$HOME/.local/bin/$key"
	printf '#!/usr/bin/env bash\necho "%s 2.0.0"\n' "$key" >"$HOME/artifact"
	digest="$(sha256sum "$HOME/artifact")"
	printf '%s\n' "$key"$'\towner\tany\tdotfiles' "$key"$'\tkind\tany\tsoftware' \
		"$key"$'\tversion\tany\t2.0.0' "$key"$'\tarchive\tany\traw' \
		"$key"$'\tbinary\tany\t'"$key" "$key"$'\turl\tany\thttps://fixture.invalid/tool' \
		"$key"$'\tdigest\tany\tsha256:'"${digest%% *}" | catalog_fixture_seal "$HOME/catalog"
	catalog_fixture_use "$HOME/catalog"
	curl() {
		printf 'download\n' >>"$HOME/downloads"
		while (($#)); do
			if [[ "$1" == -o ]]; then
				cp "$HOME/artifact" "$2"
				return
			fi
			shift
		done
		return 1
	}
	"_comp_install_$key"
	[[ "$("$HOME/.local/bin/$key" --version)" == "$key 2.0.0" ]] || {
		echo "FAIL: selected $key skipped approved version reconciliation" >&2
		exit 1
	}
	"_comp_install_$key"
	[[ "$(wc -l <"$HOME/downloads")" == 1 ]]
	DOTFILES_FORCE_REINSTALL=1 "_comp_install_$key"
	[[ "$(wc -l <"$HOME/downloads")" == 2 ]]
	rm "$HOME/.local/bin/$key"
	printf '#!/usr/bin/env bash\necho "external 9.9.9"\n' >"$HOME/.local/bin/$key"
	chmod +x "$HOME/.local/bin/$key"
	for force in 0 1; do
		DOTFILES_FORCE_REINSTALL="$force" "_comp_install_$key"
		[[ "$("$HOME/.local/bin/$key" --version)" == 'external 9.9.9' ]]
		[[ "$(wc -l <"$HOME/downloads")" == 2 ]]
	done
done
printf 'PASS: selected components reconcile approved versions and preserve external commands\n'
