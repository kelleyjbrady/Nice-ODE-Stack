#!/bin/bash
set -e

# --- Configuration ---
DEV_IMAGE_BASE_NAME="cuda-py"
MLFLOW_IMAGE_BASE_NAME="mlflow-postgres"
GEMMA_IMAGE_BASE_NAME="gemma-llm"
COMPOSE_GEMMA=0

REGISTRY_PATH="not-used"

# Path to the PK-Analysis repo's .env file (ADJUST IF YOUR REPOS ARE NOT SIBLINGS)
PK_ANALYSIS_REPO_PATH="../PK-Analysis"
PK_ANALYSIS_ENV_FILE="${PK_ANALYSIS_REPO_PATH}/.env"


# --- Dev Image Build Process ---
echo "Starting DEV IMAGE build process..."
DEV_BUILD_TAG=$(date +%Y%m%d%H%M%S)
# Local tag for the image built by docker-compose
LOCAL_DEV_IMAGE_NAME_WITH_TAG="${DEV_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"
# Full registry path for the dev image
REGISTRY_DEV_IMAGE_NAME_WITH_TAG="${REGISTRY_PATH}/${DEV_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"

export BUILD_TAG=${DEV_BUILD_TAG} # Used by docker-compose.yml to tag the image internally

echo "Building dev image. It will be tagged as '${LOCAL_DEV_IMAGE_NAME_WITH_TAG}' by docker-compose.yml"
# Ensure your docker-compose.yml `dev_env_builder` service has `image: cuda-py:${BUILD_TAG}`
docker compose -f ./docker-compose.yml build --no-cache dev_env_builder

# After build, the image 'cuda-py:YYYYMMDDHHMMSS' exists locally. Now tag it for registry.
echo "Tagging dev image for registry: ${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"
docker tag "${LOCAL_DEV_IMAGE_NAME_WITH_TAG}" "${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"

PUSH_TO_REG=0
if [ "$PUSH_TO_REG" -eq 1 ]
then
    # --- Push to Registry ----
    echo "Pushing dev image: ${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"
    # docker login your-registry.io # Uncomment and configure if needed for private registries
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


# --- MLflow Extended Image Build Process ---
echo ""
echo "Starting MLFLOW EXTENDED IMAGE build process..."
FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY="${REGISTRY_PATH}/${MLFLOW_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"

echo "Building MLFLOW EXTENDED image: ${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}"
docker build --no-cache -t "${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}" ./mlflow_image/

# --- Push to Registry ----
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

# --- Gemma LLM Image Build Process ---
if [ "$COMPOSE_GEMMA" -eq 1 ]; then
    echo ""
    echo "Starting GEMMA LLM IMAGE build process..."
    FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY="${REGISTRY_PATH}/${GEMMA_IMAGE_BASE_NAME}:${DEV_BUILD_TAG}"

    echo "Building GEMMA LLM image: ${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}"
    docker build --no-cache -t "${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY}" ./gemma_llm/

    # --- Push Gemma LLM Image to Registry ---
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

# --- Update .env file in PK-Analysis repo ---
if [ ! -d "${PK_ANALYSIS_REPO_PATH}" ]; then
    echo "ERROR: PK-Analysis repository not found at ${PK_ANALYSIS_REPO_PATH}. Cannot update .env file."
    echo "Please manually update ${PK_ANALYSIS_ENV_FILE} with the following tags:"
    echo "DEV_IMAGE_TAG=${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}"
    echo "MLFLOW_IMAGE_TAG=${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}"
    exit 1
fi

echo "Updating ${PK_ANALYSIS_ENV_FILE}..."
ENV_CONTENT=$(cat <<EOF
# This file is managed by build.sh from the proj-cuda-container repo
# and read by docker-compose.runtime.yml in PK-Analysis
DEV_IMAGE_TAG=${REGISTRY_DEV_IMAGE_NAME_WITH_TAG}
MLFLOW_IMAGE_TAG=${FULL_MLFLOW_IMAGE_TAG_WITH_REGISTRY}
GEMMA_IMAGE_TAG=${FULL_GEMMA_IMAGE_TAG_WITH_REGISTRY} #A placeholder if COMPOSE_GEMMA==0
POSTGRES_USER=mlflow_user
POSTGRES_PASSWORD=yoursecurepassword # <<< CHANGE THIS IN THE ACTUAL .env FILE!
POSTGRES_DB=mlflow_db 
HF_TOKEN=your_hugging_face_read_token_here #A placeholder if COMPOSE_GEMMA==0. Used to get the weights for GEMMA 3 otherwise.
DB_HOST=db
DB_PORT=5432
# Add other secrets/variables below if needed, they will be preserved.
EOF
)

# Preserve existing non-tag lines from .env if they exist
# This grep should be adjusted if additional lines are added to .env
if [ -f "${PK_ANALYSIS_ENV_FILE}" ]; then
    EXISTING_OTHER_VARS=$(grep -v -e '^DEV_IMAGE_TAG=' -e '^MLFLOW_IMAGE_TAG=' -e '^GEMMA_IMAGE_TAG=' -e '^HF_TOKEN=' -e '^POSTGRES_USER=' -e '^POSTGRES_PASSWORD=' -e '^POSTGRES_DB=' -e '^DB_HOST=' -e '^DB_PORT=' -e '^# This file is managed' "${PK_ANALYSIS_ENV_FILE}" || true)
    if [ -n "${EXISTING_OTHER_VARS}" ]; then
        ENV_CONTENT="${ENV_CONTENT}\n${EXISTING_OTHER_VARS}"
    fi
fi
echo -e "${ENV_CONTENT}" > "${PK_ANALYSIS_ENV_FILE}"

echo ""
echo "--------------------------------------------------"
echo " Build script finished."
echo " ${PK_ANALYSIS_ENV_FILE} updated."
echo " Review and commit changes in ${PK_ANALYSIS_REPO_PATH} if necessary."
echo "--------------------------------------------------"
echo ""
exit 0