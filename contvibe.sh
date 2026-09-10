#!/bin/bash

set -e

# default working directory path (defaults to current directory)
export WORK_PATH="${WORK_PATH:-$(pwd)}"

# target mount path, in container filesystem
export bind_path="/app"

# vibe.sh script location
contvibe_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# agent comtainer home dir
vibe_home="/home/python"
export VIBE_HOME="${vibe_home}"
v_ver=$(cat "${contvibe_path}/VERSION" 2>/dev/null || echo "v0.2.0-dev")

str_arr=("contvibe.sh ${v_ver} 😽 sandbox container runner")
args=()
# Order-independent parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --workpath=*|--jailpath=*)
            export WORK_PATH="${1#*=}"
            shift
            ;;
        *)
            # Capture all other flags for Vibe
            args+=("$1")
            shift
            ;;
    esac
done

# Expand tilde (~) if present in WORK_PATH
export WORK_PATH="${WORK_PATH/#\~/$HOME}"

str_arr+=("container volume mount config: "
          "host work path: ${WORK_PATH}"
          "agent fs mount path: ${bind_path}"
          "vibe args: ${args}")
printf "%s\n" "${str_arr[@]}"

# Sanity check: Docker group
if [[ ! $(groups) =~ "docker" ]]; then
    echo "Error: $(whoami) not in docker group."
    exit 1
fi

# persistent directories
v_state=".contvibe"
# for Vibe files
mkdir -p "${contvibe_path}/.vibe_config"
# persists/home/agent
mkdir -p "${WORK_PATH}/${v_state}"

# .gitignore adderifier
ign_f="${WORK_PATH}/.gitignore"
if [ -f "$ign_f" ]; then
    if ! grep -qxF "/$v_state/" "$ign_f"; then
        printf "\n# Contvibe isolated environment state\n/$v_state/\n" \
            >> "$ign_f"
    fi
fi

# Identity exports for the container
export UA_UID=$(id -u)
export UA_GID=$(id -g)

# Users git config for the agent
export UA_GIT_NAME=$(git config user.name || echo "Cont Vibe")
export UA_GIT_EMAIL=$(git config user.email || echo "vibe@contvibe.sh.local")

# Detect docker compose command
COMPOSE_CMD="docker compose"
if ! docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
fi

# Build and run
cd "${contvibe_path}" # working dir for compose
source version_audit.sh
$COMPOSE_CMD build mistral-agent

# Security: Limit environment variables passed to container
# Only pass essential variables, filter out potential secrets
# Note: HOME and TERM are already set in compose.yaml environment section
$COMPOSE_CMD run --rm -e USER -e PATH \
  mistral-agent "${args[@]}"
