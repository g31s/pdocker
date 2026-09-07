ARG BASE=pdocker:latest
FROM ${BASE}

ARG USERNAME=dev

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 --version
USER ${USERNAME}

# Debian marks its Python as externally managed, so work in a venv:
#   python3 -m venv /workspace/.venv && . /workspace/.venv/bin/activate
# PDOCKER_PATH puts that venv on PATH automatically once it exists.
ENV PIP_CACHE_DIR=/workspace/.cache/pip \
    PDOCKER_PATH=/workspace/.venv/bin
