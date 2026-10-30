# 1. BUILD STAGE
FROM python:3.12-slim-bookworm AS builder

# Install everything needed to download/build
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Deno
RUN curl -fsSL https://deno.land/install.sh | sh

# Install mistral-vibe (get latest version)
RUN pip install --no-cache-dir mistral-vibe

# 2. RUNTIME STAGE
FROM python:3.12-slim-bookworm

ARG VIBE_HOME

# Install runtime deps, dev tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      elixir \
      git \
      curl \
      build-essential \
      vim-tiny \
    && rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# elixir package manager
RUN mix local.hex --force

# Remove package managers to prevent installation of unwanted packages
# but keep git and build tools for development
RUN rm -rf /usr/bin/apt /usr/bin/apt-get /usr/bin/dpkg /var/lib/dpkg

# Copy Deno binary
COPY --from=builder /root/.deno/bin/deno /usr/local/bin/deno

# Copy Python packages and the 'vibe' executable
COPY --from=builder \
     /usr/local/lib/python3.12/site-packages \
     /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin/vibe /usr/local/bin/vibe

# Create work dirs and prompts directory
RUN mkdir -p ${VIBE_HOME}/.vibe \
             ${VIBE_HOME}/.vibe/prompts \
             ${VIBE_HOME}/.cache/deno \
             ${VIBE_HOME}/.mix \
             ${VIBE_HOME}/.hex \
             /app
WORKDIR /app

# Configure Git to trust project directory
RUN git config --global --add safe.directory /app

# Copy agent instructions
COPY AGENTS.md ${VIBE_HOME}/AGENTS.md

# Create config to use AGENTS.md as system prompt
RUN echo '[system]' > ${VIBE_HOME}/.vibe/config.toml && \
    echo 'prompt_id = "default"' >> ${VIBE_HOME}/.vibe/config.toml

ENTRYPOINT ["vibe"]
