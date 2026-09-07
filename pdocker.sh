#!/usr/bin/env bash
#
# pdocker - manage and maintain personal project containers with Docker.
#
# Containers are described by a spec file under $PDOCKER_HOME/projects and are
# always (re)created from the base image, never from a commit. Anything that
# must survive a recreate lives in the mounted volume.
#
# Written for bash 3.2 so it runs on a stock macOS.

set -euo pipefail

readonly PDOCKER_VERSION="3.0.0"
readonly LABEL="pdocker"
readonly WORKDIR="/workspace"

PDOCKER_HOME="${PDOCKER_HOME:-${HOME}/.pdocker}"
PROJECTS_DIR="${PDOCKER_HOME}/projects"
IMAGE="${PDOCKER_IMAGE:-pdocker:latest}"
NETWORK="${PDOCKER_NETWORK:-pdocker}"
ASSUME_YES="${PDOCKER_ASSUME_YES:-0}"

# Resolve the repo root through any symlink, since install.sh links this script
# into ~/.local/bin and the templates live next to the real file.
_pd_src="${BASH_SOURCE[0]}"
while [ -L "$_pd_src" ]; do
	_pd_dir="$(cd -P "$(dirname "$_pd_src")" && pwd)"
	_pd_src="$(readlink "$_pd_src")"
	case "$_pd_src" in /*) ;; *) _pd_src="$_pd_dir/$_pd_src" ;; esac
done
PDOCKER_ROOT="$(cd -P "$(dirname "$_pd_src")" && pwd)"
TEMPLATES_DIR="${PDOCKER_ROOT}/templates"

# ---------------------------------------------------------------- output ----

info() { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
err()  { printf '[-] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------- checks ----

# require_docker fails early if the daemon is not reachable.
require_docker() {
	command -v docker >/dev/null 2>&1 || die "docker not found in PATH."
	docker info >/dev/null 2>&1 || die "Cannot reach the Docker daemon. Is Docker running?"
}

# require_image fails if the base image has not been built yet.
require_image() {
	docker image inspect "$IMAGE" >/dev/null 2>&1 \
		|| die "Image '$IMAGE' not found. Run ./build.sh first."
}

# require_image_named fails if a specific image is missing.
require_image_named() {
	docker image inspect "$1" >/dev/null 2>&1 \
		|| die "Image '$1' not found. Run ./build.sh first."
}

# valid_name checks a name against Docker's own container-name rules.
valid_name() {
	[[ "${1:-}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]
}

# confirm asks a yes/no question, honouring --yes.
confirm() {
	local reply=""
	[[ "$ASSUME_YES" == "1" ]] && return 0
	# No terminal (CI, a pipe, `pdocker ... < /dev/null`) means "no", not a crash.
	read -r -p "[?] $1 [y/N]: " reply 2>/dev/null </dev/tty || return 1
	[[ "$reply" == "y" || "$reply" == "Y" ]]
}

# --------------------------------------------------------------- network ----

# ensure_network creates the shared network the first time it is needed. Every
# pdocker container joins it, so projects reach each other by container name.
ensure_network() {
	local net="${1:-$NETWORK}"
	[[ "$net" == "none" ]] && return 0
	docker network inspect "$net" >/dev/null 2>&1 && return 0
	info "Creating network '$net' ..."
	docker network create "$net" >/dev/null
}

# project_network returns the network a project should be on: its own spec
# value if it set one, otherwise the global default.
project_network() {
	local net
	net="$(spec_get "$1" NETWORK 2>/dev/null || true)"
	[[ -n "$net" ]] || net="$NETWORK"
	printf '%s\n' "$net"
}

# -------------------------------------------------------------- templates ----

template_dir()   { printf '%s/%s\n' "$TEMPLATES_DIR" "$1"; }
template_image() { printf 'pdocker:%s\n' "$1"; }

# template_exists reports whether we ship a template by that name.
template_exists() { [[ -d "$(template_dir "$1")" ]]; }

# detect_template guesses a template from the files in a project directory.
detect_template() {
	local dir="${1:-$PWD}"
	if [[ -f "$dir/go.mod" ]]; then printf 'go\n'; return 0; fi
	if [[ -f "$dir/Cargo.toml" ]]; then printf 'rust\n'; return 0; fi
	if [[ -f "$dir/package.json" ]]; then printf 'node\n'; return 0; fi
	if [[ -f "$dir/pyproject.toml" || -f "$dir/requirements.txt" ]]; then
		printf 'python\n'; return 0
	fi
	return 1
}

template_build() {
	local name="${1:-}" dir img
	[[ -n "$name" ]] || die "Usage: pdocker template build <name>"
	template_exists "$name" || die "No template '$name'. Try: pdocker template list"
	require_image
	dir="$(template_dir "$name")"
	img="$(template_image "$name")"
	info "Building $img from templates/$name (this installs a toolchain, give it a minute) ..."
	docker build --rm --build-arg "BASE=${IMAGE}" -t "$img" "$dir"
	info "Built $img."
}

# ensure_template_image builds the template image on first use.
ensure_template_image() {
	local img
	img="$(template_image "$1")"
	docker image inspect "$img" >/dev/null 2>&1 && return 0
	template_build "$1"
}

template_list() {
	local d name img
	{
		printf 'TEMPLATE\tIMAGE\tBUILT\n'
		for d in "$TEMPLATES_DIR"/*/; do
			[[ -d "$d" ]] || continue
			name="$(basename "$d")"
			img="$(template_image "$name")"
			if docker image inspect "$img" >/dev/null 2>&1; then
				printf '%s\t%s\tyes\n' "$name" "$img"
			else
				printf '%s\t%s\tno\n' "$name" "$img"
			fi
		done
	} | column -t -s "$(printf '\t')"
}

# ----------------------------------------------------------------- specs ----

spec_path() { printf '%s/%s.env\n' "$PROJECTS_DIR" "$1"; }

# spec_get reads one key out of a project spec. Values may contain spaces.
# $1 project name, $2 key
spec_get() {
	local file
	file="$(spec_path "$1")"
	[[ -f "$file" ]] || return 1
	sed -n "s/^$2=//p" "$file" | head -1
}

# spec_write records the full spec for a project.
# $1 name, $2 image, $3 volume (may be empty), $4 ports (may be empty),
# $5 template (may be empty), $6 network (defaults to the global one)
spec_write() {
	mkdir -p "$PROJECTS_DIR"
	{
		printf '# pdocker project spec - edit freely, then: pdocker rebuild %s\n' "$1"
		printf 'IMAGE=%s\n' "$2"
		printf 'VOLUME=%s\n' "$3"
		printf 'PORTS=%s\n' "$4"
		printf 'TEMPLATE=%s\n' "${5:-}"
		printf 'NETWORK=%s\n' "${6:-$NETWORK}"
	} > "$(spec_path "$1")"
}

# spec_set updates a single key in place, preserving the rest.
# $1 name, $2 key, $3 value
spec_set() {
	local file tmp
	file="$(spec_path "$1")"
	[[ -f "$file" ]] || die "No spec for '$1'. Recreate it with: pdocker new"
	tmp="${file}.tmp.$$"
	sed "s|^$2=.*|$2=$3|" "$file" > "$tmp" && mv "$tmp" "$file"
}

# ------------------------------------------------------------ containers ----

# list_containers prints tab-separated name/id/status/image for pdocker
# containers only, identified by label rather than by grepping ps output.
list_containers() {
	docker ps -a --filter "label=${LABEL}" \
		--format '{{.Names}}\t{{.ID}}\t{{.Status}}\t{{.Image}}'
}

container_names() {
	docker ps -a --filter "label=${LABEL}" --format '{{.Names}}'
}

container_exists() {
	[[ -n "$(docker ps -a --filter "label=${LABEL}" --filter "name=^/$1$" --format '{{.Names}}')" ]]
}

container_running() {
	[[ -n "$(docker ps --filter "label=${LABEL}" --filter "name=^/$1$" --format '{{.Names}}')" ]]
}

# ports_to_args expands "8080:80,5432:5432" into one docker argument per line.
ports_to_args() {
	local spec="${1:-}" part
	[[ -z "$spec" || "$spec" == "n" ]] && return 0
	local IFS=','
	for part in $spec; do
		[[ -z "$part" ]] && continue
		printf -- '-p\n%s\n' "$part"
	done
}

# run_args prints the full docker-run argument list, one per line, so the
# caller can read it into an array without re-splitting on whitespace.
# $1 name, $2 volume, $3 ports
run_args() {
	local name="$1" volume="${2:-}" ports="${3:-}" net="${4:-$NETWORK}"
	printf -- '-d\n'
	printf -- '--name\n%s\n' "$name"
	printf -- '--hostname\n%s\n' "$name"
	printf -- '--label\n%s\n' "$LABEL"
	printf -- '--label\n%s\n' "${LABEL}.project=${name}"
	printf -- '--workdir\n%s\n' "$WORKDIR"
	printf -- '--network\n%s\n' "$net"
	if [[ "$net" != "none" ]]; then
		printf -- '--network-alias\n%s\n' "$name"
	fi
	if [[ -n "$volume" ]]; then
		printf -- '--volume\n%s\n' "${volume}:${WORKDIR}"
	fi
	ports_to_args "$ports"
}

# create_container starts a detached container from the project spec. It stays
# alive on a sleep so start/stop/exec all behave the same way.
create_container() {
	local name="$1" image volume ports
	image="$(spec_get "$name" IMAGE || true)"
	volume="$(spec_get "$name" VOLUME || true)"
	ports="$(spec_get "$name" PORTS || true)"
	[[ -n "$image" ]] || image="$IMAGE"

	if [[ -n "$volume" && ! -d "$volume" ]]; then
		die "Volume path '$volume' does not exist."
	fi

	local net
	net="$(project_network "$name")"
	ensure_network "$net"

	local args=() line
	while IFS= read -r line; do
		args+=("$line")
	done < <(run_args "$name" "$volume" "$ports" "$net")

	info "Creating $name from $image ..."
	docker run "${args[@]}" "$image" sleep infinity >/dev/null
}

ensure_running() {
	container_running "$1" && return 0
	info "Starting $1 ..."
	docker start "$1" >/dev/null
}

attach() {
	if [[ ! -t 0 ]]; then
		info "Not a terminal; leaving $1 running. Attach with: pdocker $1"
		return 0
	fi
	info "Attaching to $1. Exit the shell to leave it running."
	docker exec -it "$1" /bin/bash -l
}

# recreate destroys and rebuilds a container from its spec. The volume is the
# only thing that survives, which is exactly the contract we want.
recreate() {
	local name="$1"
	[[ -f "$(spec_path "$name")" ]] \
		|| die "No spec for '$name'; cannot safely recreate it."

	if container_exists "$name"; then
		warn "Recreating '$name' discards anything outside the mounted volume."
		confirm "Continue?" || { info "Aborted."; return 1; }
		docker rm -f "$name" >/dev/null
	fi
	create_container "$name"
}

# ------------------------------------------------------------- selection ----

# choose_container resolves an explicit argument, or prompts. All prompts go to
# stderr so the caller can capture the chosen name from stdout.
choose_container() {
	local want="${1:-}" names name
	names="$(container_names)"
	[[ -n "$names" ]] || { err "No pdocker containers found."; return 1; }

	if [[ -n "$want" ]]; then
		while IFS= read -r name; do
			[[ "$name" == "$want" ]] && { printf '%s\n' "$name"; return 0; }
		done <<< "$names"
		# Fall back to an unambiguous container-ID prefix.
		name="$(docker ps -a --filter "label=${LABEL}" --filter "id=$want" \
			--format '{{.Names}}' 2>/dev/null | head -1)"
		[[ -n "$name" ]] && { printf '%s\n' "$name"; return 0; }
		err "No pdocker container matches '$want'."
		return 1
	fi

	if command -v fzf >/dev/null 2>&1; then
		name="$(list_containers | fzf --with-nth=1,3 --delimiter='\t' \
			--prompt='container> ' --height=40% --reverse | cut -f1)"
		[[ -n "$name" ]] || { err "Nothing selected."; return 1; }
		printf '%s\n' "$name"
		return 0
	fi

	cmd_ls >&2
	local PS3="[*] Select a container: "
	select name in $names; do
		[[ -n "${name:-}" ]] && { printf '%s\n' "$name"; return 0; }
		err "Invalid selection."
	done < /dev/tty >&2
	return 1
}

# -------------------------------------------------------------- commands ----

cmd_ls() {
	local rows
	rows="$(list_containers)"
	if [[ -z "$rows" ]]; then
		info "No pdocker containers yet. Create one with: pdocker new"
		return 0
	fi
	{
		printf 'NAME\tID\tSTATUS\tIMAGE\n'
		printf '%s\n' "$rows"
	} | column -t -s "$(printf '\t')"
}

cmd_new() {
	local name="" template="" volume="" ports="" network="" reply
	local have_volume=0 have_ports=0 have_template=0

	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			-t|--template) template="${2:-}"; have_template=1; shift 2 ;;
			--no-template) template=""; have_template=1; shift ;;
			-v|--volume)   volume="${2:-}";   have_volume=1;   shift 2 ;;
			--no-volume)   volume="";         have_volume=1;   shift ;;
			-p|--ports)    ports="${2:-}";    have_ports=1;    shift 2 ;;
			-N|--network)  network="${2:-}";  shift 2 ;;
			--no-network)  network="none";    shift ;;
			--no-ports)    ports="";          have_ports=1;    shift ;;
			-*) die "Unknown flag for new: $1" ;;
			*)
				[[ -z "$name" ]] || die "Unexpected argument: $1"
				name="$1"; shift ;;
		esac
	done

	while :; do
		if [[ -z "$name" ]]; then
			read -r -p "[*] New container name: " name \
				|| die "No container name given."
		fi
		if ! valid_name "$name"; then
			err "Invalid name. Use letters, digits, and _ . - (must start alphanumeric)."
			name=""
			continue
		fi
		if container_exists "$name"; then
			err "A pdocker container named '$name' already exists."
			name=""
			continue
		fi
		break
	done

	# Volume.
	if [[ "$have_volume" -eq 0 ]]; then
		printf '[*] Volume to mount at %s:\n' "$WORKDIR"
		printf '    y = current directory, n = none, or type a path\n'
		read -r -p ">> " reply || reply=""
		case "$reply" in
			y|Y) volume="$PWD" ;;
			n|N|"") volume="" ;;
			*) volume="$reply" ;;
		esac
	fi
	if [[ -n "$volume" ]]; then
		[[ "$volume" == "." ]] && volume="$PWD"
		volume="${volume/#\~/$HOME}"
		[[ -d "$volume" ]] || die "Volume path '$volume' does not exist."
		volume="$(cd "$volume" && pwd)"
	fi

	# Template: explicit flag wins, otherwise guess from the project directory.
	if [[ "$have_template" -eq 0 ]]; then
		local guess=""
		guess="$(detect_template "${volume:-$PWD}" 2>/dev/null || true)"
		if [[ -n "$guess" ]]; then
			info "Detected a $guess project."
			if confirm "Use the '$guess' template?"; then
				template="$guess"
			fi
		fi
	fi
	if [[ -n "$template" ]]; then
		template_exists "$template" \
			|| die "No template '$template'. Try: pdocker template list"
		ensure_template_image "$template"
	fi

	# Ports.
	if [[ "$have_ports" -eq 0 ]]; then
		read -r -p "[*] Ports (e.g. 8080:80,5432:5432 or blank for none) >> " ports \
			|| ports=""
	fi
	[[ "$ports" == "n" ]] && ports=""

	local image="$IMAGE"
	[[ -n "$template" ]] && image="$(template_image "$template")"
	require_image_named "$image"

	spec_write "$name" "$image" "$volume" "$ports" "$template" \
		"${network:-$NETWORK}"
	if [[ -n "$template" && -n "$volume" ]]; then
		info "Toolchain caches live in ${WORKDIR}/.cache - add '.cache/' to your .gitignore."
	fi
	create_container "$name"
	attach "$name"
}

cmd_start() {
	local name
	name="$(choose_container "${1:-}")" || return 1
	ensure_running "$name"
	attach "$name"
}

cmd_ports() {
	local name current ports
	name="$(choose_container "${1:-}")" || return 1
	current="$(spec_get "$name" PORTS || true)"
	info "Current ports: ${current:-none}"
	read -r -p "[*] New ports (e.g. 8080:80,5432:5432 or blank for none) >> " ports
	[[ "$ports" == "n" ]] && ports=""
	spec_set "$name" PORTS "$ports"
	recreate "$name" && info "Ports updated."
}

cmd_rebuild() {
	local name
	name="$(choose_container "${1:-}")" || return 1
	recreate "$name" && info "Rebuilt $name from ${IMAGE}."
}

cmd_stop() {
	local name
	name="$(choose_container "${1:-}")" || return 1
	info "Stopping $name ..."
	docker stop "$name" >/dev/null
}

cmd_logs() {
	local name
	name="$(choose_container "${1:-}")" || return 1
	docker logs "$name"
}

cmd_exec() {
	local name
	name="$(choose_container "${1:-}")" || return 1
	shift || true
	[[ "$#" -gt 0 ]] || die "Usage: pdocker exec <name> <command> [args...]"
	docker exec -it "$name" "$@"
}

cmd_delete() {
	local name
	name="$(choose_container "${1:-}")" || return 1
	confirm "Delete container '$name'?" || { info "Aborted."; return 0; }
	docker rm -f "$name" >/dev/null
	info "Deleted $name."
	if [[ -f "$(spec_path "$name")" ]] && confirm "Also delete its saved spec?"; then
		rm -f "$(spec_path "$name")"
		info "Removed spec for $name."
	fi
}

cmd_delete_all() {
	local names count reply=""
	names="$(container_names)"
	[[ -n "$names" ]] || { info "No pdocker containers found."; return 0; }
	count="$(printf '%s\n' "$names" | wc -l | tr -d ' ')"

	cmd_ls
	if [[ "$ASSUME_YES" != "1" ]]; then
		read -r -p "[!] This deletes ALL $count containers. Type the number to confirm: " reply \
			|| reply=""
		[[ "$reply" == "$count" ]] || { info "Aborted."; return 0; }
	fi

	local name failed=0
	while IFS= read -r name; do
		if docker rm -f "$name" >/dev/null 2>&1; then
			info "Deleted $name."
		else
			err "Failed to delete $name."
			failed=1
		fi
	done <<< "$names"
	[[ "$failed" -eq 0 ]] || return 1
}

# cmd_adopt imports a container created before pdocker used labels (< 3.0).
# It only writes a spec; nothing is destroyed, because recreating the container
# is what discards anything living outside the mounted volume.
cmd_adopt() {
	local name="${1:-}" image volume ports
	[[ -n "$name" ]] || die "Usage: pdocker adopt <container>"
	docker inspect "$name" >/dev/null 2>&1 || die "No container named '$name'."

	if container_exists "$name"; then
		info "'$name' is already labelled; nothing to adopt."
		return 0
	fi

	image="$(docker inspect --format '{{.Config.Image}}' "$name")"
	volume="$(docker inspect \
		--format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{end}}{{end}}' \
		"$name" | head -1)"
	ports="$(docker inspect \
		--format '{{range $p, $c := .HostConfig.PortBindings}}{{range $c}}{{.HostPort}}:{{$p}},{{end}}{{end}}' \
		"$name" | sed 's|/tcp||g; s|,$||')"

	spec_write "$name" "${image:-$IMAGE}" "$volume" "$ports"
	info "Wrote spec: $(spec_path "$name")"
	printf '      IMAGE=%s\n      VOLUME=%s\n      PORTS=%s\n' \
		"${image:-$IMAGE}" "${volume:-none}" "${ports:-none}"

	warn "'$name' is not managed yet: pdocker adopts containers by recreating them."
	if [[ -z "$volume" ]]; then
		warn "It has no bind mount, so EVERYTHING in it would be lost on recreate."
		warn "Copy anything you need out first:  docker cp $name:/path ./somewhere"
	else
		warn "Only $volume survives; anything written elsewhere in the container is lost."
	fi
	info "When you are ready:  pdocker rebuild $name"
}

cmd_template() {
	local sub="${1:-list}"
	[[ "$#" -gt 0 ]] && shift || true
	case "$sub" in
		ls|list)  template_list ;;
		build)    template_build "${1:-}" ;;
		*)        die "Usage: pdocker template [list|build <name>]" ;;
	esac
}

# cmd_net manages networks. Containers on the same network reach each other by
# name, so a 'db' project is just http://db from an 'api' project.
cmd_net() {
	local sub="${1:-show}"
	[[ "$#" -gt 0 ]] && shift || true
	case "$sub" in
		show|ls|list)  net_show "${1:-}" ;;
		set)           net_set "${1:-}" "${2:-}" ;;
		attach|connect)    net_attach "${1:-}" "${2:-}" ;;
		detach|disconnect) net_detach "${1:-}" "${2:-}" ;;
		create)        ensure_network "${1:-}" ;;
		rm|remove)     net_remove "${1:-}" ;;
		*) die "Usage: pdocker net [show|set|attach|detach|create|rm] ..." ;;
	esac
}

# net_show lists a network and its members, or every pdocker network.
net_show() {
	local net="${1:-}"
	if [[ -z "$net" ]]; then
		{
			printf 'NETWORK\tDRIVER\tCONTAINERS\n'
			docker network ls --format '{{.Name}}\t{{.Driver}}' \
				| while IFS="$(printf '\t')" read -r n d; do
					case "$n" in
						bridge|host|none) continue ;;
					esac
					printf '%s\t%s\t%s\n' "$n" "$d" \
						"$(docker network inspect "$n" \
							--format '{{len .Containers}}' 2>/dev/null || echo 0)"
				done
		} | column -t -s "$(printf '\t')"
		info "Default for new containers: $NETWORK (set PDOCKER_NETWORK to change)"
		return 0
	fi

	docker network inspect "$net" >/dev/null 2>&1 || die "No network '$net'."
	info "Network: $net"
	{
		printf 'CONTAINER\tADDRESS\n'
		docker network inspect "$net" \
			--format '{{range .Containers}}{{println .Name .IPv4Address}}{{end}}' \
			| sed '/^[[:space:]]*$/d' | tr ' ' '\t'
	} | column -t -s "$(printf '\t')"
}

# net_set changes a project's network for good: it updates the spec and
# recreates the container, so the change survives the next rebuild.
net_set() {
	local name="${1:-}" net="${2:-}"
	[[ -n "$net" ]] || die "Usage: pdocker net set <container> <network|none>"
	name="$(choose_container "$name")" || return 1
	[[ -f "$(spec_path "$name")" ]] || die "No spec for '$name'."

	if grep -q '^NETWORK=' "$(spec_path "$name")"; then
		spec_set "$name" NETWORK "$net"
	else
		printf 'NETWORK=%s\n' "$net" >> "$(spec_path "$name")"
	fi
	ensure_network "$net"
	info "Spec updated: $name -> $net"
	recreate "$name" && info "$name is now on '$net'."
}

# net_attach adds a running container to another network without recreating it.
# Useful for a one-off; it does NOT survive a rebuild - use `net set` for that.
net_attach() {
	local name="${1:-}" net="${2:-}"
	[[ -n "$net" ]] || die "Usage: pdocker net attach <container> <network>"
	name="$(choose_container "$name")" || return 1
	ensure_network "$net"
	docker network connect --alias "$name" "$net" "$name"
	info "Attached $name to $net (temporary; 'pdocker net set' makes it stick)."
}

net_detach() {
	local name="${1:-}" net="${2:-}"
	[[ -n "$net" ]] || die "Usage: pdocker net detach <container> <network>"
	name="$(choose_container "$name")" || return 1
	docker network disconnect "$net" "$name"
	info "Detached $name from $net."
}

net_remove() {
	local net="${1:-}" members
	[[ -n "$net" ]] || die "Usage: pdocker net rm <network>"
	docker network inspect "$net" >/dev/null 2>&1 || die "No network '$net'."
	members="$(docker network inspect "$net" --format '{{len .Containers}}')"
	if [[ "$members" != "0" ]]; then
		warn "'$net' still has $members container(s) attached."
		confirm "Remove it anyway?" || { info "Aborted."; return 0; }
	fi
	docker network rm "$net" >/dev/null
	info "Removed network $net."
}

# ------------------------------------------------------------------ TUI ----

tui_clear() { printf '\033[2J\033[H'; }
tui_pause() { printf '\n  press enter to continue '; read -r _ || true; }

# tui_network_menu moves a container to another network from inside the TUI.
tui_network_menu() {
	local name="$1" net=""
	tui_clear
	cmd_net show || true
	printf '\n  Move %s to which network?\n' "$name"
	printf '  (blank to cancel, "none" to isolate it)\n  > '
	read -r net || return 0
	[[ -n "$net" ]] || return 0
	net_set "$name" "$net" || true
	tui_pause
}

# tui_container is the per-container action screen.
tui_container() {
	local name="$1" a=""
	while :; do
		tui_clear
		printf '\033[1m%s\033[0m\n\n' "$name"
		docker ps -a --filter "name=^/${name}$" --format \
			'  status:  {{.Status}}
  image:   {{.Image}}
  ports:   {{.Ports}}' 2>/dev/null
		printf '\n  network: %s\n' "$(project_network "$name")"
		if [[ -f "$(spec_path "$name")" ]]; then
			printf '\n  spec:\n'
			sed 's/^/    /' "$(spec_path "$name")"
		else
			printf '\n  (no spec - import it with: pdocker adopt %s)\n' "$name"
		fi
		printf '\n  [a] attach   [s] start    [x] stop     [b] rebuild\n'
		printf '  [p] ports    [l] logs     [w] network  [d] delete   [q] back\n  > '
		read -r a || return 0
		case "$a" in
			a|A) ensure_running "$name" && attach "$name" || true ;;
			s|S) ensure_running "$name" || true; tui_pause ;;
			x|X) docker stop "$name" >/dev/null 2>&1 || true
			     info "Stopped $name."; tui_pause ;;
			b|B) recreate "$name" || true; tui_pause ;;
			p|P) cmd_ports "$name" || true; tui_pause ;;
			l|L) tui_clear; docker logs --tail 60 "$name" 2>&1 | tail -50; tui_pause ;;
			w|W) tui_network_menu "$name" ;;
			d|D) cmd_delete "$name" || true; return 0 ;;
			q|Q|"") return 0 ;;
		esac
	done
}

# cmd_tui is a full-screen browser over your containers. It is plain bash and
# ANSI escapes - no curses, no dependencies - so it works on a stock macOS.
cmd_tui() {
	[[ -t 0 && -t 1 ]] || die "pdocker tui needs an interactive terminal."
	local rows=() line choice="" n
	while :; do
		rows=()
		while IFS= read -r line; do
			rows+=("$line")
		done < <(list_containers)

		tui_clear
		printf '\033[1mpdocker %s\033[0m   default network: %s\n\n' \
			"$PDOCKER_VERSION" "$NETWORK"
		if [[ "${#rows[@]}" -eq 0 ]]; then
			printf '  No containers yet - press [n] to create one.\n'
		else
			printf '   %-3s %-18s %-24s %s\n' '#' 'NAME' 'STATUS' 'IMAGE'
			printf '   %s\n' '---------------------------------------------------------------'
			n=1
			for line in "${rows[@]}"; do
				printf '   %-3s %-18s %-24s %s\n' "$n" \
					"$(printf '%s' "$line" | cut -f1)" \
					"$(printf '%s' "$line" | cut -f3)" \
					"$(printf '%s' "$line" | cut -f4)"
				n=$((n + 1))
			done
		fi
		printf '\n  [1-9] open   [n] new   [t] networks   [r] refresh   [q] quit\n  > '

		read -r choice || return 0
		case "$choice" in
			q|Q|"") return 0 ;;
			r|R) ;;
			n|N) cmd_new || true ;;
			t|T) tui_clear; cmd_net show || true; tui_pause ;;
			*[!0-9]*) ;;
			*)
				if [[ "$choice" -ge 1 && "$choice" -le "${#rows[@]}" ]]; then
					tui_container "$(printf '%s' "${rows[$((choice - 1))]}" | cut -f1)"
				fi
				;;
		esac
	done
}

cmd_help() {
	cat <<'USAGE'
Usage: pdocker [--yes] <command> [name]

Commands:
  (none)                 pick a container and open a shell in it
  n,  new [name] [opts]  create a new project container
                         opts: -t/--template <name>  -v/--volume <path>
                               -p/--ports <list>  -N/--network <name>
                               --no-volume  --no-ports  --no-network
  ls, list               list pdocker containers
  op, ports [name]       change published ports (recreates the container)
  rb, rebuild [name]     recreate a container from its spec and the base image
  st, stop [name]        stop a container
  lg, logs [name]        show container logs
  ex, exec <name> <cmd>  run a command inside a container
  d,  delete [name]      delete one container
  da, delete_all         delete every pdocker container
  ad, adopt <name>       import a pre-3.0 container by writing a spec for it
  tpl, template [...]    list templates, or: template build <name>
  tui, ui                full-screen browser over your containers
  net [sub]              networks: show | set | attach | detach | create | rm
  h,  help               show this help
  v,  version            show the pdocker version

Flags:
  -y, --yes              assume yes for confirmation prompts

Environment:
  PDOCKER_HOME           spec directory (default: ~/.pdocker)
  PDOCKER_IMAGE          base image (default: pdocker:latest)
  PDOCKER_NETWORK        shared network (default: pdocker)

Recreating a container keeps only what lives in the mounted volume at
/workspace. Project specs are plain files under ~/.pdocker/projects.

Every container joins a shared Docker network, so projects can reach each
other by container name (e.g. `curl http://api:8080` from another project).
USAGE
}

cmd_version() { printf 'pdocker %s\n' "$PDOCKER_VERSION"; }

# ------------------------------------------------------------------ main ----

main() {
	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			-y|--yes) ASSUME_YES=1; shift ;;
			*) break ;;
		esac
	done

	case "${1:-}" in
		h|help|-h|--help) cmd_help; return 0 ;;
		v|version|--version) cmd_version; return 0 ;;
	esac

	require_docker

	local sub="${1:-}"
	[[ "$#" -gt 0 ]] && shift || true

	case "$sub" in
		n|new)          cmd_new "$@" ;;
		ls|list)        cmd_ls ;;
		op|ports|open_ports|open_port) cmd_ports "${1:-}" ;;
		rb|rebuild)     cmd_rebuild "${1:-}" ;;
		st|stop)        cmd_stop "${1:-}" ;;
		lg|logs)        cmd_logs "${1:-}" ;;
		ex|exec)        cmd_exec "$@" ;;
		d|delete)       cmd_delete "${1:-}" ;;
		da|delete_all)  cmd_delete_all ;;
		ad|adopt)       cmd_adopt "${1:-}" ;;
		tpl|template)   cmd_template "$@" ;;
		net|network)    cmd_net "$@" ;;
		tui|ui)         cmd_tui ;;
		"")             cmd_start "" ;;
		*)              cmd_start "$sub" ;;
	esac
}

# Only run when executed, so the test suite can source this file.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
