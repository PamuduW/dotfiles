# shellcheck shell=bash
# Docker CLI helper: try bare docker, then sudo docker.

run_docker() {
	if command -v docker >/dev/null 2>&1 && docker "$@" 2>/dev/null; then
		return 0
	fi
	if command -v docker >/dev/null 2>&1; then
		sudo docker "$@"
		return $?
	fi
	printf 'docker: command not found\n' >&2
	return 127
}
