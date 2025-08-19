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
