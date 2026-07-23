# ~/.Rprofile
# This script runs on R startup for the user.
# It ensures both user and renv project libraries are added to .libPaths().

user_lib <- Sys.getenv("R_LIBS_USER")

if (interactive()) {
  message("Sourcing user .Rprofile to configure library paths...")
}

# Check if R_LIBS_USER is set and the directory exists
if (nzchar(user_lib) && dir.exists(user_lib)) {
  .libPaths(c(user_lib, .libPaths()))
  if (interactive()) {
    message(paste("-> User library set to:", user_lib))
  }
}

# Clean up variable
rm(user_lib)

# --- Universal renv Library Injection ---
# Dynamically locate renv package libraries (supports 2-level and 3-level depth)
renv_root <- "/workspaces/PK-Analysis/renv/library"

if (dir.exists(renv_root)) {
  renv_libs <- c(
    Sys.glob(file.path(renv_root, "*/*/*")), # 3-level: platform/R-version/arch
    Sys.glob(file.path(renv_root, "*/*"))    # 2-level fallback
  )
  
  # Filter to existing directories
  renv_libs <- renv_libs[dir.exists(renv_libs)]
  
  if (length(renv_libs) > 0) {
    .libPaths(c(renv_libs, .libPaths()))
  }
}