#!/bin/bash

# Contract:
# 1. Host script sets environment and delegates to container runner
# 2. Filesystem state: ./agent-state (global), $WORK_PATH/.contvibe (local)
# 3. All non-namespaced flags pass through to vibe entrypoint

set -e

bind_path="/app"
contvibe_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
vibe_home="/home/python"
v_ver=$(tr -d '[:space:]' < "${contvibe_path}/VERSION" 2>/dev/null \
  || echo "v0.2.4-dev")

WORK_PATH="${WORK_PATH:-$(pwd)}"
VIBE_ARGS=()
PRINT_CONFIG=0
ENABLE_DOOD=0

parse_args() {
    local passthrough=0
    while [ "$#" -gt 0 ]; do
        if [ "$passthrough" -eq 1 ]; then
            VIBE_ARGS+=("$1")
            shift
            continue
        fi
        case "$1" in
            --)
                passthrough=1
                shift
                ;;
            --cv-print-config)
                PRINT_CONFIG=1
                shift
                ;;
            --cv-dood)
                ENABLE_DOOD=1
                shift
                ;;
            --workpath=*|--jailpath=*)
                WORK_PATH="${1#*=}"
                shift
                ;;
            --cv-*)
                echo "Unknown contvibe flag: $1" >&2
                return 1
                ;;
            *)
                echo "Passing argument to vibe: $1" >&2
                VIBE_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

canonicalize_paths() {
    WORK_PATH="${WORK_PATH/#\~/$HOME}"
    WORK_PATH="$(realpath -m "${WORK_PATH}")"
    if [ ! -d "${WORK_PATH}" ]; then
        echo "Error: WORK_PATH directory does not exist: ${WORK_PATH}" >&2
        return 1
    fi
    export WORK_PATH
    export bind_path
    export VIBE_HOME="${vibe_home}"
}

check_runner() {
    CONT_RUNNER=()
    local c
    for c in "podman compose" "podman-compose" \
             "docker compose" "docker-compose"; do
        if $c version >/dev/null 2>&1; then
            # shellcheck disable=SC2206
            CONT_RUNNER=($c)
            break
        fi
    done
    if [ "${#CONT_RUNNER[@]}" -eq 0 ]; then
        echo "Error: Container compose runner not found." >&2
        return 1
    fi
    if [[ "${CONT_RUNNER[*]}" =~ docker ]]; then
        [[ $(groups) =~ "docker" ]] || {
            echo "Error: $(whoami) not in docker group." >&2
            return 1
        }
    fi
}

check_version_update() {
    local stamp_f="${contvibe_path}/.state/.version_check"
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

prepare_state() {
    local agent_state="${contvibe_path}/agent-state"
    local old_cfg="${contvibe_path}/.vibe_config"
    mkdir -p "${contvibe_path}/.state"
    if [ -d "$old_cfg" ] && [ ! -d "$agent_state" ]; then
        mv "$old_cfg" "$agent_state"
    fi
    mkdir -p "${agent_state}/prompts"
    local cfg_file="${agent_state}/config.toml"
    if [ ! -f "$cfg_file" ]; then
        printf '[system]\nprompt_id = "default"\nstate_version = 1\n' \
          > "$cfg_file"
    fi
    if grep -q "state_version" "$cfg_file" 2>/dev/null; then
        local cur_ver
        cur_ver=$(grep 'state_version' "$cfg_file" | tr -dc '0-9')
        if [ "$cur_ver" != "1" ]; then
            echo "Notice: migrating agent-state from v${cur_ver} to v1"
            sed -i 's/state_version *= *[0-9]*/state_version = 1/' \
              "$cfg_file"
        fi
    else
        printf '\nstate_version = 1\n' >> "$cfg_file"
    fi
    mkdir -p "${WORK_PATH}/.contvibe"
    check_version_update
    local ign_f="${WORK_PATH}/.gitignore"
    if [ -f "$ign_f" ] && ! grep -qxF "/.contvibe/" "$ign_f"; then
        printf "\n# Contvibe state\n/.contvibe/\n" >> "$ign_f"
    fi
}

setup_identity() {
    local uid gid name email
    uid=$(id -u)
    gid=$(id -g)
    name=$(git config user.name || echo "Cont Vibe")
    email=$(git config user.email || echo "vibe@contvibe.sh.local")
    export UA_UID="${uid}"
    export UA_GID="${gid}"
    export UA_GIT_NAME="${name}"
    export UA_GIT_EMAIL="${email}"
}

build_image() {
    cd "${contvibe_path}"
    # shellcheck source=/dev/null
    source version_audit.sh
    local stamp_f="${contvibe_path}/.state/.last_pull"
    if [ ! -f "$stamp_f" ] || \
       [ -n "$(find "$stamp_f" -mtime +1 2>/dev/null)" ]; then
        echo "Checking for base image updates..."
        "${CONT_RUNNER[@]}" build --pull --quiet \
          mistral-agent 2>/dev/null || true
        touch "$stamp_f"
    else
        "${CONT_RUNNER[@]}" build mistral-agent
    fi
}

configure_dood() {
    if [ "$ENABLE_DOOD" -ne 1 ]; then
        return 0
    fi
    printf "\033[31m⚠️ WARNING: DooD enabled. " >&2
    printf "Container isolation boundary is broken!\033[0m\n" >&2
    local sock=""
    if [[ "${CONT_RUNNER[*]}" =~ podman ]]; then
        local user_sock
        user_sock="/run/user/$(id -u)/podman/podman.sock"
        if [ -S "$user_sock" ]; then
            sock="$user_sock"
        elif [ -S "/var/run/podman/podman.sock" ]; then
            sock="/var/run/podman/podman.sock"
        fi
    else
        if [ -S "/var/run/docker.sock" ]; then
            sock="/var/run/docker.sock"
        fi
        if ! id -nG 2>/dev/null | grep -qw "docker"; then
            echo "Error: DooD requires user to be in docker group." >&2
            return 1
        fi
    fi
    if [ -z "$sock" ] || [ ! -S "$sock" ]; then
        echo "Error: Container socket not found for DooD." >&2
        return 1
    fi
    DOOD_SOCK="$sock"
}

run_agent() {
    local run_opts=(
      run --rm
      -e USER="${USER}"
      -e PATH="${PATH}"
    )
    if [ "$ENABLE_DOOD" -eq 1 ] && [ -n "$DOOD_SOCK" ]; then
        run_opts+=(
          -v "${DOOD_SOCK}:/var/run/docker.sock"
        )
        if getent group docker >/dev/null 2>&1; then
            local docker_gid
            docker_gid=$(getent group docker | cut -d: -f3)
            run_opts+=(-u "${UA_UID}:${docker_gid}")
        fi
    fi
    "${CONT_RUNNER[@]}" "${run_opts[@]}" \
      mistral-agent "${VIBE_ARGS[@]}"
}

main() {
    parse_args "$@"
    canonicalize_paths
    if [ "$PRINT_CONFIG" -eq 1 ]; then
        echo "WORK_PATH=${WORK_PATH}"
        echo "bind_path=${bind_path}"
        echo "VIBE_HOME=${VIBE_HOME}"
        return 0
    fi
    check_runner
    prepare_state
    setup_identity
    configure_dood
    build_image
    run_agent
}

main "$@"
