#!/bin/bash

# Script to setup and submit a SLURM job with custom job settings and user input

# Define SLURM history directory
# SLURM_HISTORY="/cfs/klemming/projects/snic/sllstore2017078/${USER}-workingdir/slurm_history"

SLURM_HISTORY="$(pwd)/slurm_history"

source /cfs/klemming/projects/supr/sllstore2017078/kaczma-workingdir/helper_scripts/helpers_shell.sh

# Check if COMPUTE_ACCOUNT is set
if [[ -z "$COMPUTE_ACCOUNT" ]]; then
    echo "Error: COMPUTE_ACCOUNT is not defined." >&2
    exit 1
fi

# Check if USER_E_MAIL is set
if [[ -z "$USER_E_MAIL" ]]; then
    echo "Error: USER_E_MAIL is not defined." >&2
    exit 1
fi

# Check if SLURM history directory exists, if not, create it
if [[ ! -d "$SLURM_HISTORY" ]]; then
    echo "Creating SLURM history directory: $SLURM_HISTORY"
    mkdir -p "$SLURM_HISTORY"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create SLURM history directory!" >&2
        exit 1
    fi
fi

# Capture the current timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Clear any previous settings for these variables / probably not needeed, but does not hurt
unset TASKS JOB_TIME PARTITION CPUS NODES MEMORY DRY_RUN

# Default values for job settings  
JOB_NAME="unnamedjob"
NTASKS=1
NTASKS_PER_NODE=1
PARTITION="shared"
NODES=1
INTERACTIVE=0
CPUS=1
DRY_RUN="slurm"

function show_help() {
    echo ""
    echo "${BRIGHT_CYAN}Usage:${NC} ${YELLOW}run_shell_command.sh [options] -- '[command]'${NC}"
    echo ""
    echo "${BRIGHT_CYAN}Options:${NC}"
    echo "  ${BRIGHT_YELLOW}-J, --job-name${NC}        ${WHITE}[string]   Specify the job name (default: unnamed_job)${NC}"
    echo "  ${BRIGHT_YELLOW}-n, --ntasks${NC}          ${WHITE}[integer]  Set the number of tasks (default: 1)${NC}"
    echo "  ${BRIGHT_YELLOW}-m, --ntasks-per-node${NC} ${WHITE}[integer]  Set the number of tasks per node (default: 1)${NC}"
    echo "  ${BRIGHT_YELLOW}-t, --time${NC}            ${WHITE}[D-HH:MM:SS or integer]  Specify the job time (default: 24 hrs)${NC}"
    echo "                         - ${GREEN}Format:${NC} ${YELLOW}[D-HH:MM:SS]${NC} (e.g., ${YELLOW}1-12:30:00${NC} for 1 day, 12 hours, 30 minutes)"
    echo "                         - ${GREEN}If given as an integer (e.g., 5), it is treated as hours and converted${NC}"
    echo "                           (e.g., ${YELLOW}'5' → '0-05:00:00'${NC}, ${YELLOW}'30' → '1-06:00:00'${NC})"
    echo "  ${BRIGHT_YELLOW}-p, --partition${NC}       ${WHITE}[string]   Partition to run the job on (default: shared)${NC}"
    echo "                         ${GREEN}Options:${NC} ${YELLOW}core, node, shared, long, main, memory, devel${NC}"
    echo "  ${BRIGHT_YELLOW}-N, --nodes${NC}           ${WHITE}[integer]  Specify the number of nodes (default: 1)${NC}"
    echo "  ${BRIGHT_YELLOW}-i, --interactive${NC}     ${WHITE}           Run the job in interactive mode.${NC}"
    echo "  ${BRIGHT_YELLOW}-c, --cpus${NC}            ${WHITE}[integer]  Specify the number of CPUs (default: 1)${NC}"
    echo "                         - ${GREEN}This also determines the memory, so even if your job is single-threaded,"
    echo "                           ${GREEN}consider how much it needs to load to memory at once (1cpu == about 1.8GB of RAM).${NC}"
    echo "  ${BRIGHT_YELLOW}-M, --memory${NC}          ${WHITE}[string]   Set the memory allocation for SLURM (e.g., ${YELLOW}8G, 32G${NC})${NC}"
    echo "  ${BRIGHT_YELLOW}-o, --modules${NC}         ${WHITE}[string]   List of modules to load (comma-separated, e.g., '${YELLOW}python,gcc${NC}')${NC}"
    echo "                         - ${GREEN}If not provided, modules will be loaded from '~/.temp_modules'${NC}"
    echo "  ${BRIGHT_YELLOW}-d, --dry-run${NC}         ${WHITE}[string]   Enable dry run mode (default: slurm)${NC}"
    echo "                         ${GREEN}Options:${NC}"
    echo "                          ${YELLOW}dry${NC}       : ${WHITE}Prints the command without executing it.${NC}"
    echo "                          ${YELLOW}with_eval${NC} : ${WHITE}Executes the command in the current shell (ignoring SLURM-specific options).${NC}"
    echo "                          ${YELLOW}slurm${NC}     : ${WHITE}Executes the command with SLURM.${NC}"
    echo "  ${BRIGHT_YELLOW}-h, --help${NC}            ${WHITE}           Display this help message and exit${NC}"
    echo ""
    echo "${BRIGHT_CYAN}Notes:${NC}"
    echo "  - ${WHITE}The '[command]' should be enclosed in quotes and placed after '--'.${NC}"
    echo "  - ${WHITE}If '--modules' is not specified, the script will attempt to source '~/.temp_modules'.${NC}"
    echo "  - ${WHITE}Dry run modes allow different execution levels without running the full command.${NC}"
    echo ""

    echo "${BRIGHT_CYAN}Example 1 (very simple): Run a test commands with pipe using SLURM with default settings:${NC}"
    echo "  ${YELLOW}run_shell_command.sh -- 'echo "This really can be any command" | grep really'${NC}"
    echo ""

    echo "${BRIGHT_CYAN}Example 2: Run an R script with SLURM job submission:${NC}"
    echo "  ${YELLOW}run_shell_command.sh -J R_analysis -p long -n 1 -N 1 -c 4 -M 16G -t 2-00:00:00 -o 'PDC,R/4.4.1' -- 'Rscript my_analysis.R <arg1 arg2 ...>'${NC}"
    echo ""

    exit 0
}

if [ $# -eq 0 ]; then
    echo "No arguments provided. Displaying help:"
    # Call a function to display help
    show_help
    exit 1
fi

# Parse command-line options - works much better than getopts :)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -J|--job-name)
            JOB_NAME="$2"
            shift 2
            ;;
        -n|--ntasks)
            NTASKS="$2"
            shift 2
            ;;
        -m|--ntasks-per-node)
            NTASKS_PER_NODE="$2"
            shift 2
            ;;
        -t|--time)
            JOB_TIME="$2"
            shift 2
            ;;
        -p|--partition)
            PARTITION="$2"
            shift 2
            ;;
        -N|--nodes)
            NODES="$2"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE=1
            shift
            ;;
        -c|--cpus)
            CPUS="$2"
            shift 2
            ;;
        -M|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -o|--modules)
            MODULES="$2"
            shift 2
            ;;
        -a|--array)
            JOB_ARRAY="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Invalid option: $1" 1>&2
            show_help
            ;;
    esac
done

# Display parsed options for debugging
# echo "Job Name: $JOB_NAME"
# echo "Number of Tasks: $NTASKS"
# echo "Tasks per Node: $NTASKS_PER_NODE"
# echo "Job Time: $JOB_TIME"
# echo "Partition: $PARTITION"
# echo "Nodes: $NODES"
# echo "Interactive Mode: $INTERACTIVE"
# echo "CPUs: $CPUS"
# echo "Memory: $MEMORY"
# echo "Modules: $MODULES"
# echo "Job Array: $JOB_ARRAY"
# echo "Dry Run: $DRY_RUN"

# Output success message (optional)
echo -e "SLURM history directory is set to: ${BRIGHT_YELLOW}${SLURM_HISTORY}${NC}\n"

# Remaining arguments are treated as the command to run
ARGUMENTS="$@"

# Set the job name to the first argument if not explicitly set
JOB_NAME=${JOB_NAME:-$(echo $ARGUMENTS | awk '{print $1}')}

# Set default job time based on the partition
if [[ $PARTITION =~ (core|node|shared|long|main|memory) ]]; then
    JOB_TIME=${JOB_TIME:-23:59:00}
else 
    JOB_TIME=${JOB_TIME:-00:10:00} 
fi


# Function to check if JOB_TIME is in D-HH:MM:SS format
is_valid_format() {
    [[ "$1" =~ ^([0-9]+-)?([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]
}

# If JOB_TIME is an integer, treat it as hours and convert to d-HH:MM:SS
if [[ "$JOB_TIME" =~ ^[0-9]+$ ]]; then
    HRS=$((JOB_TIME % 24))  # Extract hours
    DAYS=$((JOB_TIME / 24))  # Extract days
    JOB_TIME=$(printf "%d-%02d:00:00" "$DAYS" "$HRS")
elif ! is_valid_format "$JOB_TIME"; then
    echo "Error: Invalid JOB_TIME format ($JOB_TIME)" >&2
    exit 1
fi

# Color settings for output using tput
color_key=$CYAN   # Blue color for keys
color_value=$RED  # Green color for values
color_reset=$NC   # Reset to default terminal color

# Display settings
# echo -e "Here are the current settings:"
echo -e "${color_key}Job name: ${color_value}$JOB_NAME${color_reset}"
echo -e "${color_key}Number of tasks: ${color_value}$NTASKS${color_reset}"
echo -e "${color_key}Number of cpus: ${color_value}$CPUS${color_reset}"
echo -e "${color_key}Number of nodes: ${color_value}$NODES${color_reset}"
echo -e "${color_key}Job time: ${color_value}$JOB_TIME${color_reset}"
echo -e "${color_key}Partition: ${color_value}$PARTITION${color_reset}"
echo -e "${color_key}E-mail: ${color_value}$USER_E_MAIL${color_reset}"
echo -e "${color_key}Account: ${color_value}$COMPUTE_ACCOUNT${color_reset}"
echo -e "${color_key}Run: ${color_value}$DRY_RUN${color_reset}"

if [ -n "${MEMORY:-}" ]; then
    echo -e "${color_key}Memory allocation: ${color_value}$MEMORY${color_reset}"
else
    echo -e "${color_key}Memory allocation: ${color_value}Not specified${color_reset}"
fi

if [ -n "${JOB_ARRAY:-}" ]; then
    echo -e "${color_key}Job array: ${color_value}$JOB_ARRAY${color_reset}"
else
    echo -e "${color_key}Job array: ${color_value}Not specified${color_reset}"
fi

if [ -n "${NTASKS_PER_NODE:-}" ]; then
    echo -e "${color_key}Tasks per node: ${color_value}$NTASKS_PER_NODE${color_reset}"
else
    echo -e "${color_key}Tasks per node: ${color_value}Not specified${color_reset}"
fi

SBATCH_SCRIPT="${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}/${JOB_NAME}_${TIMESTAMP}.sh"

# Create the SLURM job script with the specified parameters
if [[ $DRY_RUN == "dry" ]]; then
  echo -e "Command to evaluate:" 
  echo -e "$ARGUMENTS" 
  exit 0
elif [[ $DRY_RUN == "with_eval" ]]; then
  echo -e "\nEvaluating: $ARGUMENTS" 
  echo -e "Loading modules"
  load_modules
  echo "Check... OK"
  eval "$ARGUMENTS"
  echo -e "Finished."
  exit 0
fi

# Prepare the directory and SLURM script for the job
mkdir -p ${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}

# creating script file
cat <<EOF > "$SBATCH_SCRIPT"
#!/bin/bash -eu
#SBATCH -A ${COMPUTE_ACCOUNT}
#SBATCH -J ${JOB_NAME}
#SBATCH -o ${SLURM_HISTORY}/%x_${TIMESTAMP}/%x_%j_${TIMESTAMP}.out
#SBATCH -t ${JOB_TIME}
#SBATCH -p ${PARTITION}
#SBATCH -n ${NTASKS}
#SBATCH -N ${NODES}
#SBATCH -c ${CPUS}
#SBATCH --mail-user=${USER_E_MAIL:-lecka@liu.se}
#SBATCH --mail-type=ALL
EOF

if [ -n "${MEMORY:-}" ]; then
  echo "#SBATCH --mem ${MEMORY}" >> "$SBATCH_SCRIPT"
fi

if [ -n "${JOB_ARRAY:-}" ]; then
  echo "#SBATCH --array ${JOB_ARRAY}" >> "$SBATCH_SCRIPT"
fi

if [ -n "${NTASKS_PER_NODE:-}" ]; then
  echo "#SBATCH --ntasks-per-node ${NTASKS_PER_NODE}" >> "$SBATCH_SCRIPT"
fi

# if [ -n "${JOB_ARRAY:-}" ]; then
#   echo "export SLURM_ARRAY_TASK_ID" >> "$SBATCH_SCRIPT"
# fi

# Colors for pretty output
BRIGHT_MAGENTA='\033[1;35m'
NC='\033[0m' # No Color

# Safely expand ARGUMENTS
expanded_command=$(echo "$ARGUMENTS" | envsubst)

# Log the expanded command
mkdir -p "${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}"
echo -e "\nRunning command: ${BRIGHT_YELLOW}${expanded_command}${NC}" | tee "${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}/command.log"

# echo "CHUNK_ID=\$SLURM_ARRAY_TASK_ID" >> ${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}/job_steps.sh

echo "$ARGUMENTS" >> ${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}/job_steps.sh

chmod +x ${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}/job_steps.sh

# Generate SLURM job script
cat <<EOF >> "$SBATCH_SCRIPT"
load_modules
echo "Job \${SLURM_JOB_ID} for job name \${JOB_NAME} is running..."
start=\$(date +%s)

${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}/job_steps.sh

echo "Job \${SLURM_JOB_ID} for job name \${JOB_NAME} finished."
end=\$(date +%s)
runtime=\$((end-start))
echo "Runtime: \$((runtime/3600)) hours and \$(((runtime%3600)/60)) minutes."
EOF

if [[ $INTERACTIVE == 1 ]]; then
  countdown 3
fi

# Find a module file either in $HOME or the current working directory
temp_modules="$(get_module_file_path)"

# Check if the function was successful and the variable is not empty
if [ -n "$temp_modules" ]; then
    echo -e "Modules file is set to: ${BRIGHT_YELLOW}${temp_modules}${NC}"
    export temp_modules
else
    echo "No valid module file found."
fi

# Check if the MODULES variable is set and export it
if [ -n "$MODULES" ]; then
    echo -e "Loading modules:\n\t${BRIGHT_YELLOW}${MODULES}${NC}"
    export MODULES
fi

# Export other variables
export ARGUMENTS SLURM_JOB_ID JOB_NAME

# Export functions
export -f load_modules

echo -e "Job script will be saved to: ${BRIGHT_YELLOW}${SBATCH_SCRIPT}${NC}"
chmod +x "$SBATCH_SCRIPT"

JOB_ID=$(sbatch --parsable "$SBATCH_SCRIPT")

if [ -z "$JOB_ID" ]; then
    echo "Failed to submit job. Please check the SLURM script for errors."
    exit 1
fi

if [[ $INTERACTIVE == 1 ]]; then
  interactive_mode
fi

remove_if_empty "${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}"

status=$?

case $status in
    0)
        echo "Directory "${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}" was empty and has been removed."
        ;;
    1)
        echo -e "Slurm history and log files saved to: ${BRIGHT_YELLOW}${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}${NC}."
        ;;
    2)
        echo "Directory "${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}" does not exist."
        ;;
    3)
        echo "Failed to remove directory "${SLURM_HISTORY}/${JOB_NAME}_${TIMESTAMP}"."
        ;;
esac