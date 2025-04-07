#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# You can change the base image name if needed
IMAGE_BASE_NAME="cuda-py"

# --- Build Process ---
echo "Starting Docker image build process..."

# 1. Generate the timestamp tag
BUILD_TAG=$(date +%Y%m%d%H%M%S)
FULL_IMAGE_TAG="${IMAGE_BASE_NAME}:${BUILD_TAG}"

# 2. Export the tag variable so docker-compose can use it
#    (Needed if docker-compose.yml uses ${BUILD_TAG})
export BUILD_TAG

# 3. Inform the user about the tag being used
echo "Attempting to build image with tag: ${FULL_IMAGE_TAG}"

# 4. Run the Docker Compose build command
#    Using '--no-cache' to ensure a clean build as discussed
#    Docker Compose will automatically use the exported BUILD_TAG
#    if your docker-compose.yml is set up like: image: cuda-py:${BUILD_TAG:-latest}
echo "Running docker compose build..."
docker compose build --no-cache

# 5. Confirmation and Next Steps
echo ""
echo "--------------------------------------------------"
echo " Build Complete!"
echo " Docker image created: ${FULL_IMAGE_TAG}"
echo "--------------------------------------------------"
echo ""
echo " >>> ACTION REQUIRED <<<"
echo " Please update the 'image' property in your "
echo " .devcontainer/devcontainer.json file to:"
echo ""
echo " \"image\": \"${FULL_IMAGE_TAG}\""
echo ""
echo " >>> ACTION REQUIRED <<<"
echo ""

# Exit cleanly
exit 0