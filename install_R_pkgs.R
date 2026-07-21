# install_R_packages.R
# Simple script to install specific versions of R packages from a CSV

options(repos = c(CRAN = "https://cloud.r-project.org/"))

req_file <- "r_requirements.csv"
if (!file.exists(req_file)) {
  stop(paste("Cannot find", req_file, "in the current directory."))
}

print(paste("Reading packages from:", req_file))

# Read the CSV. Ignore lines starting with '#'
req_data <- read.csv(req_file, stringsAsFactors = FALSE, strip.white = TRUE, comment.char = "#")

# Validate columns
if (!all(c("Package", "Version") %in% colnames(req_data))) {
  stop("CSV must contain 'Package' and 'Version' columns.")
}

# Remove any empty rows
req_data <- req_data[req_data$Package != "" & !is.na(req_data$Package), ]

if (nrow(req_data) == 0) {
  print(paste("No packages listed in", req_file))
  quit(save = "no", status = 0)
}

print("Required packages and target versions:")
print(req_data)

installed_info <- as.data.frame(installed.packages(), stringsAsFactors = FALSE)

# Function to check if the exact version is already installed
needs_install <- function(pkg, target_ver) {
  if (!(pkg %in% installed_info$Package)) {
    return(TRUE) 
  }
  installed_ver <- installed_info[installed_info$Package == pkg, "Version"]
  return(installed_ver != target_ver)
}

req_data$InstallNeeded <- mapply(needs_install, req_data$Package, req_data$Version)
to_install_data <- req_data[req_data$InstallNeeded, ]

if (nrow(to_install_data) > 0) {
  print("Installing the following missing or mismatched packages:")
  print(to_install_data[, c("Package", "Version")])
  
  n_cores <- max(1, parallel::detectCores(logical = FALSE))
  
  # Loop through packages because install_version requires singular arguments
  tryCatch({
    for (i in 1:nrow(to_install_data)) {
      pkg <- to_install_data$Package[i]
      ver <- to_install_data$Version[i]
      
      print(paste("--> Installing", pkg, "version", ver))
      
      remotes::install_version(
        package = pkg,
        version = ver,
        upgrade = "never",
        Ncpus = n_cores
      )
    }
  }, error = function(e) {
    write(paste("Installation encountered an error:", e$message), stderr())
    quit(save = "no", status = 1)
  })
} else {
  print("All required R packages are already installed at the specified versions.")
}

# Verification step
print("Verifying installation...")
installed_final <- as.data.frame(installed.packages(), stringsAsFactors = FALSE)
failed_pkgs <- character(0)

for (i in 1:nrow(req_data)) {
  pkg <- req_data$Package[i]
  expected_ver <- req_data$Version[i]
  
  if (!(pkg %in% installed_final$Package)) {
    failed_pkgs <- c(failed_pkgs, paste(pkg, "(Missing completely)"))
  } else {
    actual_ver <- installed_final[installed_final$Package == pkg, "Version"]
    if (actual_ver != expected_ver) {
      failed_pkgs <- c(failed_pkgs, paste0(pkg, " (Found ", actual_ver, ", expected ", expected_ver, ")"))
    }
  }
}

if (length(failed_pkgs) > 0) {
    write(paste("Error: Failed to verify the following R packages:", paste(failed_pkgs, collapse=", ")), stderr())
    quit(save = "no", status = 1) 
} else {
    print("Successfully installed and verified all required R packages to their exact versions.")
    quit(save = "no", status = 0) 
}