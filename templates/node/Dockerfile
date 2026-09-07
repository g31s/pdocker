ARG BASE=pdocker:latest
FROM ${BASE}

ARG USERNAME=dev
# Pin a version (e.g. v24.20.0) for reproducible builds, or leave as "lts".
ARG NODE_VERSION=lts

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) narch=x64 ;; \
      arm64) narch=arm64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    ver="${NODE_VERSION}"; \
    if [ "$ver" = "lts" ]; then \
      # nodejs.org has no /dist/latest-lts/ path; resolve it from the index,
      # without needing jq or python inside the image.
      json="$(curl -fsSL https://nodejs.org/dist/index.json)"; \
      ver="$(printf '%s' "$json" | tr '}' '\n' \
        | sed -n 's/.*"version":"\([^"]*\)".*"lts":"[^"]*".*/\1/p' \
        | awk 'NR==1')"; \
    fi; \
    test -n "$ver"; \
    curl -fsSL "https://nodejs.org/dist/${ver}/node-${ver}-linux-${narch}.tar.xz" \
      -o /tmp/node.tar.xz; \
    mkdir -p /usr/local/node; \
    tar -C /usr/local/node --strip-components=1 -xJf /tmp/node.tar.xz; \
    rm /tmp/node.tar.xz; \
    /usr/local/node/bin/node --version
USER ${USERNAME}

ENV npm_config_cache=/workspace/.cache/npm \
    PDOCKER_PATH=/usr/local/node/bin:/workspace/node_modules/.bin
