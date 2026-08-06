# ~/.Rprofile
# This fallback script runs when R is started in a directory without its own .Rprofile (e.g., subfolders).

user_lib <- Sys.getenv("R_LIBS_USER")
if (interactive()) {
  message("Sourcing container fallback .Rprofile...")
}

# 1. Prepend User Library
if (nzchar(user_lib) && dir.exists(user_lib)) {
  .libPaths(c(user_lib, .libPaths()))
}
rm(user_lib)

# 2. Universal renv Library Injection for Subfolders
# If we are in a subfolder, explicitly point R back to the workspace renv library
renv_root <- "/workspaces/PK-Analysis/renv/library"

if (dir.exists(renv_root)) {
  # Support both 3-level (platform/R-version/arch) and 2-level renv structures
  renv_libs <- c(
    Sys.glob(file.path(renv_root, "*/*/*")), 
    Sys.glob(file.path(renv_root, "*/*"))
  )
  
  # Filter to directories that actually exist
  renv_libs <- renv_libs[dir.exists(renv_libs)]
  
  if (length(renv_libs) > 0) {
    .libPaths(c(renv_libs, .libPaths()))
    if (interactive()) {
      message("-> Injected PK-Analysis renv library paths from fallback profile.")
    }
  }
}