#!/bin/sh
set -e

# Change the ownership of the cache directory to the gemma user.
# This allows the transformers library to write model files to the volume.
chown -R gemma:gemma /cache

# Execute the command passed to this script (the CMD from the Dockerfile)
# as the 'gemma' user.
exec gosu gemma "$@"