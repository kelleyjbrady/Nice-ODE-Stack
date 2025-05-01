# ~/.Rprofile
# This script runs on R startup for the user.
# It ensures the user's personal library path (defined by R_LIBS_USER env var)
# is the first path searched and used for package installation.

message("Sourcing user .Rprofile to configure library paths...")
user_lib <- Sys.getenv("R_LIBS_USER")

# Check if R_LIBS_USER is set and the directory exists
if (nzchar(user_lib) && dir.exists(user_lib)) {
  # Prepend the user library to the library paths
  .libPaths(c(user_lib, .libPaths()))
  message(paste("-> User library set to:", user_lib))
} else if (nzchar(user_lib)) {
  message(paste("-> Warning: R_LIBS_USER set to", user_lib, "but directory does not exist."))
} else {
  message("-> Warning: R_LIBS_USER environment variable not set.")
}

# Clean up variable
rm(user_lib)