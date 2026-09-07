# Pdocker v3.0.0

Pdocker keeps one throwaway Docker container per personal project — a sandbox
you can open in a second, break freely, and recreate without ceremony.

It is deliberately a single Bash script. If you outgrow it, you want Docker
Compose or Dev Containers, and `pdocker` is easy to walk away from.

## Quick start

```
git clone https://github.com/g31s/pdocker.git
cd pdocker
./build.sh && ./install.sh
```

Then, from a project you already have:

```
cd ~/Projects/myapi          # a directory with a go.mod in it
pdocker new myapi -t go -v . -p 8080:8080
```

That builds a Go toolchain image the first time, mounts the directory at
`/workspace`, publishes port 8080, and drops you in a shell with `go` on the
PATH. Later, `pdocker myapi` reopens it.

Drop the `-t go` and pdocker notices the `go.mod` and *offers* the Go template
instead — handy in an existing repo, but the flag is what makes it repeatable.

## How it works

Every project has a **spec** — a plain file under `~/.pdocker/projects/`:

```
IMAGE=pdocker:go
VOLUME=/Users/you/Projects/myapi
PORTS=8080:8080,5432:5432
TEMPLATE=go
```

Containers are always (re)created from that spec and a base image, never from a
commit of a running container. The practical consequence:

> **Only what lives in the mounted volume at `/workspace` survives a rebuild.**

That is the whole discipline. It is what makes `pdocker ports` and
`pdocker rebuild` safe to run, and it keeps your environments reproducible from
a Dockerfile instead of drifting into snapshots nobody can rebuild. Edit a spec
by hand any time, then `pdocker rebuild <name>` to apply it.

Two more things follow from it:

* Pdocker finds its containers by Docker **label**, so it never touches
  anything it did not create.
* Every container joins one shared **network**, so projects can reach each
  other by name.

## Requirements

* Docker (Desktop on macOS, or Engine on Linux)
* Bash 3.2+ — the stock macOS bash is fine
* `fzf` *(optional)* — nicer container picker when present

Developed on macOS; the scripts avoid bashisms newer than 3.2 and work on Linux.

## Install

```
./build.sh      # build the base image
./install.sh    # symlink `pdocker` into ~/.local/bin
```

`install.sh` creates a symlink rather than appending an alias to your shell
config, so re-running it is harmless and it works the same in bash and zsh. If
it warns that the target directory is not on your `PATH`:

```
export PATH="$HOME/.local/bin:$PATH"
```

Uninstall with `rm ~/.local/bin/pdocker`. Nothing else is written outside
`~/.pdocker`.

## Usage

```
pdocker [--yes] <command> [name] [options]
```

| Command | Alias | What it does |
| --- | --- | --- |
| *(none)* | | pick a container and open a shell in it |
| `new [name] [opts]` | `n` | create a new project container |
| `list` | `ls` | list pdocker containers |
| `ports [name]` | `op` | change published ports (recreates the container) |
| `rebuild [name]` | `rb` | recreate from the spec and the current base image |
| `stop [name]` | `st` | stop a container |
| `logs [name]` | `lg` | show container logs |
| `exec <name> <cmd>` | `ex` | run a command inside a container |
| `delete [name]` | `d` | delete one container |
| `delete_all` | `da` | delete every pdocker container |
| `adopt <name>` | `ad` | import a pre-3.0 container by writing a spec for it |
| `template [list\|build]` | `tpl` | list templates, or build one |
| `tui` | `ui` | full-screen browser over your containers |
| `net [sub]` | | manage networks (see below) |
| `help` | `h` | show usage |
| `version` | `v` | show the version |

Options for `new`:

| Option | Meaning |
| --- | --- |
| `-t, --template <name>` | use a language template (`--no-template` to skip detection) |
| `-v, --volume <path>` | mount a host directory at `/workspace` (`.` works) |
| `-p, --ports <list>` | publish ports, e.g. `8080:80,5432:5432` |
| `-N, --network <name>` | put it on a specific network (`--no-network` to isolate) |
| `--no-volume` / `--no-ports` | answer those prompts non-interactively |

Commands that act on a container take an optional name. Omit it and you get a
picker — `fzf` if you have it, a numbered menu otherwise.

Add `--yes` to skip confirmation prompts in scripts. Without a terminal
(CI, a pipe) pdocker declines every prompt rather than hanging, and `new`
leaves the container running instead of trying to attach to it.

### Examples

```
pdocker new myapp                          # interactive: name, volume, ports
pdocker new api -t go -v . -p 8080:8080    # fully non-interactive
pdocker myapp                              # reopen the shell later
pdocker ports myapp                        # republish ports (recreates it)
pdocker exec myapp go test ./...           # one-off command
pdocker rebuild myapp                      # pick up a rebuilt base image
pdocker --yes delete myapp
```

## The TUI

```
pdocker tui
```

A full-screen browser over your containers: pick one by number to see its
status, ports, network, and spec, then act on it — attach, start, stop,
rebuild, change ports, view logs, move networks, delete.

It is plain bash and ANSI escapes, no curses and no dependencies, so it works
on a stock macOS. It needs a real terminal and will say so if it does not have
one.

## Templates

Templates give you a working language toolchain without hand-installing one.
Each is a thin image built on top of the base, installing from the official
upstream source (the Go tarball, nodejs.org, rustup, Debian's python3) rather
than through a package manager, so versions are pinnable and builds are quick:

```
pdocker template list             # go, node, python, rust
pdocker template build go         # produces pdocker:go
pdocker new myapi --template go   # builds it automatically if missing
```

`pdocker new` also **guesses** from the project directory:

| File found | Template |
| --- | --- |
| `go.mod` | `go` |
| `Cargo.toml` | `rust` |
| `package.json` | `node` |
| `pyproject.toml` or `requirements.txt` | `python` |

so in an existing repo you can usually just accept the suggestion.

Pin a version when you want reproducibility:

```
pdocker template build go     # latest
docker build --build-arg GO_VERSION=go1.25.1 -t pdocker:go templates/go
```

**Toolchains live in the image; only caches live in the volume.** That split
matters: the volume is empty until you mount a project into it, so anything
installed there would vanish. What goes in the volume is `GOMODCACHE`,
`GOCACHE`, `CARGO_TARGET_DIR`, and the npm and pip caches — the slow,
regenerable parts. That is what keeps `pdocker rebuild` cheap.

> Add `.cache/` to your project's `.gitignore`. A Go build cache alone runs to
> about 90MB.

### Adding one

Create `templates/<name>/Dockerfile`:

```dockerfile
ARG BASE=pdocker:latest
FROM ${BASE}
ARG USERNAME=dev

USER root
RUN curl -fsSL https://example.com/tool.tar.gz | tar -C /usr/local -xz
USER ${USERNAME}

# Toolchain in the image, cache in the volume.
ENV TOOL_CACHE=/workspace/.cache/tool \
    PDOCKER_PATH=/usr/local/tool/bin
```

Put PATH additions in `PDOCKER_PATH`, **not** `PATH`. Debian's `/etc/profile`
resets `PATH` in login shells but leaves other variables alone, so the shell
rc re-applies `PDOCKER_PATH` itself.

## Networking

Every pdocker container joins one shared Docker network (`pdocker` by default,
created on first use), so projects reach each other by container name:

```
pdocker net                  # all networks and how many containers are on each
pdocker net show pdocker     # who is on one network, with addresses

# from inside another pdocker container:
curl http://myapi:8080
```

A database is therefore just *another pdocker project* — no extra concept.

Each project records its network in its spec, so you can change it:

| Command | Effect |
| --- | --- |
| `pdocker net set <name> <network>` | change it **permanently** — updates the spec and recreates |
| `pdocker net attach <name> <network>` | add it to another network **now**, without recreating (does not survive a rebuild) |
| `pdocker net detach <name> <network>` | remove it from a network |
| `pdocker net create <network>` | create an empty network |
| `pdocker net rm <network>` | delete one (warns if containers are attached) |

`pdocker new --no-network`, or `pdocker net set <name> none`, isolates a
project completely.

> **Worth knowing:** containers on the same network can reach each other, and
> the image gives you passwordless `sudo`. If you run untrusted code in one
> project — an unfamiliar dependency's install script, say — it can reach the
> services in your other projects. Use `--no-network` for anything you do not
> trust.

This is deliberately all pdocker does about multi-container setups. If you need
real orchestration — health checks, dependency ordering, one-command up/down —
that is Docker Compose, and you should use it rather than growing this script.

## The image

`Dockerfile` builds a lean Debian base (~475MB) with a compiler toolchain, git,
curl, sudo, and `vi`. It intentionally does **not** preinstall language
runtimes — that is what templates are for — and it does not install Homebrew,
which alone was 245MB of the old image.

You can still install anything you want inside a container: `sudo apt install`
works out of the box, and Homebrew is one build arg away.

The image creates a user whose UID/GID match yours (`build.sh` passes them as
build args), so files you create in the mounted volume are owned by you rather
than by root. Containers do not run as root.

To add apt packages for everyone without editing the Dockerfile:

```
./build.sh --build-arg EXTRA_PACKAGES="ruby postgresql-client"
```

Add Homebrew back with `--build-arg INSTALL_BREW=true` (about +245MB).

Shell history is written to `/workspace/.pdocker_bash_history`, so it lives in
your volume and survives rebuilds.

## Upgrading from 2.x

Version 3 identifies containers by label and drives them from spec files, so
containers created by pdocker 2.x are invisible to it. Import one with:

```
pdocker adopt <name>
```

That inspects the existing container and writes a spec from its bind mount and
published ports. It does **not** touch the container — adopting for real means
recreating it, which discards anything outside the mounted volume. `adopt`
tells you exactly what would be lost; copy that out first if you need it:

```
docker cp <name>:/path ./somewhere
pdocker rebuild <name>
```

Also note that 2.x edited `~/.bash_profile` and `~/.zshrc` to add a `pdocker`
alias, possibly several times. Remove those lines — `install.sh` uses a symlink
now.

## Development

```
bats tests/                                  # unit tests, no Docker needed
shellcheck pdocker.sh build.sh install.sh
hadolint Dockerfile templates/*/Dockerfile
```

CI runs all of that plus a real image build and a template build, on every push
and once a week. The weekly run is the point: the previous release sat broken
for years because Debian dropped the `python` package and nothing ever rebuilt
the image.

## Authors

* **g31s** - *Initial work* - [g31s](https://github.com/g31s)

See also the list of [contributors](https://github.com/g31s/pdocker/contributors) who participated in this project.

## License

Licensed under the Apache License 2.0 — see [LICENSE](LICENSE).
