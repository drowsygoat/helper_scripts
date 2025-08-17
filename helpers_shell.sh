# Function to find a unique file based on a pattern in specified directories
function find_module_file() {
    local file_pattern=$1
    shift  # Remove the pattern argument from $@
    local search_dirs=("$@")
    local files_array=()

    # Iterate through each directory
    for dir in "${search_dirs[@]}"; do
        # Search for files matching the pattern in the directory (non-recursively)
        mapfile -t files_array < <(find "$dir" -maxdepth 1 -type f -regex "$file_pattern")

        if [[ ${#files_array[@]} -eq 1 ]]; then
            echo "${files_array[0]}"
            return 0
        fi
    done

    # Handle no or multiple matching files
    if [[ ${#files_array[@]} -eq 0 ]]; then
        echo "Error: No file matching '$file_pattern' found." >&2
    else
        echo "Error: Multiple files matching '$file_pattern' found." >&2
    fi
    return 1
}

function get_module_file_path() {
    local filename=".temp_modules"
    local search_dirs=("$PWD" "$HOME")

    for dir in "${search_dirs[@]}"; do
        local filepath="$dir/$filename"

        if [[ -f "$filepath" ]]; then
            echo "$filepath"
            return 0
        fi
    done

    echo "Warning: No '$filename' file found in current directory or home directory." >&2
    echo 'To use modules form a file, create a '$filename' file with a line like: "module load x y z" in either current directory or $HOME (the former will be prioritized)' >&2
    return 0
}

# Function to print the current job status
function print_job_status() {
    local current_status
    current_status=$(sacct --brief --jobs "$JOB_ID" | awk -v job_id="$JOB_ID" '$1 == job_id {print $1, $2}')

    if [[ "$last_status" != "$current_status" ]]; then
        echo ""
        echo "Monitoring job status for Job ID: $JOB_ID"
        echo "Current status: $current_status"
        last_status="$current_status"
    else
        echo -n "."
    fi
}

function is_job_active() {
    local active_jobs=$(sacct --jobs $JOB_ID | grep -E "RUNNING|PENDING" | wc -l)
    return $(( active_jobs == 0 ))
}

function is_completed() {
    local completed_jobs=$(sacct --jobs $JOB_ID | grep -E "COMPLETED" | wc -l)
    return $(( completed_jobs == 0 ))
}

# Function to handle interactive job monitoring
function interactive_mode() {
    tput setaf 3
    echo -e "Job ID $JOB_ID submitted at $TIMESTAMP."
    echo -e "Press 'c' to cancel the job or 'q' to stop monitoring."
    tput sgr0

    local input
    read -t 5 -n 1 input
    if [[ $input == "c" ]]; then
        cancel_job
    fi

    last_status="init"
    while is_job_active; do
        print_job_status
        read -t 5 -n 1 -s input
        if [[ $input == "c" ]]; then
            cancel_job
        elif [[ $input == "q" ]]; then
            stop_monitoring
        fi
    done

    echo ""
    echo "Job $JOB_ID has finished. Fetching final statistics..."
    sacct --format=elapsed,jobname,reqcpus,reqmem,state -j "$JOB_ID"
    echo -e "Job completed.\n"
}

# Helper function to cancel the job
function cancel_job() {
    scancel "$JOB_ID"
    rm -rf "${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}"
    tput setaf 1
    echo -e "\nOperation canceled by the user."
    tput sgr0
    exit 1
}

# Helper function to stop monitoring
function stop_monitoring() {
    tput setaf 1
    echo -e "\nMonitoring stopped by the user."
    tput sgr0
    exit 0
}

# Function to remove a directory if it's empty
remove_if_empty() {
    local dir=$1
    if [[ -d "$dir" ]]; then
        if [[ -z "$(ls -A "$dir")" ]]; then
            rmdir "$dir" && return 0 || return 3
        else
            return 1
        fi
    else
        return 2
    fi
}

# Function to perform a countdown before starting a job
function countdown() {
    local duration=$1
    echo -n "Job will start in "

    for ((i = duration; i > 0; i--)); do
        echo -n "$i... "
        read -t 1 -n 1 -s response
        if [[ $? -eq 0 ]]; then
            echo -e "\nOperation canceled by the user."
            exit 1
        fi
    done
    echo -e "\nJob is starting now..."
}

# Function to load modules
function load_modules() {
    if [ -n "${MODULES+x}" ]; then
        # Convert comma-separated string to array
        IFS=',' read -ra module_array <<< "$MODULES"
        
        echo "Loading modules from MODULES variable: ${MODULES}"
        for module in "${module_array[@]}"; do
            echo "Loading module: $module"
            module load "$module"
        done
    elif [ -n "${temp_modules+x}" ]; then
        echo "Using modules from ${temp_modules}"
        cat "${temp_modules}"
        source "${temp_modules}"
    fi
}

# Define foreground color variables using tput
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

# Define bright foreground color variables using tput
BRIGHT_BLACK=$(tput setaf 8)  # Often appears as gray
BRIGHT_RED=$(tput setaf 9)
BRIGHT_GREEN=$(tput setaf 10)
BRIGHT_YELLOW=$(tput setaf 11)
BRIGHT_BLUE=$(tput setaf 12)
BRIGHT_MAGENTA=$(tput setaf 13)
BRIGHT_CYAN=$(tput setaf 14)
BRIGHT_WHITE=$(tput setaf 15)

# Define background color variables using tput
BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

# Define bright background color variables using tput
BG_BRIGHT_BLACK=$(tput setab 8)  # Often appears as gray
BG_BRIGHT_RED=$(tput setab 9)
BG_BRIGHT_GREEN=$(tput setab 10)
BG_BRIGHT_YELLOW=$(tput setab 11)
BG_BRIGHT_BLUE=$(tput setab 12)
BG_BRIGHT_MAGENTA=$(tput setab 13)
BG_BRIGHT_CYAN=$(tput setab 14)
BG_BRIGHT_WHITE=$(tput setab 15)

# Reset color
NC=$(tput sgr0)  # No Color