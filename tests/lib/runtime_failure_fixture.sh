# shellcheck shell=bash
# A real catalog/native adapter operation stopped at its first source/artifact
# dependency. Full SDK import and rollback are covered by native runtime suites.
runtime_failure_fixture() {
	local family="$1" key binary baseline root
	HOME="$TEST_HARNESS_ROOT/runtime-failure-$family-$BASHPID"
	export HOME NVM_DIR="$HOME/.nvm" ASDF_DATA_DIR="$HOME/.asdf"
	PATH="$HOME/.local/bin:$TEST_FAKE_BIN:/usr/bin:/bin"
	export PATH
	mkdir -p "$HOME/.local/bin"
	# shellcheck source=/dev/null
	source "$REPO_DIR/scripts/lib/catalog_runtimes.sh"
	{
		printf '%s\n' $'nodejs\towner\tany\tdotfiles' $'nodejs\tkind\tany\tsoftware' $'nodejs\tversion\tany\t24.1.0' \
			$'nodejs\tarchive\tany\ttar.gz' $'nodejs\tbinary\tany\tnode-v24.1.0-linux-x64/bin/node' $'nodejs\turl\tany\thttps://fixture.invalid/node' \
			$'nodejs\tdigest\tany\tsha256:'"$(printf '%064d' 0)" \
			$'npm\towner\tany\tdotfiles' $'npm\tkind\tany\tsoftware' $'npm\tversion\tany\t12.0.2' $'npm\tarchive\tany\ttgz' \
			$'npm\tbinary\tany\tpackage/bin/npm-cli.js' $'npm\turl\tany\thttps://fixture.invalid/npm' $'npm\tdigest\tany\tsha256:'"$(printf '%064d' 0)" \
			$'nvm\towner\tany\tdotfiles' $'nvm\tkind\tany\tgit-source' $'nvm\tsource\tany\tnvm-sh/nvm' $'nvm\tversion\tany\t0.40.8' \
			$'nvm\trevision\tany\t'"$(printf '%040d' 1)" \
			$'go\towner\tany\tdotfiles' $'go\tkind\tany\tsoftware' $'go\tversion\tany\t1.2.3' $'go\tarchive\tany\ttar.gz' \
			$'go\tbinary\tany\tgo/bin/go' $'go\turl\tany\thttps://fixture.invalid/go' $'go\tdigest\tany\tsha256:'"$(printf '%064d' 0)" \
			$'asdf\towner\tany\tdotfiles' $'asdf\tkind\tany\tsoftware' $'asdf\tversion\tany\t0.20.0' $'asdf\tarchive\tany\traw' \
			$'asdf\tbinary\tany\tasdf' $'asdf\turl\tany\thttps://fixture.invalid/asdf' $'asdf\tdigest\tany\tsha256:'"$(printf '%064d' 0)" \
			$'asdf-golang\towner\tany\tdotfiles' $'asdf-golang\tkind\tany\tgit-source' \
			$'asdf-golang\tsource\tany\tasdf-community/asdf-golang' $'asdf-golang\trevision\tany\t'"$(printf '%040d' 1)"
	} | catalog_fixture_seal "$HOME/catalog"
	catalog_fixture_use "$HOME/catalog"
	for key in nodejs npm go; do
		case "$key" in nodejs)
			binary=node
			baseline=24.0.0
			;;
		npm)
			binary=npm
			baseline=12.0.1
			;;
		go)
			binary=go
			baseline=1.2.2
			;;
		esac
		root="$(dotfiles_catalog_root "$key")"
		mkdir -p "$root/releases/baseline"
		printf '#!/usr/bin/env bash\necho "%s %s"\n' "$binary" "$baseline" >"$root/releases/baseline/command"
		chmod +x "$root/releases/baseline/command"
		printf '%s\n%s\n%s\n' "$baseline" "$SOFTWARE_CATALOG_DIGEST" "$SOFTWARE_CATALOG_REVISION" >"$root/releases/baseline/.catalog-receipt"
		ln -s "$root/releases/baseline" "$root/current"
		ln -s "$root/current/command" "$HOME/.local/bin/$binary"
		if [[ "$key" == npm ]]; then
			cp "$root/current/command" "$root/current/command-npx"
			ln -s "$root/current/command-npx" "$HOME/.local/bin/npx"
		fi
	done
	TEST_RUNTIME_FAILURE_CALLS="$HOME/calls"
	: >"$TEST_RUNTIME_FAILURE_CALLS"
	curl() {
		printf 'download:%s\n' "${*: -1}" >>"$TEST_RUNTIME_FAILURE_CALLS"
		return 27
	}
	dotfiles_catalog_source_install() {
		printf 'source:%s\n' "$1" >>"$TEST_RUNTIME_FAILURE_CALLS"
		return 27
	}
}
