# shellcheck shell=bash
# shellcheck source=scripts/lib/catalog_load.sh
source "${BASH_SOURCE[0]%/*}/catalog_load.sh"

_dotfiles_catalog_source_repository() {
	case "$1" in
	nvm) printf 'nvm-sh/nvm\n' ;;
	asdf-golang) printf 'asdf-community/asdf-golang\n' ;;
	*) return 2 ;;
	esac
}

_dotfiles_catalog_source_git() {
	timeout 180 env GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
		git -c core.hooksPath=/dev/null -c credential.helper= "$@"
}

dotfiles_catalog_source_owned() {
	local key="$1" root release releases
	root="$(dotfiles_catalog_root "$key")"
	[[ ! -L "$root" && ! -L "$root/releases" && -L "$root/current" ]] || return 1
	release="$(realpath -- "$root/current")" || return 1
	releases="$(realpath -- "$root/releases")" || return 1
	[[ "$release" == "$releases/"* && -d "$release/.git" && ! -L "$release/.git" ]] || return 1
	dotfiles_catalog_source_checkout_owned "$key" "$release"
}

dotfiles_catalog_source_checkout_owned() {
	local key="$1" release="$2" repository revision
	repository="$(_dotfiles_catalog_source_repository "$key")" || return 1
	[[ -d "$release/.git" && ! -L "$release/.git" ]] || return 1
	dotfiles_catalog_receipt_valid "$release/.catalog-receipt" || return 1
	[[ -f "$release/.catalog-source-revision" && ! -L "$release/.catalog-source-revision" &&
		-O "$release/.catalog-source-revision" && "$(stat -c %s -- "$release/.catalog-source-revision")" == 41 ]] || return 1
	revision="$(cat "$release/.catalog-source-revision")" || return 1
	[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
	[[ "$(_dotfiles_catalog_source_git -C "$release" rev-parse --verify HEAD)" == "$revision" ]] || return 1
	[[ "$(_dotfiles_catalog_source_git -C "$release" config --get remote.origin.url)" == "https://github.com/$repository.git" ]] || return 1
	/usr/bin/python3 -I -B - "$DOTFILES_SHARED_ROOT" "$release" "$revision" <<'PY'
import pathlib,sys
sys.path.insert(0,str(pathlib.Path(sys.argv[1])/"scripts/lib/shared/python"))
from catalog_git_source import verify_checkout
try:
    verify_checkout(pathlib.Path(sys.argv[2]),sys.argv[3])
except (OSError,ValueError):
    raise SystemExit(1)
PY
}

# Prints the verified checkout path. Native runtime adapters own activation.
dotfiles_catalog_source_install() (
	local key="$1" repository root revision version current_revision='' staging='' committed=0 rc=0 temporary_link
	# shellcheck disable=SC2034  # Holds the transaction descriptor until this subshell exits.
	local lock_fd
	dotfiles_catalog_transaction_lock "$key" lock_fd || return $?
	dotfiles_catalog_begin || return $?
	[[ "${SOFTWARE_CATALOG_REVISION:-}" =~ ^[0-9a-f]{40}$ ]] || return 2
	repository="$(_dotfiles_catalog_source_repository "$key")" || return 2
	[[ "$(dotfiles_catalog_get "$key" owner)" == dotfiles &&
	"$(dotfiles_catalog_get "$key" kind)" == git-source &&
	"$(dotfiles_catalog_get "$key" source)" == "$repository" ]] || return 2
	revision="$(dotfiles_catalog_get "$key" revision)" || return 2
	[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 2
	version="$(dotfiles_catalog_get "$key" version 2>/dev/null || true)"
	version="${version:-$revision}"
	[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+:-]*$ ]] || return 2
	root="$(dotfiles_catalog_root "$key")"
	[[ ! -L "$root" && ! -L "$root/releases" ]] || return 2
	if [[ -e "$root/current" || -L "$root/current" ]]; then
		if ! dotfiles_catalog_source_owned "$key"; then
			printf 'Preserving modified or unverified %s source checkout.\n' "$key" >&2
			return 2
		fi
		current_revision="$(cat "$root/current/.catalog-source-revision")" || return 2
		if [[ "$current_revision" == "$revision" && "${DOTFILES_FORCE_REINSTALL:-0}" != 1 ]]; then
			realpath -- "$root/current"
			return 0
		fi
	fi
	mkdir -p -- "$root/releases" || return 1
	staging="$(mktemp -d "$root/releases/.source-XXXXXX")" || return 1
	temporary_link="$root/.source-current.$BASHPID"
	trap 'rm -f -- "$temporary_link"; if [[ "$committed" == 0 ]]; then rm -rf -- "$staging"; fi' EXIT
	_dotfiles_catalog_source_git init --quiet "$staging" >"$staging/.catalog-fetch.log" 2>&1 || return $?
	_dotfiles_catalog_source_git -C "$staging" remote add origin "https://github.com/$repository.git" >>"$staging/.catalog-fetch.log" 2>&1 || return $?
	# Full ancestry lets us reject source rewinds and unrelated histories.
	_dotfiles_catalog_source_git -C "$staging" fetch --quiet origin "$revision" >>"$staging/.catalog-fetch.log" 2>&1 || rc=$?
	if ((rc != 0)); then
		printf 'Could not fetch the approved %s revision; preserving the current checkout.\n' "$key" >&2
		return "$rc"
	fi
	_dotfiles_catalog_source_git -C "$staging" checkout --quiet --detach "$revision" >>"$staging/.catalog-fetch.log" 2>&1 || return $?
	[[ "$(_dotfiles_catalog_source_git -C "$staging" rev-parse --verify HEAD)" == "$revision" ]] || return 2
	if [[ -n "$current_revision" ]] && ! _dotfiles_catalog_source_git -C "$staging" merge-base --is-ancestor "$current_revision" "$revision" >/dev/null 2>&1; then
		printf 'Cannot verify that approved %s source advances the installed revision; preserving it.\n' "$key" >&2
		return 2
	fi
	[[ ! -e "$staging/.catalog-receipt" && ! -L "$staging/.catalog-receipt" &&
		! -e "$staging/.catalog-source-revision" && ! -L "$staging/.catalog-source-revision" ]] || return 2
	rm -f -- "$staging/.catalog-fetch.log"
	printf '\n/.catalog-receipt\n/.catalog-source-revision\n' >>"$staging/.git/info/exclude" || return 1
	printf '%s\n%s\n%s\n' "$version" "$SOFTWARE_CATALOG_DIGEST" "$SOFTWARE_CATALOG_REVISION" >"$staging/.catalog-receipt"
	printf '%s\n' "$revision" >"$staging/.catalog-source-revision"
	dotfiles_catalog_source_checkout_owned "$key" "$staging" || return 2
	ln -s -- "$staging" "$temporary_link" || return 1
	mv -Tf -- "$temporary_link" "$root/current" || return 1
	committed=1
	printf '%s\n' "$staging"
)
