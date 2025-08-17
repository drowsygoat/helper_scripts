#!/bin/bash

if ! command -v singularity &> /dev/null; then
    module load PDC singularity
fi

# Export host PATH to container
export SINGULARITYENV_APPEND_PATH="$PATH"

export SINGULARITY_CACHEDIR=/cfs/klemming/projects/supr/sllstore2017078/${USER}-workingdir/nobackup/SINGULARITY_CACHEDIR
export SINGULARITY_TMPDIR=/cfs/klemming/projects/supr/sllstore2017078/${USER}-workingdir/nobackup/SINGULARITY_TMPDIR

export APPTAINER_CACHEDIR=$SINGULARITY_CACHEDIR
export APPTAINER_TMPDIR=$SINGULARITY_TMPDIR

mkdir -p "$SINGULARITY_CACHEDIR" "$SINGULARITY_TMPDIR"

export R_ENVIRON_USER="$HOME/.Renviron"
export R_PROFILE_USER="$HOME/.Rprofile"

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RESET='\033[0m'

# Emoji helpers
info()    { echo -e "${CYAN}🧠 $1${RESET}"; }
success() { echo -e "${GREEN}✅ $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${RESET}"; }
error()   { echo -e "${RED}❌ $1${RESET}"; }
task()    { echo -e "${BLUE}📦 $1${RESET}"; }
command() { echo -e "${YELLOW}🎯 Running:${RESET} $1"; }

# Function to display usage
usage() {
    echo -e "${CYAN}🧠 Usage:${RESET} $0 -d <docker_image> [-B <host_path>]... [-b] [-c] [-C] <command> [args...]"
    echo -e "${CYAN}🧠 Options:${RESET}"
    echo "  -d <image>    Docker image"
    echo "  -H <path>     Use a custom home directory inside the container"
    echo "  -B <path>     Additional bind mount(s), can be repeated or comma-separated"
    echo "  -b            Binds /cfs/.../<user>-workingdir instead of current working dir"
    echo "  -s            Skip Docker image digest check and reuse cached sandbox if it exists"
    echo "  -c            Use '--cleanenv' (resets container environment)"
    echo "  -C            Use '--contain' (isolates container environment)"
    echo "  -h            Show this help message"
    exit 1
}

# Set defaults
SINGULARITY_OPTIONS=""
USE_CUSTOM_BIND=false
SKIP_UPDATE_CHECK=false
declare -a CUSTOM_BIND_PATHS
DOCKER_IMAGE=""
LOCAL_BASE_PATH="/cfs/klemming/projects/supr/sllstore2017078/${USER}-workingdir"
CONTAINER_BASE_PATH="/mnt"

# Parse options
while getopts ":d:B:bcCH:sh" opt; do
    case ${opt} in
        d) DOCKER_IMAGE="$OPTARG" ;;
        B) CUSTOM_BIND_PATHS+=("$OPTARG") ;;
        b) USE_CUSTOM_BIND=true ;;
        c) SINGULARITY_OPTIONS+=" --cleanenv" ;;
        C) SINGULARITY_OPTIONS+=" --contain" ;;
        s) SKIP_UPDATE_CHECK=true ;;
        H) CUSTOM_HOME="$OPTARG" ;;
        h) usage ;;
        \?) error "Invalid option: -$OPTARG"; usage ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$DOCKER_IMAGE" ]; then
    error "Docker image is required (-d)"
    usage
fi

[[ "$DOCKER_IMAGE" != *:* ]] && DOCKER_IMAGE="${DOCKER_IMAGE}:latest"

if [ "$#" -lt 1 ]; then
    error "Missing command to run inside the container."
    usage
fi

SANDBOX_MAP_FILE="${SINGULARITY_CACHEDIR}/sandbox_map.txt"

if [ "$SKIP_UPDATE_CHECK" = true ]; then
    if [ -f "$SANDBOX_MAP_FILE" ]; then
        SANDBOX_PATH=$(awk -v image="$DOCKER_IMAGE" -F'\t' '$1 == image { print $2 }' "$SANDBOX_MAP_FILE")
    fi

    if [ -z "$SANDBOX_PATH" ] || [ ! -d "$SANDBOX_PATH" ]; then
        error "No cached sandbox found for image '$DOCKER_IMAGE'. Run without -s first to generate the sandbox."
        exit 1
    fi
    info "Using sandbox from cache map: $SANDBOX_PATH"
else
    HASH=$(echo "$DOCKER_IMAGE" | sha256sum | awk '{print $1}')
    SANDBOX_PATH="${SINGULARITY_CACHEDIR}/sandbox_${HASH}"
fi

DIGEST_FILE="${SANDBOX_PATH}/.docker_digest"
SKOPEO_IMAGE="${SINGULARITY_CACHEDIR}/skopeo_latest.sif"

if [ "$SKIP_UPDATE_CHECK" = false ]; then
    if [ ! -f "$SKOPEO_IMAGE" ]; then
        task "Pulling skopeo image into cache..."
        singularity build "$SKOPEO_IMAGE" docker://quay.io/skopeo/stable:latest || {
            error "Failed to pull skopeo container image."
            exit 1
        }
    fi

    REMOTE_DIGEST=$(singularity exec "$SKOPEO_IMAGE" skopeo inspect --raw "docker://$DOCKER_IMAGE" 2>/dev/null | sha256sum | awk '{print $1}')
    info "Remote digest: $REMOTE_DIGEST"

    if [ -f "$DIGEST_FILE" ]; then
        CACHED_DIGEST=$(cat "$DIGEST_FILE")
    else
        CACHED_DIGEST=""
    fi
    info "Cached digest: $CACHED_DIGEST"
else
    info "Skipping Docker image digest check due to -s flag."
fi

if [ "$SKIP_UPDATE_CHECK" = true ] && [ -d "$SANDBOX_PATH" ]; then
    success "Using cached sandbox (digest check skipped): $SANDBOX_PATH"
elif [ "$SKIP_UPDATE_CHECK" = false ] && { [ "$REMOTE_DIGEST" != "$CACHED_DIGEST" ] || [ ! -d "$SANDBOX_PATH" ]; }; then
    task "Building sandbox at: $SANDBOX_PATH (Docker image has changed or cache missing)"
    rm -rf "$SANDBOX_PATH"
    singularity build --sandbox "$SANDBOX_PATH" "docker://${DOCKER_IMAGE}" || {
        error "Failed to build sandbox from Docker image."
        exit 1
    }
    echo "$REMOTE_DIGEST" > "$DIGEST_FILE"

    touch "$SANDBOX_MAP_FILE"
    awk -v image="$DOCKER_IMAGE" -F'\t' '$1 != image' "$SANDBOX_MAP_FILE" > "${SANDBOX_MAP_FILE}.tmp"
    echo -e "${DOCKER_IMAGE}\t${SANDBOX_PATH}" >> "${SANDBOX_MAP_FILE}.tmp"
    mv "${SANDBOX_MAP_FILE}.tmp" "$SANDBOX_MAP_FILE"
else
    success "Using cached sandbox: $SANDBOX_PATH"
fi

CONTAINER_SOURCE="$SANDBOX_PATH"

for entry in "${CUSTOM_BIND_PATHS[@]}"; do
    IFS=',' read -ra paths <<< "$entry"
    for path in "${paths[@]}"; do
        if [ -d "$path" ]; then
            SINGULARITY_OPTIONS+=" --bind ${path}:${path}"
        else
            warn "Skipping bind path '${path}' (not found)"
        fi
    done
done

if [ -n "$CUSTOM_HOME" ]; then
    if [ -d "$CUSTOM_HOME" ]; then
        SINGULARITY_OPTIONS+=" --no-home --home ${CUSTOM_HOME}"
        SINGULARITY_OPTIONS+=" --bind ${CUSTOM_HOME}"
    else
        error "Custom home path '${CUSTOM_HOME}' does not exist."
        exit 1
    fi
fi

if [ "$USE_CUSTOM_BIND" = true ]; then
    SINGULARITY_OPTIONS+=" --bind ${LOCAL_BASE_PATH}:${LOCAL_BASE_PATH}"
    CONTAINER_DIR="${PWD}"
else
    SINGULARITY_OPTIONS+=" --bind ${PWD}:${PWD}"
    CONTAINER_DIR="${PWD}"
fi

# if ! ml --terse 2>&1 | grep -q "^PDC/singularity"; then
#     ml PDC singularity
# fi

COMMAND="$@"
command "singularity exec ${SINGULARITY_OPTIONS} --pwd ${CONTAINER_DIR} ${CONTAINER_SOURCE} ${COMMAND}"

singularity exec ${SINGULARITY_OPTIONS} --pwd "${CONTAINER_DIR}" "${CONTAINER_SOURCE}" ${COMMAND}
