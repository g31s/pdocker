ARG BASE=pdocker:latest
FROM ${BASE}

ARG USERNAME=dev
# Pin a version (e.g. go1.25.1) for reproducible builds, or leave as "latest".
ARG GO_VERSION=latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) goarch=amd64 ;; \
      arm64) goarch=arm64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    ver="${GO_VERSION}"; \
    if [ "$ver" = "latest" ]; then \
      ver="$(curl -fsSL 'https://go.dev/VERSION?m=text' | sed -n '1p')"; \
    fi; \
    curl -fsSL "https://go.dev/dl/${ver}.linux-${goarch}.tar.gz" -o /tmp/go.tgz; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm /tmp/go.tgz; \
    /usr/local/go/bin/go version
USER ${USERNAME}

# The toolchain lives in the image; only caches go in the volume, so they
# survive `pdocker rebuild` without the toolchain depending on the mount.
ENV GOPATH=/workspace/.cache/go \
    GOMODCACHE=/workspace/.cache/go/pkg/mod \
    GOCACHE=/workspace/.cache/go-build \
    PDOCKER_PATH=/usr/local/go/bin:/workspace/.cache/go/bin
