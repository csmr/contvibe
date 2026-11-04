#!/bin/bash

set -e

# default working directory path (defaults to current directory)
export WORK_PATH="${WORK_PATH:-$(pwd)}"

# target mount path, in container filesystem
export bind_path="/app"

# vibe.sh script location
contvibe_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# agent container home dir
vibe_home="/home/python"
export VIBE_HOME="${vibe_home}"
v_ver=$(tr -d '[:space:]' < "${contvibe_path}/VERSION" 2>/dev/null \
  || echo "v0.2.4-dev")

check_version_update() {
    local stamp_f="${contvibe_path}/.vibe_config/.version_check"
    if [ ! -f "$stamp_f" ] || \
       [ -n "$(find "$stamp_f" -mtime +1 2>/dev/null)" ]; then
        (
            local remote_url=\
"https://raw.githubusercontent.com/csmr/contvibe/main/VERSION"
            local remote_ver
            remote_ver=$(curl -sSL "$remote_url" 2>/dev/null \
              | tr -d '[:space:]')
            if [[ -n "$remote_ver" && "$remote_ver" != "$v_ver" ]]; then
                printf "\n\033[33m💡 New version available: %s" "$remote_ver"
                printf " (Current: %s)\033[0m\n" "$v_ver"
                printf "\033[33mRun './contvibe.sh --self-update' "
                printf "to pull the latest changes.\033[0m\n\n"
            fi
        ) &
        touch "$stamp_f"
    fi
}

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

# Determine container compose runner
CONT_RUNNER=()
for c in "podman compose" podman-compose "docker compose" docker-compose; do
    if $c version >/dev/null 2>&1; then
        CONT_RUNNER=($c)
        break
    fi
done

if [[ ${#CONT_RUNNER[@]} -eq 0 ]]; then
    echo "Error: Container compose runner not found."
    exit 1
fi

# Sanity check: Docker group if runner uses docker
if [[ "${CONT_RUNNER[*]}" =~ docker ]]; then
    [[ $(groups) =~ "docker" ]] || {
        echo "Error: $(whoami) not in docker group."
        exit 1
    }
fi

# persistent directories
# for Vibe files
mkdir -p "${contvibe_path}/.vibe_config"
# persists/home/agent
mkdir -p "${WORK_PATH}/.contvibe"

# check version update in background
check_version_update

# .gitignore adderifier
ign_f="${WORK_PATH}/.gitignore"
v_state=".contvibe"
if [ -f "$ign_f" ]; then
    if ! grep -qxF "/$v_state/" "$ign_f"; then
        printf "\n# Contvibe state\n/$v_state/\n" >> "$ign_f"
    fi
fi

# Identity exports for the container
export UA_UID=$(id -u)
export UA_GID=$(id -g)

# Users git config for the agent
export UA_GIT_NAME=$(git config user.name || echo "Cont Vibe")
export UA_GIT_EMAIL=$(git config user.email || echo "vibe@contvibe.sh.local")

# Build and run
cd "${contvibe_path}" # working dir for compose
source version_audit.sh

# Check for updates once per day automatically
stamp_f="${contvibe_path}/.vibe_config/.last_pull"
if [ ! -f "$stamp_f" ] || [ -n "$(find "$stamp_f" -mtime +1 2>/dev/null)" ]
then
    echo "Checking for base image updates..."
    "${CONT_RUNNER[@]}" build --pull --quiet mistral-agent 2>/dev/null || true
    touch "$stamp_f"
else
    "${CONT_RUNNER[@]}" build mistral-agent
fi

# Security: Limit environment variables passed to container
# Only pass essential variables, filter out potential secrets
# Note: HOME and TERM are already set in compose.yaml environment section
"${CONT_RUNNER[@]}" run --rm \
  -e USER="${USER}" \
  -e PATH="${PATH}" \
  mistral-agent "${args[@]}"
