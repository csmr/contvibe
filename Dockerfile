# 1. BUILD STAGE
FROM python:3.12-slim-bookworm AS builder

# Install build dependencies, ensuring ca-certificates is up-to-date
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      unzip \
      ca-certificates \
    && apt-get --only-upgrade install -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Deno
RUN curl -fsSL https://deno.land/install.sh | sh

# Ensure certifi is patched against the eMudhra compromise
RUN pip install --no-cache-dir --upgrade \
      "certifi>=2026.10.19" \
      mistral-vibe

# 2. RUNTIME STAGE
FROM python:3.12-slim-bookworm

ARG VIBE_HOME

ENV MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    PATH=/opt/mix/bin:/opt/hex/bin:${PATH}

# Install runtime deps and ensure system CA bundle is updated
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      elixir \
      git \
      curl \
      build-essential \
      vim-tiny \
      ca-certificates \
    && apt-get --only-upgrade install -y ca-certificates \
    && curl -fsSL \
       https://download.docker.com/linux/static/stable/\
x86_64/docker-27.3.1.tgz \
       | tar -xzC /usr/local/bin --strip-components=1 docker/docker \
    && rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Elixir package manager in shared /opt location
RUN mkdir -p /opt/mix /opt/hex && \
    mix local.hex --force && \
    chmod -R 777 /opt/mix /opt/hex

# Remove package managers to prevent installation of unwanted packages
RUN rm -rf /usr/bin/apt /usr/bin/apt-get /usr/bin/dpkg /var/lib/dpkg

# Copy Deno binary
COPY --from=builder /root/.deno/bin/deno /usr/local/bin/deno

# Copy Python packages and vibe executables
COPY --from=builder \
     /usr/local/lib/python3.12/site-packages \
     /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin/vibe* /usr/local/bin/

# Base runtime directories
RUN mkdir -p ${VIBE_HOME} /app
WORKDIR /app

ENTRYPOINT ["vibe"]
