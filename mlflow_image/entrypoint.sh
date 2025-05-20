#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

# Default UID/GID for the mlflow user.
# The official ghcr.io/mlflow/mlflow images often use a user named 'mlflow'.
# We'll aim to ensure this user exists and owns the artifact directory.
# Commonly UID 1000 or 1001. Let's use 1000 as an example.
# These can be overridden by environment variables if needed.
APP_USER_NAME=${MLFLOW_USER_NAME:-mlflow}
APP_UID=${MLFLOW_UID:-1000}
APP_GID=${MLFLOW_GID:-1000}

# This entrypoint script will run as root initially.
echo "Entrypoint: Ensuring artifact directory permissions..."

# Create the parent /mlflow directory if it doesn't exist and ensure it's traversable
mkdir -p /mlflow
# Note: chown on /mlflow might be too broad if other things are mounted there
# but if /mlflow is solely for artifacts or managed by this container, it's okay.
# More safely, ensure the artifacts dir itself.

# Ensure the /mlflow/artifacts directory exists and has correct ownership
# Docker creates the mount point, but its initial ownership might be root.
ARTIFACT_DIR="/mlflow/artifacts" # Matches your --default-artifact-root
mkdir -p "${ARTIFACT_DIR}"
echo "Setting ownership of ${ARTIFACT_DIR} to ${APP_UID}:${APP_GID}"
chown -R "${APP_UID}:${APP_GID}" "${ARTIFACT_DIR}"
# Optionally set more specific permissions if needed, e.g., chmod -R 700 "${ARTIFACT_DIR}"

# Check if the APP_USER_NAME exists, create if not.
# This ensures the user exists before gosu tries to switch to it.
if ! id -u "${APP_USER_NAME}" > /dev/null 2>&1; then
    echo "User ${APP_USER_NAME} not found. Creating user ${APP_USER_NAME} with UID ${APP_UID} and GID ${APP_GID}."
    groupadd --gid "${APP_GID}" "${APP_USER_NAME}" || echo "Group ${APP_USER_NAME} or GID ${APP_GID} may already exist."
    useradd --shell /bin/bash --uid "${APP_UID}" --gid "${APP_GID}" --no-create-home "${APP_USER_NAME}"
fi

# Execute the CMD (mlflow server ...) as the APP_USER_NAME using gosu
# This drops root privileges for the main MLflow server process.
echo "Executing command as user ${APP_USER_NAME}: $@"
exec gosu "${APP_USER_NAME}" "$@"