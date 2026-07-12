#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

expect_success() {
	local name="$1"
	shift
	if "$@"; then pass "$name"; else fail "$name"; fi
}

expect_failure() {
	local name="$1"
	shift
	if "$@"; then fail "$name"; else pass "$name"; fi
}

test_docker_stops_before_restart_on_config_failure() {
	local tmp="$1"
	RESTART_MARKER="$tmp/restarted" bash -c '
		source "$1/scripts/lib/installers/logging.sh"
		source "$1/scripts/lib/installers/docker.sh"
		docker() { printf "Docker version test\n"; }
		groups() { printf "docker\n"; }
		configure_docker_daemon() { return 1; }
		restart_docker_service() { : >"$RESTART_MARKER"; }
		install_docker
	' _ "$ROOT" "$tmp"
}

test_docker_merge_temp_file_uses_sudo_boundary() {
	local installer="$ROOT/scripts/lib/installers/docker.sh"
	grep -Fq 'tmp_file="$(sudo mktemp)"' "$installer" &&
		grep -Fq 'sudo tee "$tmp_file" >/dev/null' "$installer" &&
		grep -Fq 'sudo rm -f "$tmp_file"' "$installer"
}

test_existing_unapproved_origin_is_rejected() {
	local repo="$1/rejected-repo"
	git init -q "$repo"
	git -C "$repo" remote add origin https://example.invalid/unapproved.git
	bash -c '
		source "$1/scripts/lib/agent_bootstrap_paths.sh"
		agent_bootstrap_existing_origin_allowed "$2"
	' _ "$ROOT" "$repo"
}

test_existing_unapproved_origin_can_be_explicitly_bypassed() {
	local repo="$1/bypassed-repo"
	git init -q "$repo"
	git -C "$repo" remote add origin https://example.invalid/unapproved.git
	AGENT_BOOTSTRAP_REPO_URL_ALLOW_ANY=1 bash -c '
		source "$1/scripts/lib/agent_bootstrap_paths.sh"
		agent_bootstrap_existing_origin_allowed "$2"
	' _ "$ROOT" "$repo"
}

test_self_rejects_non_git_directory() {
	local non_git="$1/non-git"
	mkdir -p "$non_git"
	bash -c '
		upgrade_dotfiles_repo() { return 0; }
		_err() { :; }
		source <(sed -n "/^cmd_self()/,/^}/p" "$1/bin/bin/dotfiles")
		DOTFILES_DIR="$2"
		set +e
		cmd_self
		exit $?
	' _ "$ROOT" "$non_git"
}

test_self_rejects_bare_git_repository() {
	local bare_repo="$1/bare.git"
	git init -q --bare "$bare_repo"
	bash -c '
		upgrade_dotfiles_repo() { return 0; }
		_err() { :; }
		source <(sed -n "/^cmd_self()/,/^}/p" "$1/bin/bin/dotfiles")
		DOTFILES_DIR="$2"
		set +e
		cmd_self
		exit $?
	' _ "$ROOT" "$bare_repo"
}

test_report_separator_has_no_stray_trailing_dash() {
	local output
	output="$(NO_COLOR=1 bash -c 'source "$1/scripts/lib/report_table.sh"; rt_print_table_columns' _ "$ROOT")"
	[[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]] &&
		[[ "$(printf '%s\n' "$output" | sed -n '2p')" == *+*+* ]] &&
		! printf '%s\n' "$output" | sed -n '2p' | grep -Eq -- '-[0-9]+$'
}

test_path_status_separator_has_no_numeric_format_artifact() {
	local output
	output="$(NO_COLOR=1 bash -c 'source "$1/scripts/lib/ui.sh"; ui_print_check_result_path_header 100' _ "$ROOT")"
	[[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]] &&
		[[ "$(printf '%s\n' "$output" | sed -n '2p')" == *+*+* ]] &&
		! printf '%s\n' "$output" | sed -n '2p' | grep -Eq -- '-[0-9]+$'
}

test_github_api_failure_names_source_without_leaking_token() {
	local output
	output="$(PATH="$1:/usr/bin:/bin" GITHUB_TOKEN=top-secret bash -c '
		source "$2/scripts/lib/github_api.sh"
		github_api_release_json asdf-vm/asdf
	' _ "$1" "$ROOT" 2>&1)" || true
	[[ "$output" == *'GitHub Releases API request failed for asdf-vm/asdf'* ]] &&
		[[ "$output" != *'top-secret'* ]]
}

incoming_notice_fixture_init() {
	local base="$1" remote seed local_repo
	remote="$base/remote.git"
	seed="$base/seed"
	local_repo="$base/local"

	git init -q --bare "$remote"
	git init -q "$seed"
	git -C "$seed" config user.email fixture@example.test
	git -C "$seed" config user.name Fixture
	printf '%s\n' 'base' >"$seed/README.md"
	git -C "$seed" add README.md
	git -C "$seed" commit -qm base
	git -C "$seed" branch -M main
	git -C "$seed" remote add origin "$remote"
	git -C "$seed" push -qu origin main
	git -C "$remote" symbolic-ref HEAD refs/heads/main
	git clone -q "$remote" "$local_repo"
	printf '%s\n' "$remote|$seed|$local_repo"
}

test_incoming_extension_notice_classifies_extension_only_commits() {
	local tmp="$1" remote seed local_repo fixture output
	fixture="$(incoming_notice_fixture_init "$tmp/incoming-extension-only")"
	IFS='|' read -r remote seed local_repo <<<"$fixture"
	mkdir -p "$seed/extensions"
	printf '%s\n' 'changed' >"$seed/extensions/vscode-wsl.txt"
	git -C "$seed" add extensions/vscode-wsl.txt
	git -C "$seed" commit -qm 'extension change'
	git -C "$seed" push -q origin main
	git -C "$local_repo" fetch -q origin main

	output="$(DOTFILES_DIR="$local_repo" bash -c '
		source <(sed -n "/^dotfiles_repo_incoming_change_notice()/,/^}/p" "$1/bin/bin/dotfiles")
		_msg() { printf "%s\\n" "$*"; }
		dotfiles_repo_incoming_change_notice main
	' _ "$ROOT")"
	[[ "$output" == *'Upstream changes include extension manifests. Review them in Extensions > Publish manifest changes before updating.'* ]] &&
		[[ "$output" != *'Upstream changes also include non-extension files. Review those changes manually before updating.'* ]]
}

test_incoming_extension_notice_classifies_non_extension_only_commits() {
	local tmp="$1" remote seed local_repo fixture output
	fixture="$(incoming_notice_fixture_init "$tmp/incoming-non-extension-only")"
	IFS='|' read -r remote seed local_repo <<<"$fixture"
	printf '%s\n' 'changed' >"$seed/README.md"
	git -C "$seed" add README.md
	git -C "$seed" commit -qm 'readme change'
	git -C "$seed" push -q origin main
	git -C "$local_repo" fetch -q origin main

	output="$(DOTFILES_DIR="$local_repo" bash -c '
		source <(sed -n "/^dotfiles_repo_incoming_change_notice()/,/^}/p" "$1/bin/bin/dotfiles")
		_msg() { printf "%s\\n" "$*"; }
		dotfiles_repo_incoming_change_notice main
	' _ "$ROOT")"
	[[ "$output" != *'Upstream changes include extension manifests. Review them in Extensions > Publish manifest changes before updating.'* ]] &&
		[[ "$output" == *'Upstream changes also include non-extension files. Review those changes manually before updating.'* ]]
}

test_incoming_extension_notice_classifies_mixed_commits() {
	local tmp="$1" remote seed local_repo fixture output
	fixture="$(incoming_notice_fixture_init "$tmp/incoming-mixed")"
	IFS='|' read -r remote seed local_repo <<<"$fixture"
	mkdir -p "$seed/extensions"
	printf '%s\n' 'changed' >"$seed/extensions/cursor-wsl.txt"
	printf '%s\n' 'changed' >"$seed/README.md"
	git -C "$seed" add extensions/cursor-wsl.txt README.md
	git -C "$seed" commit -qm 'mixed change'
	git -C "$seed" push -q origin main
	git -C "$local_repo" fetch -q origin main

	output="$(DOTFILES_DIR="$local_repo" bash -c '
		source <(sed -n "/^dotfiles_repo_incoming_change_notice()/,/^}/p" "$1/bin/bin/dotfiles")
		_msg() { printf "%s\\n" "$*"; }
		dotfiles_repo_incoming_change_notice main
	' _ "$ROOT")"
	[[ "$output" == *'Upstream changes include extension manifests. Review them in Extensions > Publish manifest changes before updating.'* ]] &&
		[[ "$output" == *'Upstream changes also include non-extension files. Review those changes manually before updating.'* ]]
}

test_incoming_extension_notice_ignores_unavailable_remote() {
	local tmp="$1" repo="$tmp/incoming-no-remote" output
	git init -q "$repo"
	git -C "$repo" config user.email fixture@example.test
	git -C "$repo" config user.name Fixture
	printf '%s\n' 'base' >"$repo/README.md"
	git -C "$repo" add README.md
	git -C "$repo" commit -qm base

	output="$(DOTFILES_DIR="$repo" bash -c '
		source <(sed -n "/^dotfiles_repo_incoming_change_notice()/,/^}/p" "$1/bin/bin/dotfiles")
		_msg() { printf "%s\\n" "$*"; }
		dotfiles_repo_incoming_change_notice main
	' _ "$ROOT")"
	[[ -z "$output" ]]
}

manifest_fixture_init() {
	local repo="$1"
	mkdir -p "$repo/extensions"
	git init -q "$repo"
	git -C "$repo" config user.email fixture@example.test
	git -C "$repo" config user.name Fixture
	printf '%s\n' 'base' >"$repo/extensions/vscode-wsl.txt"
	printf '%s\n' 'base' >"$repo/extensions/manifest.json"
	printf '%s\n' 'base' >"$repo/extensions/ext-compat.tsv"
	printf '%s\n' 'base' >"$repo/README.md"
	git -C "$repo" add .
	git -C "$repo" commit -qm fixture
}

test_manifest_preflight_rejects_nested_extension_text_files() {
	local tmp="$1" repo="$tmp/manifest-nested" output

	manifest_fixture_init "$repo"
	mkdir -p "$repo/extensions/nested"
	printf '%s\n' 'not allowed' >"$repo/extensions/nested/hidden.txt"
	if output="$(ext_manifest_preflight "$repo" 2>&1)"; then
		return 1
	fi
	[[ "$output" == *'extensions/nested/hidden.txt'* ]]
}

test_manifest_preflight_retains_manifest_and_tracked_compat_paths() {
	local tmp="$1" repo="$tmp/manifest-compat" output

	manifest_fixture_init "$repo"
	printf '%s\n' 'changed' >>"$repo/extensions/manifest.json"
	printf '%s\n' 'changed' >>"$repo/extensions/ext-compat.tsv"
	output="$(ext_manifest_preflight "$repo")" || return 1
	[[ "$output" == *'extensions/manifest.json'* ]] &&
		[[ "$output" == *'extensions/ext-compat.tsv'* ]]
}

manifest_publish_fixture_init() {
	local repo="$1" remote="${1}.remote.git"

	manifest_fixture_init "$repo"
	git init -q --bare "$remote"
	git -C "$repo" branch -M main
	git -C "$repo" remote add origin "$remote"
	git -C "$repo" push -qu origin main
}

test_manifest_publish_pushes_verified_upstream_remote_and_ref() {
	local tmp="$1" repo="$tmp/manifest-push" output

	manifest_publish_fixture_init "$repo"
	printf '%s\n' 'changed' >>"$repo/extensions/vscode-wsl.txt"
	output="$(PUSH_LOG="$tmp/push.log" bash -c '
		source "$1/scripts/menus/helpers.sh"
		source "$1/scripts/menus/extensions.sh"
		ui_confirm_yes_no() { return 0; }
		git() {
			if [[ "$3" == push ]]; then printf "%s\\n" "$*" >>"$PUSH_LOG"; fi
			command git "$@"
		}
		ext_manifest_run "$2"
	' _ "$ROOT" "$repo" 2>&1)" || return 1
	[[ "$(cat "$tmp/push.log")" == "-C $repo push origin main" ]] &&
		[[ "$output" == *'Published commit'* ]]
}

test_manifest_publish_parses_slash_named_upstream_remote() {
	local tmp="$1" repo="$tmp/manifest-push-slash-remote" remote="$tmp/manifest-push-slash-remote.git" output

	manifest_fixture_init "$repo"
	git init -q --bare "$remote"
	git -C "$repo" branch -M main
	git -C "$repo" remote add team/origin "$remote"
	git -C "$repo" push -qu team/origin main
	printf '%s\n' 'changed' >>"$repo/extensions/vscode-wsl.txt"
	output="$(PUSH_LOG="$tmp/slash-push.log" bash -c '
		source "$1/scripts/menus/helpers.sh"
		source "$1/scripts/menus/extensions.sh"
		ui_confirm_yes_no() { return 0; }
		git() {
			if [[ "$3" == push ]]; then printf "%s\\n" "$*" >>"$PUSH_LOG"; fi
			command git "$@"
		}
		ext_manifest_run "$2"
	' _ "$ROOT" "$repo" 2>&1)" || return 1
	[[ "$(cat "$tmp/slash-push.log")" == "-C $repo push team/origin main" ]] &&
		[[ "$output" == *'Published commit'* ]]
}

test_manifest_publish_reports_git_add_failure() {
	local tmp="$1" repo="$tmp/manifest-add-failure" output

	manifest_publish_fixture_init "$repo"
	printf '%s\n' 'changed' >>"$repo/extensions/vscode-wsl.txt"
	if output="$(bash -c '
		source "$1/scripts/menus/helpers.sh"
		source "$1/scripts/menus/extensions.sh"
		ui_confirm_yes_no() { return 0; }
		git() { [[ "$3" == add ]] && return 42; command git "$@"; }
		ext_manifest_run "$2"
	' _ "$ROOT" "$repo" 2>&1)"; then
		return 1
	fi
	[[ "$output" == *'Error: failed to stage extension manifest changes.'* ]]
}

test_manifest_publish_reports_git_commit_failure() {
	local tmp="$1" repo="$tmp/manifest-commit-failure" output

	manifest_publish_fixture_init "$repo"
	printf '%s\n' 'changed' >>"$repo/extensions/vscode-wsl.txt"
	if output="$(bash -c '
		source "$1/scripts/menus/helpers.sh"
		source "$1/scripts/menus/extensions.sh"
		ui_confirm_yes_no() { return 0; }
		git() { [[ "$3" == commit ]] && return 42; command git "$@"; }
		ext_manifest_run "$2"
	' _ "$ROOT" "$repo" 2>&1)"; then
		return 1
	fi
	[[ "$output" == *'Error: failed to create the extension manifest commit.'* ]]
}

test_manifest_preflight_allows_clean_and_allowed_manifest_changes() {
	local tmp="$1" repo="$tmp/manifest-clean" output

	manifest_fixture_init "$repo"
	source "$ROOT/scripts/menus/helpers.sh"
	ext_manifest_preflight "$repo" >/dev/null
	printf '%s\n' 'changed' >>"$repo/extensions/vscode-wsl.txt"
	git -C "$repo" add extensions/vscode-wsl.txt
	printf '%s\n' 'new' >"$repo/extensions/custom.txt"
	output="$(ext_manifest_preflight "$repo")" || return 1
	[[ "$output" == *'extensions/vscode-wsl.txt'* ]]
	[[ "$output" == *'extensions/custom.txt'* ]]
}

test_manifest_preflight_rejects_unrelated_staged_and_untracked_changes() {
	local tmp="$1" repo output

	for scenario in unrelated staged untracked; do
		repo="$tmp/manifest-${scenario}"
		manifest_fixture_init "$repo"
		case "$scenario" in
		unrelated) printf '%s\n' 'changed' >>"$repo/README.md" ;;
		staged)
			printf '%s\n' 'changed' >>"$repo/README.md"
			git -C "$repo" add README.md
			;;
		untracked) printf '%s\n' 'new' >"$repo/unrelated.txt" ;;
		esac
		if output="$(ext_manifest_preflight "$repo" 2>&1)"; then
			return 1
		fi
		[[ "$output" == *'README.md'* || "$output" == *'unrelated.txt'* ]] || return 1
	done
}

test_manifest_preflight_rejects_renames_without_exposing_status_arrows_as_paths() {
	local tmp="$1" repo output

	repo="$tmp/manifest-rename"
	manifest_fixture_init "$repo"
	git -C "$repo" mv extensions/vscode-wsl.txt extensions/cursor-wsl.txt
	if output="$(ext_manifest_preflight "$repo" 2>&1)"; then
		return 1
	fi
	[[ "$output" == *'rename'* ]] || return 1
	[[ "${EXT_MANIFEST_CHANGED_PATHS[*]}" != *' -> '* ]]
}

test_publish_manifest_submenu_has_only_guarded_actions() {
	source "$ROOT/scripts/menus/extensions.sh"
	[[ "${_ext_publish_menu_labels[*]}" == 'Run Revert local manifest changes Back' ]] &&
		[[ "${_ext_publish_menu_keys[*]}" == 'run revert back' ]]
}

matrix_fixture_cmd() {
	[[ "$1" == "ext" && "$2" == list-*-all ]] || return 1
	printf '%s\n' 'fixture.extension|Fixture extension|fixture.extension@1.0.0|1|1|fixture.extension@1.0.0|0|1|fixture.extension@1.0.0|1|0||0|0|1|1|1|1'
}

test_extension_matrix_uses_universal_state_glyphs() {
	local manifest installed store_ok expected actual

	source "$ROOT/scripts/menus/helpers.sh"
	source "$ROOT/scripts/lib/menu_matrix.sh"
	while IFS='|' read -r manifest installed store_ok expected; do
		actual="$(ext_matrix_state_glyph "$manifest" "$installed" "$store_ok")"
		[[ "$actual" == "$expected" ]] || return 1
	done <<'EOF'
1|1|1|Y
0|1|1|N
1|0|1|—
0|0|1|!
1|1|0|#
EOF
}

test_extension_matrix_loads_unchecked_pending_cells() {
	local idx subcmd

	source "$ROOT/scripts/menus/helpers.sh"
	for subcmd in list-edit-all list-missing-all list-extra-all; do
		ext_matrix_from_tsv matrix_fixture_cmd "$subcmd"
		for idx in 0 1 2 3; do
			[[ "${MENU_MX_CHECKED[$idx]}" -eq 0 ]] || return 1
		done
		[[ "${MENU_MX_MANIFEST[*]}" == '1 0 1 0' ]] &&
			[[ "${MENU_MX_INSTALLED[*]}" == '1 1 0 0' ]] &&
			[[ "${MENU_MX_STORE_OK[*]}" == '1 1 1 1' ]] || return 1
	done
}

test_extension_action_menus_load_the_edit_row_universe() {
	local action expected

	source "$ROOT/scripts/menus/helpers.sh"
	source "$ROOT/scripts/menus/extensions.sh"
	ui_clear() { :; }
	resolve_dotfiles_cmd() { printf 'matrix_fixture_cmd\n'; }
	ext_matrix_from_tsv() {
		printf '%s|%s|%s\n' "$1" "$2" "${3:-}" >>"$MATRIX_LOAD_LOG"
		return 0
	}
	menu_matrix_run() { return 1; }

	for action in restore remove; do
		MATRIX_LOAD_LOG="$(mktemp)"
		_ext_menu_dispatch "$action"
		case "$action" in
		restore) expected='matrix_fixture_cmd|list-edit-all|restore' ;;
		remove) expected='matrix_fixture_cmd|list-edit-all|remove' ;;
		esac
		[[ "$(cat "$MATRIX_LOAD_LOG")" == "$expected" ]] || return 1
		rm -f "$MATRIX_LOAD_LOG"
	done
}

test_extension_matrix_transitions_only_for_selected_operations() {
	local mode baseline checked expected actual

	source "$ROOT/scripts/menus/helpers.sh"
	while IFS='|' read -r mode baseline checked expected; do
		actual="$(ext_matrix_transition "$mode" "$baseline" "$checked")"
		[[ "$actual" == "$expected" ]] || return 1
	done <<'EOF'
edit|Y|0|no-op
edit|Y|1|N
edit|N|1|Y
edit|—|1|!
edit|!|1|—
restore|—|1|Y
restore|N|1|no-op
restore|Y|1|no-op
remove|N|1|!
remove|Y|1|no-op
edit|#|1|no-op
EOF
}

test_extension_matrix_restore_and_remove_toggle_only_their_actionable_states() {
	local mode row expected_changes

	source "$ROOT/scripts/menus/helpers.sh"
	for mode in restore remove; do
		MENU_MX_MODE="$mode"
		MENU_MX_ROWS=(present extra missing absent)
		MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
		MENU_MX_MANIFEST=(1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0)
		MENU_MX_INSTALLED=(1 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0)
		MENU_MX_STORE_OK=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1)
		MENU_MX_LINES=(present@1.0.0 '' '' '' extra@2.0.0 '' '' '' missing@3.0.0 '' '' '' absent@4.0.0 '' '' '')
		MENU_MX_CHECKED=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
		MENU_MX_PENDING_ACTION=(no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op)
		MENU_MX_PENDING_LINES=('' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '')
		MENU_MX_TOGGLEABLE=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
		for row in 0 1 2 3; do
			case "$mode:$row" in
			restore:2 | remove:1) MENU_MX_TOGGLEABLE[$((row * 4))]=1 ;;
			esac
		done

		for row in 0 1 2 3; do
			case "$mode:$row" in
			restore:2 | remove:1)
				ext_matrix_toggle_cell "$row" 0
				ext_matrix_toggle_cell "$row" 0
				[[ "${MENU_MX_CHECKED[$((row * 4))]}" -eq 0 ]] || return 1
				ext_matrix_toggle_cell "$row" 0
				;;
			*)
				if ext_matrix_toggle_cell "$row" 0; then
					return 1
				fi
				;;
			esac
		done

		case "$mode" in
		restore) expected_changes='vscode-wsl: missing  missing@3.0.0  — → Y' ;;
		remove) expected_changes='vscode-wsl: extra  extra@2.0.0  N → !' ;;
		esac
		[[ "$(ext_matrix_collect_action_preview "$mode")" == "$expected_changes" ]] || return 1
	done
}

matrix_action_recorder() {
	local target="$3" line
	read -r line
	printf '%s|%s|%s\n' "$1 $2" "$target" "$line" >>"$MATRIX_ACTION_LOG"
	[[ "$line" != fail@* ]]
}

test_extension_matrix_action_results_report_exact_success_and_failure_transitions() {
	local tmp="$1" output

	source "$ROOT/scripts/menus/helpers.sh"
	MATRIX_ACTION_LOG="$tmp/action.log"
	MENU_MX_MODE=restore
	MENU_MX_ROWS=(works fails)
	MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
	MENU_MX_MANIFEST=(1 1 0 0 1 0 0 0)
	MENU_MX_INSTALLED=(0 0 0 0 0 0 0 0)
	MENU_MX_STORE_OK=(1 1 1 1 1 1 1 1)
	MENU_MX_LINES=(works@1.0.0 '' '' '' fail@2.0.0 '' '' '')
	MENU_MX_CHECKED=(1 0 0 0 1 0 0 0)
	MENU_MX_PENDING_ACTION=(Y no-op no-op no-op Y no-op no-op no-op)
	MENU_MX_PENDING_LINES=('' '' '' '' '' '' '' '')

	output="$(ext_matrix_apply_action matrix_action_recorder restore)"
	[[ "$output" == *'vscode-wsl: works  works@1.0.0  — → Y'* ]] &&
		[[ "$output" == *'vscode-wsl: fails  fail@2.0.0  — → — (install failed)'* ]] &&
		[[ "$(cat "$MATRIX_ACTION_LOG")" == $'ext install-lines|vscode-wsl|works@1.0.0\next install-lines|vscode-wsl|fail@2.0.0' ]]
}

test_extension_matrix_edit_collects_exact_transitions_and_blocks_incompatible_cells() {
	local changes

	source "$ROOT/scripts/menus/helpers.sh"
	MENU_MX_MODE=edit
	MENU_MX_ROWS=(manifest.installed installed.only manifest.missing neither)
	MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
	MENU_MX_MANIFEST=(1 0 0 0 0 0 0 0 1 0 0 0 0 1 0 0)
	MENU_MX_INSTALLED=(1 0 0 0 1 0 0 0 0 0 0 0 0 1 0 0)
	MENU_MX_STORE_OK=(1 1 1 1 1 1 1 1 1 1 1 1 1 0 1 1)
	MENU_MX_CHECKED=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
	MENU_MX_TOGGLEABLE=(1 0 0 0 1 0 0 0 1 0 0 0 1 0 0 0)
	MENU_MX_PENDING_ACTION=(no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op no-op)
	MENU_MX_PENDING_LINES=('' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '')

	ext_matrix_toggle_cell 0 0
	ext_matrix_toggle_cell 1 0
	ext_matrix_toggle_cell 2 0
	ext_matrix_toggle_cell 3 0
	if ext_matrix_toggle_cell 3 1; then
		return 1
	fi

	changes="$(ext_matrix_collect_changes edit)"
	[[ "$changes" == $'vscode-wsl: manifest.installed  Y → N\nvscode-wsl: installed.only  N → Y\nvscode-wsl: manifest.missing  — → !\nvscode-wsl: neither  ! → —' ]]
}

matrix_sync_recorder() {
	printf '%s\n' "$*" >>"$MATRIX_SYNC_LOG"
	cat >>"${MATRIX_SYNC_LOG}.stdin"
}

test_extension_matrix_edit_noop_does_not_sync_or_remove_incompatible_entries() {
	local tmp="$1"

	source "$ROOT/scripts/menus/helpers.sh"
	MATRIX_SYNC_LOG="$tmp/sync.log"
	MENU_MX_MODE=edit
	MENU_MX_ROWS=(incompatible untouched)
	MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
	MENU_MX_MANIFEST=(1 1 1 1 1 1 1 1)
	MENU_MX_INSTALLED=(1 1 1 1 1 1 1 1)
	MENU_MX_STORE_OK=(0 1 1 1 1 1 1 1)
	MENU_MX_CHECKED=(0 0 0 0 0 0 0 0)
	MENU_MX_PENDING_ACTION=(no-op no-op no-op no-op no-op no-op no-op no-op)
	MENU_MX_LINES=(wrong-store.extension@1.0.0 untouched@1.0.0 untouched@1.0.0 untouched@1.0.0 untouched@1.0.0 untouched@1.0.0 untouched@1.0.0 untouched@1.0.0)

	ext_matrix_apply_edit matrix_sync_recorder
	[[ ! -e "$MATRIX_SYNC_LOG" && ! -e "${MATRIX_SYNC_LOG}.stdin" ]]
}

test_extension_matrix_edit_preserves_untouched_incompatible_entries_when_applying_delta() {
	local tmp="$1" changes

	source "$ROOT/scripts/menus/helpers.sh"
	MATRIX_SYNC_LOG="$tmp/sync.log"
	MENU_MX_MODE=edit
	MENU_MX_ROWS=(incompatible added)
	MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
	MENU_MX_MANIFEST=(1 0 0 0 0 0 0 0)
	MENU_MX_INSTALLED=(1 1 0 0 0 0 0 0)
	MENU_MX_STORE_OK=(0 1 1 1 1 1 1 1)
	MENU_MX_CHECKED=(0 0 0 0 0 0 0 0)
	MENU_MX_TOGGLEABLE=(0 1 1 1 1 1 1 1)
	MENU_MX_PENDING_ACTION=(no-op no-op no-op no-op no-op no-op no-op no-op)
	MENU_MX_LINES=(wrong-store.extension@1.0.0 '' '' '' '' '' '' '')

	ext_matrix_toggle_cell 1 0
	changes="$(ext_matrix_collect_changes edit)"
	[[ "$changes" == 'vscode-wsl: added  ! → —' ]] || return 1
	ext_matrix_apply_edit matrix_sync_recorder
	[[ "$(cat "$MATRIX_SYNC_LOG")" == 'ext sync-manifest vscode-wsl' ]] &&
		grep -Fxq 'wrong-store.extension@1.0.0' "${MATRIX_SYNC_LOG}.stdin" &&
		grep -Fxq 'added' "${MATRIX_SYNC_LOG}.stdin"
}

test_extension_matrix_edit_uses_a_compatible_installed_line_before_manifest_fallback() {
	source "$ROOT/scripts/menus/helpers.sh"
	MENU_MX_MODE=edit
	MENU_MX_ROWS=(fixture.extension)
	MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
	MENU_MX_MANIFEST=(0 0 1 0)
	MENU_MX_INSTALLED=(0 1 0 0)
	MENU_MX_STORE_OK=(1 1 1 1)
	MENU_MX_LINES=('' fixture.extension@2.0.0 fixture.extension@1.0.0 '')
	MENU_MX_CHECKED=(0 0 0 0)
	MENU_MX_TOGGLEABLE=(1 0 0 0)
	MENU_MX_PENDING_ACTION=(no-op no-op no-op no-op)
	MENU_MX_PENDING_LINES=('' '' '' '')

	ext_matrix_toggle_cell 0 0
	[[ "${MENU_MX_PENDING_ACTION[0]}" == '—' ]] &&
		[[ "${MENU_MX_PENDING_LINES[0]}" == 'fixture.extension@2.0.0' ]]
}

matrix_sync_fails_for_one_target() {
	printf '%s\n' "$*" >>"$MATRIX_SYNC_LOG"
	cat >>"${MATRIX_SYNC_LOG}.stdin"
	[[ "$3" != vscode-wsl ]]
}

test_extension_matrix_edit_reports_per_target_sync_failures() {
	local tmp="$1" output

	source "$ROOT/scripts/menus/helpers.sh"
	MATRIX_SYNC_LOG="$tmp/sync-failure.log"
	MENU_MX_MODE=edit
	MENU_MX_ROWS=(first second)
	MENU_MX_COL_KEYS=(vscode-wsl vscode-win cursor-wsl cursor-win)
	MENU_MX_MANIFEST=(0 0 0 0 0 0 0 0)
	MENU_MX_INSTALLED=(1 0 0 0 0 1 0 0)
	MENU_MX_STORE_OK=(1 1 1 1 1 1 1 1)
	MENU_MX_LINES=(first@1.0.0 '' '' '' '' second@2.0.0 '' '')
	MENU_MX_CHECKED=(1 0 0 0 0 1 0 0)
	MENU_MX_PENDING_ACTION=(Y no-op no-op no-op no-op Y no-op no-op)
	MENU_MX_PENDING_LINES=('' '' '' '' '' '' '' '')

	if output="$(ext_matrix_apply_edit matrix_sync_fails_for_one_target 2>&1)"; then
		return 1
	fi
	[[ "$output" == *'vscode-wsl: manifest sync failed'* ]] &&
		[[ "$output" == *'vscode-win: 1 manifest entry'* ]] &&
		[[ "$(cat "$MATRIX_SYNC_LOG")" == $'ext sync-manifest vscode-wsl\next sync-manifest vscode-win' ]]
}

test_edit_menu_does_not_claim_success_after_a_manifest_sync_failure() {
	local output

	source "$ROOT/scripts/menus/extensions.sh"
	resolve_dotfiles_cmd() { printf 'fixture-dotfiles\n'; }
	ui_clear() { :; }
	ext_matrix_from_tsv() { return 0; }
	menu_matrix_run() { return 0; }
	ext_matrix_collect_changes() { printf '%s\n' 'vscode-wsl: fixture.extension  N → Y'; }
	ext_matrix_count_risky() { printf '0\n'; }
	ui_confirm_yes_no() { return 0; }
	ext_matrix_apply_edit() { printf '%s\n' '  vscode-wsl: manifest sync failed' >&2; return 1; }

	output="$(_ext_menu_dispatch edit 2>&1)"
	[[ "$output" == *'Some manifest changes failed to sync'* ]] &&
		[[ "$output" != *'Applied manifest changes:'* ]]
}

strip_ansi() {
	sed -E $'s/\x1B\\[[0-?]*[ -\\/]*[@-~]//g'
}

test_extension_matrix_rendering_keeps_labels_aligned_and_uses_shared_legend() {
	local normal selected normal_lead selected_lead legend expected

	source "$ROOT/scripts/lib/menu_render.sh"
	source "$ROOT/scripts/lib/ui.sh"
	source "$ROOT/scripts/menus/helpers.sh"
	source "$ROOT/scripts/lib/menu_matrix.sh"
	ui_init_colors
	MENU_MX_MODE=edit
	MENU_MX_ROWS=(fixture.alpha fixture.bravo)
	MENU_MX_LABELS=('Fixture Alpha' 'Fixture Bravo')
	MENU_MX_MANIFEST=(1 0 1 0 0 1 0 1)
	MENU_MX_INSTALLED=(1 1 0 0 1 0 0 1)
	MENU_MX_CHECKED=(0 1 0 0 0 0 0 0)
	MENU_MX_STORE_OK=(1 1 1 1 1 1 1 1)

	normal="$(_menu_mx_draw_row 1 0 0 160 | strip_ansi)"
	selected="$(_menu_mx_draw_row 1 0 1 160 | strip_ansi)"
	normal_lead="${normal%%Fixture Alpha*}"
	selected_lead="${selected%%Fixture Bravo*}"
	[[ ${#normal_lead} -eq ${#selected_lead} ]] || return 1

	legend="$(_menu_mx_print_glyph_key 160 | strip_ansi)"
	expected=$'  Y >>> in manifest, installed\n  N >>> not in manifest, installed\n  — >>> in manifest, not installed\n  ! >>> not in manifest, not installed\n  # >>> wrong IDE store'
	[[ "$legend" == "$expected" ]]
}

main() {
	local tmp
	tmp="$(mktemp -d)"
	trap 'rm -rf -- "${tmp:-}"' EXIT

	expect_failure 'Docker config failure prevents restart' test_docker_stops_before_restart_on_config_failure "$tmp"
	expect_success 'Docker merge temporary file stays in the sudo boundary' test_docker_merge_temp_file_uses_sudo_boundary
	if [[ ! -e "$tmp/restarted" ]]; then
		pass 'Docker restart was not attempted'
	else
		fail 'Docker restart was not attempted'
	fi
	expect_failure 'unapproved existing agent_bootstrap origin is rejected' test_existing_unapproved_origin_is_rejected "$tmp"
	expect_success 'explicit origin bypass remains available' test_existing_unapproved_origin_can_be_explicitly_bypassed "$tmp"
	expect_failure 'dotfiles self rejects non-git directory' test_self_rejects_non_git_directory "$tmp"
	expect_failure 'dotfiles self rejects bare Git repository' test_self_rejects_bare_git_repository "$tmp"
	expect_success 'report separator has no stray trailing dash' test_report_separator_has_no_stray_trailing_dash
	expect_success 'path-status separator has no numeric format artifact' test_path_status_separator_has_no_numeric_format_artifact

	local curl_dir="$tmp/curl-bin"
	mkdir -p "$curl_dir"
	printf '%s\n' '#!/usr/bin/env bash' 'echo "curl: (22) The requested URL returned error: 403" >&2' 'exit 22' >"$curl_dir/curl"
	chmod +x "$curl_dir/curl"
	expect_success 'GitHub API failures are diagnosable without token leakage' test_github_api_failure_names_source_without_leaking_token "$curl_dir"
	expect_success 'incoming extension-only commits show the extension-manifest notice' test_incoming_extension_notice_classifies_extension_only_commits "$tmp"
	expect_success 'incoming non-extension commits show the manual-review notice' test_incoming_extension_notice_classifies_non_extension_only_commits "$tmp"
	expect_success 'incoming mixed commits show both update notices' test_incoming_extension_notice_classifies_mixed_commits "$tmp"
	expect_success 'unavailable dotfiles remote produces no incoming-change notice' test_incoming_extension_notice_ignores_unavailable_remote "$tmp"
	expect_success 'manifest preflight allows clean plus staged and untracked manifest fixture changes' test_manifest_preflight_allows_clean_and_allowed_manifest_changes "$tmp"
	expect_success 'manifest preflight rejects nested extension text files' test_manifest_preflight_rejects_nested_extension_text_files "$tmp"
	expect_success 'manifest preflight retains manifest.json and tracked ext-compat.tsv' test_manifest_preflight_retains_manifest_and_tracked_compat_paths "$tmp"
	expect_success 'manifest preflight rejects unrelated, staged, and untracked fixture changes' test_manifest_preflight_rejects_unrelated_staged_and_untracked_changes "$tmp"
	expect_success 'manifest preflight rejects renames without treating arrows as paths' test_manifest_preflight_rejects_renames_without_exposing_status_arrows_as_paths "$tmp"
	expect_success 'manifest publish pushes the verified upstream remote and ref' test_manifest_publish_pushes_verified_upstream_remote_and_ref "$tmp"
	expect_success 'manifest publish parses slash-named upstream remotes' test_manifest_publish_parses_slash_named_upstream_remote "$tmp"
	expect_success 'manifest publish reports git add failures' test_manifest_publish_reports_git_add_failure "$tmp"
	expect_success 'manifest publish reports git commit failures' test_manifest_publish_reports_git_commit_failure "$tmp"
	expect_success 'publish manifest submenu exposes only Run, Revert, and Back' test_publish_manifest_submenu_has_only_guarded_actions
	expect_success 'extension matrix uses the five universal state glyphs' test_extension_matrix_uses_universal_state_glyphs
	expect_success 'extension matrix loads compatible cells as unchecked pending operations' test_extension_matrix_loads_unchecked_pending_cells
	expect_success 'Restore and Remove action menus load the Edit row universe' test_extension_action_menus_load_the_edit_row_universe
	expect_success 'extension matrix derives target states only from selected operations' test_extension_matrix_transitions_only_for_selected_operations
	expect_success 'Restore and Remove only toggle their actionable state and clear on a second toggle' test_extension_matrix_restore_and_remove_toggle_only_their_actionable_states
	expect_success 'Restore and Remove report exact per-cell success and failure transitions' test_extension_matrix_action_results_report_exact_success_and_failure_transitions "$tmp"
	expect_success 'Edit collects every allowed transition and blocks incompatible cells' test_extension_matrix_edit_collects_exact_transitions_and_blocks_incompatible_cells
	expect_success 'untouched Edit never syncs or removes incompatible manifest entries' test_extension_matrix_edit_noop_does_not_sync_or_remove_incompatible_entries "$tmp"
	expect_success 'Edit delta retains untouched incompatible manifest entries' test_extension_matrix_edit_preserves_untouched_incompatible_entries_when_applying_delta "$tmp"
	expect_success 'Edit additions prefer a compatible installed line over manifest fallback' test_extension_matrix_edit_uses_a_compatible_installed_line_before_manifest_fallback
	expect_success 'Edit reports and returns per-target manifest sync failures' test_extension_matrix_edit_reports_per_target_sync_failures "$tmp"
	expect_success 'Edit menu never claims success after a manifest sync failure' test_edit_menu_does_not_claim_success_after_a_manifest_sync_failure
	expect_success 'extension matrix rendering keeps labels aligned and uses the shared legend' test_extension_matrix_rendering_keeps_labels_aligned_and_uses_shared_legend

	printf '%s test(s) passed; %s failed\n' "$PASS" "$FAIL"
	[[ "$FAIL" -eq 0 ]]
}

main "$@"
