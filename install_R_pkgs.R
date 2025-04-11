# install_R_packages.R
# Simple script to install R packages listed in a requirements file

# Ensure a non-interactive CRAN mirror is set
options(repos = c(CRAN = "https://cloud.r-project.org/"))

req_file <- "R_requirements.txt"
if (!file.exists(req_file)) {
  stop("Cannot find R_requirements.txt in the current directory.")
}

print(paste("Reading packages from:", req_file))
packages <- readLines(req_file)
packages <- packages[packages != ""] # Remove empty lines
packages <- packages[!startsWith(packages, "#")] # Remove comments/empty lines

if (length(packages) == 0) {
  print("No packages listed in R_requirements.txt.")
  quit(save = "no", status = 0)
}

print(paste("Required packages:", paste(packages, collapse=", ")))

# Get names of already installed packages
# Base and recommended packages are installed with R itself
installed <- rownames(installed.packages())

# Find packages that need installation
to_install <- packages[!packages %in% installed]

if (length(to_install) > 0) {
  print(paste("Installing missing R packages:", paste(to_install, collapse=", ")))
  # Use multiple cores if available, adjust Ncpus if needed
  install.packages(to_install, Ncpus = max(1, parallel::detectCores(logical = FALSE)))
} else {
  print("All required R packages are already installed.")
}

# Verification step
print("Verifying installation...")
installed_final <- rownames(installed.packages())
missing_pkgs <- packages[!packages %in% installed_final]

if (length(missing_pkgs) > 0) {
    write(paste("Error: Failed to install the following R packages:", paste(missing_pkgs, collapse=", ")), stderr())
    quit(save = "no", status = 1) # Exit with error status
} else {
    print("Successfully installed/verified all required R packages.")
    quit(save = "no", status = 0) # Exit successfully
}