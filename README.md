# Nice-ODE Stack

## Package Availability 

The containers built by this repository are available here: (https://github.com/orgs/NiceODE-LLC/packages)


## Introduction

- This repository contains the instructions to build the containerized Nice-ODE stack from a linux machine
  - That is, linux desktop/cli -> linux container. Windows -> linux container is not supported at this time. 
- Nice-ODE is a framework for optimizing the parameters of ODE's. 
- Before building the stack you will need to install Docker. 
  - For a local docker install I have found the Docker Desktop application has some sharp edges that can be avoided by installing the standalone Docker Engine (https://docs.docker.com/engine/install/), then managing the engine with VSCode's Docker extension (https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers). 
  - Presumably you may also use Podman, but I have not tested it. 



## Components

- ./dockerfile
  - The central development container. 
  - Installs dependencies needed to work with an 'advanced' Python setup:
    - CUDA 12.4
    - Pre-baked, locked R environment cached in `/opt/renv/cache` via `renv.lock`
    - Pre-baked, locked Python environment installed in `/opt/poetry-venvs` via `poetry.lock`
    - Global CLI dev tools (`radian`, `ruff`, `jupyterlab`)
    - Preserves full mutability for both Python and R in dev containers
- ./.devcontainer/
  - Dev container configuration with Docker-outside-of-Docker and Python 3.13 for building containers in an isolated VS Code environment.
- ./mlflow_image/
  - A local mlflow (https://mlflow.org/) server to track your work
  - Connects to a default PostgreSQL container defined in Nice-ODE's runtime docker compose file (not in this repo)
- ./gemma_llm/
  - **Not** constructed by default
  - A local Gemma 3 sever 
  - You will need you own Hugging Face API key provisioned with read access to download the model weights.
  - Does not provide any additional functionality to the Nice-ODE stack. 


## Building
1) Clone this repo to your PC.
2) Open Terminal and `cd` into the directory where the repo was cloned
   1) eg. `git_repos/nice-ode-stack`

3) Run the bash script `docker-compose-timestamp.sh` as shown below. 
   1) The compose log will be stored in `./docker_compose.log`. 
   2) If you run the command multiple times, consider updating the command to save the log to, for example, `docker_compose2.log`, `docker_compose3.log` etc. 

- See the `docker_compose.log_example` if you want to check out what your log should look like. 
- `docker_compose.log_example` is a text file and can be opened in any text editor. 
- The file type is `.log_example` rather than `.log` because `.log` is ignored by git. 



```
your-machine-name:~/git_repos/nice-ode-stack$ ./docker-compose-timestamp.sh > docker_compose.log 2>&1
```
