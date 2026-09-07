# Base image for the pdocker project.
#
# Goal: as small as we can make it while still letting you do everything for a
# project inside one container. That means the base carries only what nearly
# every project needs - a compiler, git, curl, sudo - and language toolchains
# come from templates (see templates/). Anything else is one `sudo apt install`
# or `brew install` away.

FROM debian:13-slim

ARG USERNAME=dev
ARG UID=1000
ARG GID=1000
# Extra apt packages, e.g. --build-arg EXTRA_PACKAGES="ruby postgresql-client"
ARG EXTRA_PACKAGES=""
# Homebrew is 245MB and slow to build, so it is opt-in. Templates do not need
# it; `sudo apt install` covers most of what it was here for.
ARG INSTALL_BREW=false

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Fail a RUN if any stage of a pipe fails, not just the last one.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# One layer, no recommends, cache removed. C.UTF-8 is built into glibc, so the
# `locales` package is not needed. vim-tiny (~2MB) provides `vi` so the shell is
# not editor-less; install a full editor per project if you want one.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        file \
        git \
        procps \
        sudo \
        unzip \
        vim-tiny \
        xz-utils \
        ${EXTRA_PACKAGES} \
    && rm -rf /var/lib/apt/lists/*

# Create a user whose UID/GID match the host, so files written into the mounted
# volume are owned by you and not by root. Both IDs may already exist in the
# base image (macOS staff is GID 20, which Debian ships as dialout).
RUN if ! getent group "${GID}" >/dev/null; then groupadd -g "${GID}" "${USERNAME}"; fi \
    && if ! getent passwd "${UID}" >/dev/null; then \
         useradd -l -m -u "${UID}" -g "${GID}" -s /bin/bash "${USERNAME}"; \
       else \
         usermod -l "${USERNAME}" -d "/home/${USERNAME}" -m "$(getent passwd "${UID}" | cut -d: -f1)"; \
       fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}" \
    && mkdir -p /workspace && chown "${UID}:${GID}" /workspace

USER ${USERNAME}

# Optional. The maintained Homebrew/install repo; the old Linuxbrew/install
# path is archived. NONINTERACTIVE keeps it from prompting during the build.
RUN if [ "${INSTALL_BREW}" = "true" ]; then \
      NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      && /home/linuxbrew/.linuxbrew/bin/brew --version; \
    fi

COPY --chown=${UID}:${GID} dotfiles/bashrc /home/${USERNAME}/.bashrc
COPY --chown=${UID}:${GID} dotfiles/bashrc /home/${USERNAME}/.bash_profile

WORKDIR /workspace

CMD ["bash", "-l"]
