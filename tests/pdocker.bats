#!/usr/bin/env bats
#
# Unit tests for pdocker's pure helpers. Docker itself is never invoked here;
# the container-facing commands are covered by the image build in CI.

setup() {
	TMP="$(mktemp -d)"
	export PDOCKER_HOME="$TMP/home"
	export PDOCKER_IMAGE="pdocker:test"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../pdocker.sh"
	PROJECTS_DIR="$PDOCKER_HOME/projects"
}

teardown() {
	rm -rf "$TMP"
}

@test "valid_name accepts docker-legal names" {
	valid_name "myapp"
	valid_name "my-app_2.0"
	valid_name "a"
}

@test "valid_name rejects what docker would reject" {
	! valid_name ""
	! valid_name "-leading-dash"
	! valid_name ".leading-dot"
	! valid_name "has space"
	! valid_name "has/slash"
}

@test "ports_to_args expands a comma list into -p flags" {
	run ports_to_args "8080:80,5432:5432"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "-p" ]
	[ "${lines[1]}" = "8080:80" ]
	[ "${lines[2]}" = "-p" ]
	[ "${lines[3]}" = "5432:5432" ]
}

@test "ports_to_args emits nothing for empty or 'n'" {
	run ports_to_args ""
	[ "$output" = "" ]
	run ports_to_args "n"
	[ "$output" = "" ]
}

@test "run_args omits --volume when no volume is set" {
	run run_args "demo" "" ""
	[ "$status" -eq 0 ]
	[[ "$output" != *"--volume"* ]]
}

@test "run_args mounts the volume at the workspace path" {
	run run_args "demo" "/host/path" ""
	[[ "$output" == *"--volume"* ]]
	[[ "$output" == *"/host/path:/workspace"* ]]
}

@test "run_args labels the container so listing never greps ps output" {
	run run_args "demo" "" ""
	[[ "$output" == *"pdocker.project=demo"* ]]
}

@test "run_args keeps a path containing spaces on one line" {
	run run_args "demo" "/host/my projects" ""
	[[ "$output" == *"/host/my projects:/workspace"* ]]
	# One argument per line is the contract the array read depends on.
	[ "$(printf '%s\n' "$output" | grep -c ':/workspace')" -eq 1 ]
}

@test "spec round-trips values, including paths with spaces" {
	spec_write "demo" "pdocker:test" "/host/my projects" "8080:80" "go"
	[ "$(spec_get demo IMAGE)" = "pdocker:test" ]
	[ "$(spec_get demo VOLUME)" = "/host/my projects" ]
	[ "$(spec_get demo PORTS)" = "8080:80" ]
}

@test "spec_set updates one key and leaves the others alone" {
	spec_write "demo" "pdocker:test" "/host/path" "8080:80" ""
	spec_set "demo" PORTS "9090:90"
	[ "$(spec_get demo PORTS)" = "9090:90" ]
	[ "$(spec_get demo VOLUME)" = "/host/path" ]
	[ "$(spec_get demo IMAGE)" = "pdocker:test" ]
}

@test "spec_get fails for an unknown project" {
	run spec_get nope IMAGE
	[ "$status" -ne 0 ]
}

@test "help and version work without a docker daemon" {
	run main help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: pdocker"* ]]

	run main version
	[ "$status" -eq 0 ]
	[[ "$output" == *"pdocker "* ]]
}

@test "run_args attaches every container to the shared network" {
	run run_args "demo" "" ""
	[[ "$output" == *"--network"* ]]
	[[ "$output" == *"pdocker"* ]]
	[[ "$output" == *"--network-alias"* ]]
}

@test "the network is configurable" {
	NETWORK="othernet"
	run run_args "demo" "" ""
	[[ "$output" == *"othernet"* ]]
}

@test "spec records the template it was created from" {
	spec_write "demo" "pdocker:go" "/host/path" "" "go"
	[ "$(spec_get demo TEMPLATE)" = "go" ]
	[ "$(spec_get demo IMAGE)" = "pdocker:go" ]
}

@test "template_image derives the tag from the template name" {
	[ "$(template_image go)" = "pdocker:go" ]
	[ "$(template_image node)" = "pdocker:node" ]
}

@test "template_exists matches the templates we ship" {
	template_exists go
	template_exists node
	template_exists python
	template_exists rust
	! template_exists nope
}

@test "detect_template recognises each ecosystem by its manifest" {
	mkdir -p "$TMP/go" && touch "$TMP/go/go.mod"
	[ "$(detect_template "$TMP/go")" = "go" ]

	mkdir -p "$TMP/rs" && touch "$TMP/rs/Cargo.toml"
	[ "$(detect_template "$TMP/rs")" = "rust" ]

	mkdir -p "$TMP/js" && touch "$TMP/js/package.json"
	[ "$(detect_template "$TMP/js")" = "node" ]

	mkdir -p "$TMP/py" && touch "$TMP/py/pyproject.toml"
	[ "$(detect_template "$TMP/py")" = "python" ]

	mkdir -p "$TMP/py2" && touch "$TMP/py2/requirements.txt"
	[ "$(detect_template "$TMP/py2")" = "python" ]
}

@test "detect_template fails on a directory it cannot classify" {
	mkdir -p "$TMP/plain"
	run detect_template "$TMP/plain"
	[ "$status" -ne 0 ]
	[ "$output" = "" ]
}

@test "go beats node when a repo contains both manifests" {
	mkdir -p "$TMP/both" && touch "$TMP/both/go.mod" "$TMP/both/package.json"
	[ "$(detect_template "$TMP/both")" = "go" ]
}

@test "cmd_new rejects an unknown flag" {
	run cmd_new demo --bogus
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown flag"* ]]
}

@test "cmd_new rejects a template we do not ship" {
	run cmd_new demo --template cobol --no-volume --no-ports
	[ "$status" -ne 0 ]
	[[ "$output" == *"No template"* ]]
}

@test "confirm declines instead of crashing when there is no terminal" {
	ASSUME_YES=0
	run confirm "proceed?" < /dev/null
	[ "$status" -ne 0 ]
	[[ "$output" != *"unbound variable"* ]]
}

@test "confirm honours --yes without touching the terminal" {
	ASSUME_YES=1
	run confirm "proceed?" < /dev/null
	[ "$status" -eq 0 ]
}

@test "spec records the network" {
	spec_write "demo" "pdocker:latest" "" "" "" "proj2"
	[ "$(spec_get demo NETWORK)" = "proj2" ]
}

@test "project_network prefers the spec, falls back to the global default" {
	spec_write "demo" "pdocker:latest" "" "" "" "proj2"
	[ "$(project_network demo)" = "proj2" ]

	# A spec written before NETWORK existed has no such key.
	printf 'IMAGE=pdocker:latest\nVOLUME=\nPORTS=\n' > "$(spec_path legacy)"
	[ "$(project_network legacy)" = "$NETWORK" ]
}

@test "a 'none' network skips the alias docker would reject" {
	run run_args "demo" "" "" "none"
	[[ "$output" == *"--network"* ]]
	[[ "$output" == *"none"* ]]
	[[ "$output" != *"--network-alias"* ]]
}

@test "an explicit network overrides the default in run_args" {
	run run_args "demo" "" "" "proj2"
	[[ "$output" == *"proj2"* ]]
}
