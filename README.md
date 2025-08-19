# Using Docker with Singularity on the Dardel Cluster

This guide explains how to create, deploy, and run containers using **Docker** locally and **Singularity** on the Dardel cluster — with the **`docker_sing.sh`** helper script for automatic container pulling and caching.

---

## 1. Build and Test Your Docker Container Locally

### Save Changes to a Container
```bash
docker commit <container_id_or_name> <repository>:<tag>
```

### Push to Docker Hub
```bash
docker push <repository>:<tag>
```

### Test Locally
```bash
docker run -it -v $(pwd):/mnt <repository>:<tag>
```

---

## 2. Deploy on Dardel with `docker_sing.sh`

The **`docker_sing.sh`** script:
- Pulls Docker images into a **Singularity sandbox**.
- Caches the sandbox for future runs.
- Checks if the Docker image has changed (digest check).
- Allows skipping the digest check with `-s` to reuse cache.

---

### Options

| Flag | Description |
|------|-------------|
| `-d <image>` | Docker image (with optional `:tag`, default `latest`) |
| `-B <path>` | Additional bind mount(s), can be repeated or comma-separated |
| `-b` | Bind `/cfs/.../<user>-workingdir` instead of current working dir |
| `-s` | Skip digest check and reuse cached sandbox |
| `-c` | Use `--cleanenv` (reset environment inside container) |
| `-C` | Use `--contain` (isolate from host filesystem) |
| `-H <path>` | Custom home directory inside container |
| `-h` | Show help message |

---

### Default Paths
- **Local base path**:  
  `/cfs/klemming/projects/supr/sllstore2017078/${USER}-workingdir`
- **Container base path**:  
  `/mnt`
- **Cache directories**:  
  ```
  $SINGULARITY_CACHEDIR=/cfs/.../${USER}-workingdir/nobackup/SINGULARITY_CACHEDIR
  $SINGULARITY_TMPDIR=/cfs/.../${USER}-workingdir/nobackup/SINGULARITY_TMPDIR
  ```

---

## 3. Workflow Summary

1. **Build & test** the container with Docker locally.
2. **Push** it to Docker Hub.
3. On Dardel, run with:
   ```bash
   docker_sing.sh -d <repository>:<tag> <command> [args...]
   ```
---

## 4. Troubleshooting

- **Module not found**:  
  ```bash
  module load PDC singularity
  ```
- **Cache problems**: Remove the cached sandbox in `$SINGULARITY_CACHEDIR` and rerun without `-s`.
- **Custom binds**: Use `-B` for extra bind mounts into the container.

---

**Example: AWS S3 Sync Inside Container**
```bash
docker_sing.sh -d drowsygoat/bioinfo_toolkit aws s3 sync \
  s3://mybucket/data ./ --dry-run
```

# SLURM Job Submission Helper

A flexible Bash script for setting up and submitting SLURM jobs with custom job settings, environment checks, and automatic history logging.  
---

## Quick Setup

```bash
# Clone the repository
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>

# Make the script executable
chmod +x run_shell_command.sh

# (Optional) Add to PATH for global use
echo 'export PATH="$PATH:$(pwd)"' >> ~/.bashrc
# If you use zsh: echo 'export PATH="$PATH:$(pwd)"' >> ~/.zshrc
source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null
```

Run a quick test:
```bash
run_shell_command.sh -- 'echo "Hello SLURM!"'
```
---

## Usage

```bash
run_shell_command.sh [options] -- '[command]'
```

### Common Options
- `-J, --job-name`            Job name (default: `unnamedjob`)
- `-n, --ntasks`              Number of tasks (default: `1`)
- `-m, --ntasks-per-node`     Tasks per node (default: `1`)
- `-c, --cpus`                CPUs per task (default: `1`)
- `-N, --nodes`               Number of nodes (default: `1`)
- `-M, --memory`              Memory (e.g., `8G`, `32G`)
- `-t, --time`                Wall time (`D-HH:MM:SS` **or** integer hours)
- `-p, --partition`           Partition (default: `shared`; options: `core,node,shared,long,main,memory,devel`)
- `-a, --array`               Job array range (e.g., `0-99%10`)
- `-o, --modules`             Comma-separated modules (e.g., `python,gcc`)
- `-i, --interactive`         Enable interactive monitoring (details below)
- `-d, --dry-run`             `dry` | `with_eval` | `slurm` (default: `slurm`)
- `-h, --help`                Show full help

> **Note:** Place your shell command **after** `--`, wrapped in single quotes.

---

## Module Handling

Modules can be provided in two ways:

1) **Inline via CLI**
```bash
run_shell_command.sh -o 'PDC,R/4.4.1' -- 'Rscript analysis.R'
```

2) **From a file named `.temp_modules`** (auto-detected in **current dir** first, then `$HOME`)
```bash
# .temp_modules (example)
module load PDC R/4.4.1
module load gcc
```

Helpers used:
- `get_module_file_path`: finds `.temp_modules` in `$PWD` or `$HOME`.
- `load_modules`: loads comma-separated modules from `--modules` or sources `.temp_modules`.

---

## Examples

**1) Simple command with default settings**
```bash
run_shell_command.sh -- 'echo "This can be any command" | grep any'
```

**2) R job with resources and modules**
```bash
run_shell_command.sh \
  -J R_analysis -p long -n 1 -N 1 -c 4 -M 16G -t 2-00:00:00 \
  -o 'PDC,R/4.4.1' -- \
  'Rscript my_analysis.R arg1 arg2'
```

**3) Job array (may not work yet)**
```bash
run_shell_command.sh -J array_demo -a 0-9%2 -- './run_one.sh ${SLURM_ARRAY_TASK_ID}'
```

**4) Dry-run modes**
```bash
# Only print the command
run_shell_command.sh -d dry -- 'python train.py'

# Evaluate locally in the current shell (no SLURM)
run_shell_command.sh -d with_eval -o 'python' -- 'python script.py --quick-test'
```

---

## SLURM History & Logs

Job logs are stored under:
```
./slurm_history/<job_name>_<timestamp>/
```
- The generated **SLURM script** (`<job>_<timestamp>.sh`)
- **STDOUT log** (`<job>_<jobid>_<timestamp>.out`)
- **Command log** (`command.log`) with the command
- **Script** (`job_steps.sh`) executed by SLURM

Empty history directories are automatically removed.

---

## Requirements

- SLURM workload manager (`sbatch`, `sacct`, `scancel`).
- Bash ≥ 4.x.
- Environment variables set:
  - `COMPUTE_ACCOUNT` – your SLURM account/project.
  - `USER_E_MAIL` – email for `--mail-user`.
- `.temp_modules` file in `$PWD` or `$HOME`, or `--modules` CLI flag.
- A `helpers_shell.sh` providing functions used by the script.

---