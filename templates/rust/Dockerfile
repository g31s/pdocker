ARG BASE=pdocker:latest
FROM ${BASE}

ARG USERNAME=dev
ARG RUST_VERSION=stable

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
# The toolchain and cargo's shims must live in the image, not the volume, or
# they would disappear the moment a project directory is mounted. Only the
# build artifacts (the big, slow part) are redirected into the volume.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo
RUN set -eux; \
    mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"; \
    curl -fsSL https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal \
                 --default-toolchain "${RUST_VERSION}"; \
    chown -R "${USERNAME}:$(id -g "${USERNAME}")" "$RUSTUP_HOME" "$CARGO_HOME"; \
    "$CARGO_HOME/bin/rustc" --version
USER ${USERNAME}

ENV CARGO_TARGET_DIR=/workspace/.cache/cargo-target \
    PDOCKER_PATH=/opt/cargo/bin
