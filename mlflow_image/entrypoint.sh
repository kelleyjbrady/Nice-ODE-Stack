#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

# Default UID/GID for the mlflow user.
APP_USER_NAME=${MLFLOW_USER_NAME:-mlflow}
APP_UID=${MLFLOW_UID:-1000}
APP_GID=${MLFLOW_GID:-1000}

# Path where artifacts will be stored, matching --default-artifact-root and volume mount
ARTIFACT_ROOT_IN_CONTAINER="/mlflow/artifacts"
# Parent directory of the artifact root
PARENT_OF_ARTIFACT_ROOT=$(dirname "${ARTIFACT_ROOT_IN_CONTAINER}") # This will be /mlflow

if [ "$(id -u)" = "0" ]; then # Script runs as root
    echo "Entrypoint running as root. Setting up directories and permissions for ${APP_USER_NAME} (${APP_UID}:${APP_GID})."
    
    # 1. Ensure the parent directory of the artifact root exists and is owned by the app user.
    #    Docker creates the mount point /mlflow/artifacts.
    #    The parent /mlflow is implicitly created by Docker if it doesn't exist to establish the mount path.
    #    This parent /mlflow needs to be owned by our app user for os.makedirs to work reliably.
    if [ ! -d "${PARENT_OF_ARTIFACT_ROOT}" ]; then
         mkdir -p "${PARENT_OF_ARTIFACT_ROOT}"
    fi
    echo "Setting ownership of ${PARENT_OF_ARTIFACT_ROOT} to ${APP_UID}:${APP_GID}"
    chown "${APP_UID}:${APP_GID}" "${PARENT_OF_ARTIFACT_ROOT}" # Chown /mlflow itself (not recursively)

    # 2. Ensure the artifact root directory (the volume mount point) exists and is owned by the app user.
    mkdir -p "${ARTIFACT_ROOT_IN_CONTAINER}"
    echo "Setting ownership of ${ARTIFACT_ROOT_IN_CONTAINER} (and its contents) to ${APP_UID}:${APP_GID}"
    chown -R "${APP_UID}:${APP_GID}" "${ARTIFACT_ROOT_IN_CONTAINER}" # Chown /mlflow/artifacts and its contents

else
    echo "Entrypoint not running as root. Assuming directory permissions are correct for user $(id -u)."
    # If not root, make a best effort to create the directory; might fail if permissions are wrong.
    mkdir -p "${ARTIFACT_ROOT_IN_CONTAINER}" || true
fi

# Ensure the target user exists before switching
if ! id -u "${APP_USER_NAME}" > /dev/null 2>&1; then
    echo "User ${APP_USER_NAME} not found. Creating user ${APP_USER_NAME} with UID ${APP_UID} and GID ${APP_GID}."
    groupadd --gid "${APP_GID}" "${APP_USER_NAME}" || echo "Group ${APP_USER_NAME} (GID ${APP_GID}) may already exist."
    useradd --shell /bin/bash --uid "${APP_UID}" --gid "${APP_GID}" --no-create-home "${APP_USER_NAME}"
fi

echo "Executing command as user ${APP_USER_NAME} (${APP_UID}:${APP_GID}): $@"
exec gosu "${APP_USER_NAME}" "$@"