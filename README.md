# Using Docker with Singularity on the Dardel Cluster

This guide provides step-by-step instructions for creating, deploying, and running containers using Docker and Singularity on the Dardel cluster.

---

## 1. Prepare the Container with Docker

### Save Modifications to the Docker Container
If you've modified a running container, save its state as a new image:
```bash
docker commit <container_id_or_name> <repository>:<tag>
```
Example:
```bash
docker commit flamboyant_agnesi drowsygoat/r_archr:1.0.4
```

### Push the Image to Docker Hub
Upload the container image to Docker Hub for easy access from the cluster:
```bash
docker push <repository>:<tag>
```
Example:
```bash
docker push drowsygoat/r_archr:1.0.4
```

### Test or Modify the Image Locally
Before deploying, verify and refine the container by running it locally:
```bash
docker run -it -v $(pwd):/mnt <repository>:<tag>
```
Example:
```bash
docker run -it -v $(pwd):/mnt drowsygoat/r_archr:1.0.3
```

---

## 2. Deploy the Container on the Dardel Cluster

### Pull the Docker Image with Singularity
Load Singularity module if not loaded
```bash
ml singularity
```
Pull the Docker container into a Singularity Image Format (SIF) file:
```bash
singularity pull -F <output_filename>.sif docker://<repository>:<tag>
```
Example:
```bash
singularity pull -F r_archr.sif docker://drowsygoat/r_archr:1.0.4
```

### Run the Container on the Cluster
Use the `sing.sh` script to execute commands inside the container:
```bash
sing.sh -B <bind_path> <sandbox_name> <command> [options...]
```
Example:
```bash
sing.sh -B /cfs/klemming/ r_archr Rscript "$my_script" --dir "$JOB_NAME" --name "$sample_id" --sample "$sample_path" --threads "$cpus" --gtf "$anno"
```

---

## 3. Understanding the `sing.sh` Script

The `sing.sh` script simplifies running containers on the cluster with proper bindings and environment isolation.

### Key Features
- **Default Paths**:
  - **Local Base Path**: `/cfs/klemming/projects/snic/sllstore2017078/lech`
  - **Container Base Path**: `/mnt`
  - **Sandboxes Path**: `/cfs/klemming/projects/supr/sllstore2017078/lech/singularity_sandboxes`

- **Singularity Options**:
  - `-b`: Bind custom paths for local and container base directories.
  - `-B`: Bind additional custom paths (same in host and container).
  - `-c`: Use `--cleanenv` for a clean environment.
  - `-C`: Use `--contain` for container isolation.

### Usage Syntax
```bash
sing.sh [-b] [-B <host_path>] [-c] [-C] <sandbox_name> <command> [options...]
```

### How It Works
1. **Bind Paths**: The script binds directories between the host and the container.
   - By default, it binds the current working directory.
   - With `-b`, it binds `LOCAL_BASE_PATH` to `CONTAINER_BASE_PATH`.
   - With `-B`, it binds additional custom paths.

2. **Environment Options**:
   - `--cleanenv`: Clears the container’s environment, using only the provided variables.
   - `--contain`: Isolates the container from the host system.

3. **Run Command**:
   The container is executed using `singularity exec`:
   ```bash
   singularity exec ${SINGULARITY_OPTIONS} --pwd "${CONTAINER_DIR}" "${SANDBOXES_PATH}/${SANDBOX_NAME}" ${COMMAND}
   ```

### Example
To run an R script within the container:
```bash
sing.sh -B /cfs/klemming/ r_archr Rscript "$my_script" --dir "$JOB_NAME" --name "$sample_id" --sample "$sample_path" --threads "$cpus" --gtf "$anno"
```

---

## 4. Workflow Summary

1. Use Docker to create and test your container.
2. Push the container to Docker Hub for deployment.
3. Pull the container on the Dardel cluster using Singularity.
4. Run the container on the cluster using `sing.sh` script  with appropriate options.


# Using AWS in a Singularity Container

This guide provides instructions on how to configure and use AWS CLI inside a **Singularity** container, as well as how to pull the container from Docker as a SIF file.

---

## **1. Pulling the Container from Docker and Converting to SIF**

To use the **bioinfo_toolkit** container, you need to first pull it from Docker and convert it to a **SIF (Singularity Image Format)** file.

Run the following command:

```bash
singularity pull -F bioinfo_toolkit.sif docker://drowsygoat/bioinfo_toolkit:latest
```

This will download the container as **`bioinfo_toolkit.sif`**.

---

## **2. Running the Singularity Container and Configuring AWS**

Once you have the **SIF file**, you can execute AWS commands inside the container.

### **2.1 Start the Singularity Container**

```bash
singularity exec --bind /your/local/path:/your/container/path --pwd /your/container/path bioinfo_toolkit.sif bash
```

- Replace **`/your/local/path`** with the directory you want to mount inside the container.
- Replace **`/your/container/path`** with the working path inside the container.

Alternatively, you can use **`sing_v2.sh`** to run it after adding:

```bash
export PATH=$PATH:/cfs/klemming/projects/snic/sllstore2017078/kaczma-workingdir/RR/scAnalysis/scripts_chicken_repo/helper_scripts
```

to your `.bashrc` (or another shell configuration file).

---

### **2.2 Configure AWS Inside the Container**

Run the following command:

```bash
sing.sh bioinfo_toolkit aws configure
```

You will be prompted to enter your AWS credentials:

```
AWS Access Key ID [None]: <your-access-key>
AWS Secret Access Key [None]: <your-secret-key>
Default region name [None]:
Default output format [None]:
```

---

### **2.3 Verify AWS Configuration**

Check that the credentials are saved correctly:

```bash
sing.sh bioinfo_toolkit cat ~/.aws/credentials
```

Check the configured region:

```bash
sing.sh bioinfo_toolkit cat ~/.aws/config
```

---

### **2.4 Perform an AWS S3 Sync Operation (Dry Run)**

To test an **S3 sync** operation without making actual changes, use:

```bash
sing.sh bioinfo_toolkit aws s3 sync s3://bmkdatarelease-3/delivery_2025022415420100000268/ ./ --dry-run
```

---

### **2.5 Perform a Real AWS S3 Sync Operation**

Once confirmed, run:

```bash
sing.sh bioinfo_toolkit aws s3 sync s3://bmkdatarelease-3/delivery_2025022415420100000268/ ./ --exact-timestamps
```

If you want to **log the output** of the sync operation for review, run:

```bash
sing.sh bioinfo_toolkit aws s3 sync s3://bmkdatarelease-3/delivery_2025022415420100000268/ ./ --dryrun >> ../aws.txt
```

This will download the files from S3 to your local directory.

---

## **3. Exiting the Singularity Container**

Once done, exit the container:

```bash
exit
```

or use:

```bash
Ctrl + D
```

---

## **4. Additional Notes**
- If you encounter issues with modules or dependencies inside the container, try restoring system defaults using:

  ```bash
  source /opt/cray/pe/cpe/23.12/restore_lmod_system_defaults.sh
  ```

---
