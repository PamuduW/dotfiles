# shellcheck shell=bash

_ext_menu_dispatch() {
	local action="$1"
	local dotfiles_cmd changes risky_count

	dotfiles_cmd="$(resolve_dotfiles_cmd)" || {
		echo "Error: dotfiles command not found." >&2
		return 1
	}

	case "$action" in
	publish)
		ext_publish_manifest_menu
		;;
	status)
		ui_clear
		printf '\n' >/dev/tty
		ui_print_header "Extensions status" "Dotfiles › Extensions" "$(menu_tty_cols)" >/dev/tty
		DOTFILES_TUI=1 "$dotfiles_cmd" ext compare all
		;;
	edit)
		ui_clear
		if ! ext_matrix_from_tsv "$dotfiles_cmd" list-edit-all; then
			echo "No extensions found across any target."
			return 0
		fi
		MENU_MX_TITLE="Edit manifest"
		MENU_MX_BREADCRUMB="Dotfiles › Extensions"
		MENU_MX_HINT="↑↓ row   Tab column   Space toggle   Enter save manifest   q back"
		if ! menu_matrix_run; then
			return 0
		fi
		changes="$(ext_matrix_collect_changes edit)"
		if [[ -z "$changes" ]]; then
			echo "No manifest changes selected."
			return 0
		fi
		printf '\nSelected manifest changes:\n%s\n' "$changes"
		risky_count="$(ext_matrix_count_risky edit)"
		if [[ "$risky_count" -gt 0 ]]; then
			printf '\nWarning: %s selected change(s) add manifest entries without a local install.\n' "$risky_count"
			ext_matrix_format_risky_lines edit 12
		fi
		if ui_confirm_yes_no "Apply these manifest changes?"; then
			if ext_matrix_apply_edit "$dotfiles_cmd"; then
				printf '\nApplied manifest changes:\n%s\n' "$changes"
			else
				printf '\nSome manifest changes failed to sync; review the per-target errors above.\n' >&2
			fi
		else
			echo "Manifest save cancelled."
		fi
		;;
	restore)
		ui_clear
		if ! ext_matrix_from_tsv "$dotfiles_cmd" list-edit-all restore; then
			echo "Nothing to restore — all manifest extensions are installed on every target."
			return 0
		fi
		MENU_MX_TITLE="Restore missing"
		MENU_MX_BREADCRUMB="Dotfiles › Extensions"
		MENU_MX_HINT="↑↓ row   Tab column   Space toggle   Enter install   q back"
		if ! menu_matrix_run; then
			return 0
		fi
		changes="$(ext_matrix_collect_action_preview restore)"
		if [[ -z "$changes" ]]; then
			echo "No extensions selected."
			return 0
		fi
		printf '\nSelected restore operations:\n%s\n' "$changes"
		if ui_confirm_yes_no "Install the selected extension transitions?"; then
			ext_matrix_apply_action "$dotfiles_cmd" restore || true
		fi
		;;
	remove)
		ui_clear
		if ! ext_matrix_from_tsv "$dotfiles_cmd" list-edit-all remove; then
			echo "Nothing to remove — no extras outside manifests on any target."
			return 0
		fi
		MENU_MX_TITLE="Remove extras"
		MENU_MX_BREADCRUMB="Dotfiles › Extensions"
		MENU_MX_HINT="↑↓ row   Tab column   Space toggle   Enter confirm   q back"
		if ! menu_matrix_run; then
			return 0
		fi
		changes="$(ext_matrix_collect_action_preview remove)"
		if [[ -z "$changes" ]]; then
			echo "No extensions selected."
			return 0
		fi
		printf '\nSelected removal operations:\n%s\n' "$changes"
		if ui_confirm_destructive "Uninstall the selected extension transitions?"; then
			ext_matrix_apply_action "$dotfiles_cmd" remove || true
		fi
		;;
	esac
}

ext_manifest_show_diff() {
	local repo="$1"
	local -a paths=("${EXT_MANIFEST_CHANGED_PATHS[@]}")

	((${#paths[@]} > 0)) || return 0
	printf '\nComplete allowed manifest diff:\n'
	git -C "$repo" diff --no-ext-diff -- "${paths[@]}"
	git -C "$repo" diff --cached --no-ext-diff -- "${paths[@]}"
}

ext_manifest_run() {
	local repo="${1:-$DOTFILES_DIR}" branch upstream remote ref commit candidate
	local -a paths=("${EXT_MANIFEST_CHANGED_PATHS[@]}")

	ext_manifest_preflight "$repo" || return 1
	paths=("${EXT_MANIFEST_CHANGED_PATHS[@]}")
	if ((${#paths[@]} == 0)); then
		echo "No local extension manifest changes to publish."
		return 0
	fi
	ext_manifest_show_diff "$repo"
	if ! ui_confirm_yes_no "Create and push a commit containing only these manifest changes?"; then
		echo "Manifest publish cancelled."
		return 0
	fi
	branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD)" || {
		echo "Error: cannot publish from a detached HEAD." >&2
		return 1
	}
	upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || {
		echo "Error: branch $branch has no upstream; set it manually before publishing." >&2
		return 1
	}
	while IFS= read -r candidate; do
		if [[ "$upstream" == "$candidate/"* && ${#candidate} -gt ${#remote} ]]; then
			remote="$candidate"
			ref="${upstream#"$candidate/"}"
		fi
	done < <(git -C "$repo" remote)
	if [[ -z "$remote" || -z "$ref" || "$remote" == "$ref" ]]; then
		echo "Error: cannot parse upstream $upstream into a remote and ref." >&2
		return 1
	fi
	if ! git -C "$repo" add -- "${paths[@]}"; then
		echo "Error: failed to stage extension manifest changes." >&2
		return 1
	fi
	if ! git -C "$repo" commit -m "extension changes - $(date +%F)"; then
		echo "Error: failed to create the extension manifest commit." >&2
		return 1
	fi
	commit="$(git -C "$repo" rev-parse --short HEAD)"
	if ! git -C "$repo" push "$remote" "$ref"; then
		echo "Push failed; local commit $commit remains on $branch and was not rolled back." >&2
		return 1
	fi
	printf 'Published commit %s to %s (%s).\n' "$commit" "$branch" "$upstream"
}

ext_manifest_revert() {
	local repo="${1:-$DOTFILES_DIR}" path
	local -a paths=() tracked=() untracked=()

	ext_manifest_preflight "$repo" || return 1
	paths=("${EXT_MANIFEST_CHANGED_PATHS[@]}")
	if ((${#paths[@]} == 0)); then
		echo "No local extension changes to revert."
		return 0
	fi
	ext_manifest_show_diff "$repo"
	if ! ui_confirm_yes_no "Revert only these local manifest changes?"; then
		echo "Manifest revert cancelled."
		return 0
	fi
	for path in "${paths[@]}"; do
		if git -C "$repo" ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
			tracked+=("$path")
		else
			untracked+=("$path")
		fi
	done
	((${#tracked[@]} == 0)) || git -C "$repo" restore --source=HEAD --staged --worktree -- "${tracked[@]}"
	((${#untracked[@]} == 0)) || git -C "$repo" clean -f -- "${untracked[@]}"
	echo "Reverted local extension manifest changes."
}

_ext_publish_menu_dispatch() {
	case "$1" in
	run) ext_manifest_run ;;
	revert) ext_manifest_revert ;;
	esac
}

_ext_publish_menu_labels=("Run" "Revert local manifest changes" "Back")
_ext_publish_menu_keys=(run revert back)

_ext_publish_menu_desc_fn() {
	case "$1" in
	0) echo "Preview allowed manifest changes, then confirm creating and pushing one commit." ;;
	1) echo "Preview and restore only allowed extension manifest paths to HEAD." ;;
	2) echo "Return to IDE Extensions without running Git." ;;
	esac
}

ext_publish_manifest_menu() {
	MENU_SUBMENU_DESC_FN=_ext_publish_menu_desc_fn
	menu_submenu_loop "Publish manifest changes" "Dotfiles › Extensions › Publish" \
		_ext_publish_menu_labels _ext_publish_menu_keys _ext_publish_menu_dispatch
}

_ext_menu_labels=(
	"Check status"
	"Edit manifest"
	"Restore"
	"Remove"
	"Publish manifest changes"
	"Back"
)
_ext_menu_keys=(status edit restore remove publish back)

_ext_menu_desc_fn() {
	case "$1" in
	0)
		echo "Compare manifest vs installed extensions on all four targets."
		echo "Runs dotfiles ext compare all; read-only."
		;;
	1)
		echo "Matrix editor: toggle which extensions belong in each target manifest."
		echo "Saves via ext sync-manifest; warns on manifest-only entries."
		;;
	2)
		echo "Install extensions that are in the manifest but missing locally."
		echo "Matrix picker across vscode-wsl, vscode-win, cursor-wsl, cursor-win."
		;;
	3)
		echo "Uninstall extensions installed locally but not in the manifest."
		echo "Destructive; confirms before uninstalling selected cells."
		;;
	4)
		echo "Preview and publish only extension manifest files, or revert their local changes."
		echo "Blocks any unrelated local Git changes."
		;;
	5)
		echo "Return to the main Dotfiles menu."
		;;
	esac
}

extensions_menu() {
	MENU_SUBMENU_DESC_FN=_ext_menu_desc_fn
	menu_submenu_loop "IDE Extensions" "Dotfiles › Extensions" \
		_ext_menu_labels _ext_menu_keys _ext_menu_dispatch
}
