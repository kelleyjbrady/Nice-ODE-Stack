#!/bin/bash
set -e

# --- Capture Git Commit for OCI Labels ---
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  GIT_COMMIT="${GIT_COMMIT}-dirty"
  echo "WARNING: Building with uncommitted changes ($GIT_COMMIT)"
else
  echo "Building images for commit: $GIT_COMMIT"
fi

# --- Configuration ---
DEV_IMAGE_BASE_NAME="cuda-py"
MLFLOW_IMAGE_BASE_NAME="mlflow-postgres"
GEMMA_IMAGE_BASE_NAME="gemma-llm"
TENSORBOARD_IMAGE_BASE_NAME="tensorboard"
COMPOSE_DEV=1
COMPOSE_MLFLOW=1
COMPOSE_TENSORBOARD=1
COMPOSE_GEMMA=0
PUSH_TO_REG=1
NO_CACHE_FLAG="--no-cache"

# If specific image targets or flags (--no-push, --cache) are passed as arguments,
# apply them; otherwise use the defaults above.
TARGETS=()
for arg in "$@"; do
    case "$arg" in
        --no-push) PUSH_TO_REG=0 ;;
        --cache) NO_CACHE_FLAG="" ;;
        dev|mlflow|tensorboard|gemma) TARGETS+=("$arg") ;;
        *)
            echo "Unknown argument: '$arg'. Valid targets: dev, mlflow, tensorboard, gemma; optional flags: --no-push, --cache"
            exit 1
            ;;
    esac
done

if [ "${#TARGETS[@]}" -gt 0 ]; then
    COMPOSE_DEV=0
    COMPOSE_MLFLOW=0
    COMPOSE_TENSORBOARD=0
    COMPOSE_GEMMA=0
    for target in "${TARGETS[@]}"; do
        case "$target" in
            dev) COMPOSE_DEV=1 ;;
            mlflow) COMPOSE_MLFLOW=1 ;;
            tensorboard) COMPOSE_TENSORBOARD=1 ;;
            gemma) COMPOSE_GEMMA=1 ;;
        esac
    done
fi

REGISTRY_PATH="ghcr.io/niceode-llc"

# Path to the PK-Analysis repo's .env file (checks devcontainer mount first, then sibling directory)
if [ -d "/workspaces/PK-Analysis" ]; then
    PK_ANALYSIS_REPO_PATH="/workspaces/PK-Analysis"
else
    PK_ANALYSIS_REPO_PATH="../PK-Analysis"
fi
PK_ANALYSIS_ENV_FILE="${PK_ANALYSIS_REPO_PATH}/.env"


DEV_BUILD_TAG=$(date +%Y%m%d%H%M%S)
export BUILD_TAG=${DEV_BUILD_TAG}

# --- Dev Image Build Process ---
if [ "$COMPOSE_DEV" -eq 1 ]; then
    echo "Starting DEV IMAGE build process..."
    LOCAL_DEV_IMAGE_NAME_WITH_TAG="${DEV_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"
    REGISTRY_DEV_IMAGE_NAME_WITH_TAG="${REGISTRY_PATH}/${DEV_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"

    echo "Building dev image. It will be tagged as '${LOCAL_DEV_IMAGE_NAME_WITH_TAG}' by docker-compose.yml"
    docker compose -f ./docker-compose.yml build \
      --build-arg GIT_COMMIT="${GIT_COMMIT}" \
      ${NO_CACHE_FLAG} dev_env_builder

    echo "Tagging dev image for registry: ${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"
    docker tag "${LOCAL_DEV_IMAGE_NAME_WITH_TAG}" "${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"

    if [ "$PUSH_TO_REG" -eq 1 ]
    then
        echo "Pushing dev image: ${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"
        docker push "${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"
        echo "--------------------------------------------------"
        echo " DEV IMAGE Build Complete!"
        echo " Pushed: ${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"
        echo "--------------------------------------------------"
    else
        echo "Image push skipped because PUSH_TO_REG==0"
        echo "--------------------------------------------------"
        echo " DEV IMAGE Build Complete!"
        echo "--------------------------------------------------"
    fi
else
    REGISTRY_DEV_IMAGE_NAME_WITH_TAG="dev_is_not_composed"
    echo "Skipping DEV IMAGE Build"
fi


# --- MLflow Extended Image Build Process ---
echo ""
if [ "$COMPOSE_MLFLOW" -eq 1 ]; then
    echo "Starting MLFLOW EXTENDED IMAGE build process..."
    FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY="${REGISTRY_PATH}/${MLFLOW_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"

    echo "Building MLFLOW EXTENDED image: ${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}"
    docker build --no-cache \
      --build-arg GIT_COMMIT="${GIT_COMMIT}" \
      -t "${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}" ./mlflow_image/

    if [ "$PUSH_TO_REG" -eq 1 ]
    then
        echo "Pushing MLFLOW EXTENDED image: ${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}"
        docker push "${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}"
        echo "--------------------------------------------------"
        echo " MLFLOW EXTENDED IMAGE Build Complete!"
        echo " Pushed: ${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}"
        echo "--------------------------------------------------"
    else
        echo "Image push skipped because PUSH_TO_REG==0"
        echo "--------------------------------------------------"
        echo " MLFLOW EXTENDED IMAGE Build Complete!"
        echo "--------------------------------------------------"
    fi
else
    FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY="mlflow_is_not_composed"
    echo "Skipping MLFLOW EXTENDED IMAGE Build"
fi

# --- TensorBoard / XProf Image Build Process ---
echo ""
if [ "$COMPOSE_TENSORBOARD" -eq 1 ]; then
    echo "Starting TENSORBOARD IMAGE build process..."
    FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY="${REGISTRY_PATH}/${TENSORBOARD_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"

    echo "Building TENSORBOARD image: ${FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY}"
    docker build --no-cache \
      --build-arg GIT_COMMIT="${GIT_COMMIT}" \
      -t "${FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY}" ./tensorboard/

    if [ "$PUSH_TO_REG" -eq 1 ]
    then
        echo "Pushing TENSORBOARD image: ${FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY}"
        docker push "${FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY}"
        echo "--------------------------------------------------"
        echo " TENSORBOARD IMAGE Build Complete!"
        echo " Pushed: ${FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY}"
        echo "--------------------------------------------------"
    else
        echo "Image push skipped because PUSH_TO_REG==0"
        echo "--------------------------------------------------"
        echo " TENSORBOARD IMAGE Build Complete!"
        echo "--------------------------------------------------"
    fi
else
    FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY="tensorboard_is_not_composed"
    echo "Skipping TENSORBOARD IMAGE Build"
fi

# --- Gemma LLM Image Build Process ---
if [ "$COMPOSE_GEMMA" -eq 1 ]; then
    echo ""
    echo "Starting GEMMA LLM IMAGE build process..."
    FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY="${REGISTRY_PATH}/${GEMMA_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"

    echo "Building GEMMA LLM image: ${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}"
    docker build --no-cache \
      --build-arg GIT_COMMIT="${GIT_COMMIT}" \
      -t "${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}" ./gemma_llm/

    if [ "$PUSH_TO_REG" -eq 1 ]; then
        echo "Pushing GEMMA LLM image: ${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}"
        docker push "${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}"
        echo "--------------------------------------------------"
        echo " GEMMA LLM IMAGE Build Complete!"
        echo " Pushed: ${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}"
        echo "--------------------------------------------------"
    else
        echo "Image push skipped because PUSH_TO_REG==0"
        echo "--------------------------------------------------"
        echo " GEMMA LLM IMAGE Build Complete!"
        echo "--------------------------------------------------"
    fi
else
    FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY="gemma3_is_not_composed"
    echo "Skipping GEMMA LLM IMAGE Build"
fi

# --- Update environment files in PK-Analysis repo ---
if [ ! -d "${PK_ANALYSIS_REPO_PATH}" ]; then
    echo "ERROR: PK-Analysis repository not found at ${PK_ANALYSIS_REPO_PATH}."
    exit 1
fi

EXAMPLE_FILE="${PK_ANALYSIS_REPO_PATH}/.env.example"
REAL_ENV_FILE="${PK_ANALYSIS_REPO_PATH}/.env"

# Function to safely update image tags in a target file (only for images built and pushed)
update_env_file() {
    local TARGET_FILE=$1
    local TMP_FILE="${TARGET_FILE}.tmp"
    local STRIP_REGEX="^# --- Autogenerated Image Tags"

    if [ "$PUSH_TO_REG" -ne 1 ]; then
        echo "Skipping ${TARGET_FILE} update (PUSH_TO_REG=${PUSH_TO_REG})."
        return 0
    fi

    echo "Updating tags in ${TARGET_FILE}..."
    echo "# --- Autogenerated Image Tags (Updated by build.sh) ---" > "${TMP_FILE}"

    if [ "$COMPOSE_DEV" -eq 1 ]; then
        echo "DEV_IMAGE_TAG=${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}" >> "${TMP_FILE}"
        STRIP_REGEX="${STRIP_REGEX}|^DEV_IMAGE_TAG="
    fi
    if [ "$COMPOSE_MLFLOW" -eq 1 ]; then
        echo "MLFLOW_IMAGE_TAG=${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}" >> "${TMP_FILE}"
        STRIP_REGEX="${STRIP_REGEX}|^MLFLOW_IMAGE_TAG="
    fi
    if [ "$COMPOSE_GEMMA" -eq 1 ]; then
        echo "GEMMA_IMAGE_TAG=${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}" >> "${TMP_FILE}"
        STRIP_REGEX="${STRIP_REGEX}|^GEMMA_IMAGE_TAG="
    fi
    if [ "$COMPOSE_TENSORBOARD" -eq 1 ]; then
        echo "TENSORBOARD_IMAGE_TAG=${FULL_TENSORBOARD_IMAGE_TAG_WITH_REGISTRY}" >> "${TMP_FILE}"
        STRIP_REGEX="${STRIP_REGEX}|^TENSORBOARD_IMAGE_TAG="
    fi

    # 2. Append everything else from the target file, stripping out only the updated tags
    if [ -f "${TARGET_FILE}" ]; then
        grep -v -E "${STRIP_REGEX}" "${TARGET_FILE}" >> "${TMP_FILE}" || true
    fi
    
    # 3. Overwrite
    mv "${TMP_FILE}" "${TARGET_FILE}"
}

# Always update the tracked example file
update_env_file "${EXAMPLE_FILE}"

# Update the user's actual runtime file if they have created it
if [ -f "${REAL_ENV_FILE}" ]; then
    update_env_file "${REAL_ENV_FILE}"
else
    echo "Notice: No local .env file found. You will need to run:"
    echo "  cp ${EXAMPLE_FILE} ${REAL_ENV_FILE}"
    echo "and configure your passwords/tokens before running docker compose."
fi

echo ""
echo "--------------------------------------------------"
echo " Build script finished successfully."
echo "--------------------------------------------------"
exit 0