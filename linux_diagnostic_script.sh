#!/bin/bash
#
# Script to collect system performance diagnostics on Rocky Linux 8
#
# Intended to be run during a support session with a customer.
#
# Output is saved to /tmp/ and then compressed into a zip file.
#
# Requires the 'zip' utility to be installed.  The script will check for it.
#

# --- Functions ---

# Function to run a command and check its exit status
run_command() {
    local command="$1"
    local description="$2"
    local output_file="$3" # Added output_file parameter

    echo "Running: $description"
    if [ -n "$output_file" ]; then
        # Using eval can be risky if $command contains unexpected content.
        # Consider alternatives if possible, but keeping for consistency with original.
        eval "$command" >"$output_file" 2>&1 # Redirect output and errors
    else
        eval "$command" >/dev/null 2>&1 # Redirect output and errors to /dev/null
    fi
    local status=$?

    if [ $status -eq 0 ]; then
        echo "Command '$command' successful. Press Enter to continue..."
        # Consider removing the interactive 'read' for automated environments
        read -r dummy
    else
        echo "Command '$command' failed with exit status $status. Exiting."
        exit 1
    fi
}

# Function to collect files and handle errors.
collect_files() {
    # This function now expects an already expanded list of files.
    local files=("$@")
    local missing_files=()

    for file in "${files[@]}"; do
        # Check if the specific file exists.
        if [ ! -e "$file" ]; then
            missing_files+=("$file")
            # Outputting warnings to stderr is generally preferred.
            echo "Warning: File not found: $file" >&2
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "Some files were not found. Collection will continue without them." >&2
    fi
    # Return success (0) if the function completed, even if files were missing.
    # Could return non-zero if missing files should be treated as an error.
    return 0
}

# Function to generate the report
generate_report() {
    local report_file="$1"

    echo "Generating system performance report..."
    # Use printf for more reliable newline handling across systems
    printf "\n --- System Performance Report --- \n" >> "$report_file"
    printf " Date: %s\n" "$(date)" >> "$report_file"
    printf " Hostname: %s\n" "$(hostname)" >> "$report_file"
    printf "\n --- Uptime --- \n" >> "$report_file"
    uptime >> "$report_file"
    printf "\n --- CPU Information --- \n" >> "$report_file"
    lscpu >> "$report_file" # Add CPU info
    printf "\n --- Memory Information --- \n" >> "$report_file"
    free -h >> "$report_file"
    printf "\n --- Disk Information --- \n" >> "$report_file"
    df -h >> "$report_file"
    printf "\n --- Network Interfaces ---\n" >> "$report_file"
    ip link show >> "$report_file" # show interfaces
    printf "\n --- Running Services ---\n" >> "$report_file"
    systemctl list-units --type=service --state=running >> "$report_file"
    printf "\n --- End of Report --- \n\n" >> "$report_file"
    echo "Report generation complete."
}


# --- Main Script ---

echo "Starting System Performance Diagnostics Collection Script"

# Check if zip is installed
if ! command -v zip &>/dev/null; then
    echo "Error: 'zip' utility is not installed. Please install it (e.g., 'sudo yum install zip -y') and run this script again." >&2
    exit 1
fi

# Define the base temporary directory
# Use mktemp for safer temporary directory creation
output_dir=$(mktemp -d "/tmp/asms_system_diagnostics_XXXXXX")
if [ ! -d "$output_dir" ]; then
    echo "Error: Failed to create temporary directory." >&2
    exit 1
fi
echo "Created temporary directory: $output_dir"

# Define the final zip file path (outside the temporary directory)
# Use /tmp/ as the destination for the final zip file
zip_filename="/tmp/asms-system_performance_$(date +'%Y%m%d_%H%M%S')-$(hostname).zip"

# Use a trap to ensure cleanup even if the script exits unexpectedly
# Note: The cleanup function will run *after* the script finishes or exits.
cleanup() {
    echo "Cleaning up temporary directory: $output_dir"
    # Check if the directory exists before attempting removal
    if [ -d "$output_dir" ]; then
        rm -rf "$output_dir"
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to remove temporary directory: $output_dir. You may need to remove it manually." >&2
        else
             echo "Successfully removed temporary directory: $output_dir"
        fi
    fi
}
trap cleanup EXIT

# Change to the output directory - simplifies paths for collected command outputs
# Use pushd/popd for potentially safer directory navigation
pushd "$output_dir" > /dev/null || { echo "Error: Failed to change directory to $output_dir" >&2; exit 1; }

# --- Collect Data ---

# Removed output_file argument from run_command as it was duplicating redirection
run_command "top -b -n 1" "Collect CPU Utilization (top)" "top_output.txt" # Added -b for batch mode
run_command "free -h" "Collect Memory Utilization (free)" "memory_output.txt"
run_command "iostat -xz 1 1" "Collect Disk I/O (iostat)" "iostat_output.txt" # Added count 1
run_command "sar -n DEV 1 1" "Collect Network Utilization (sar -n DEV)" "network_output.txt"
run_command "uptime" "Collect Load Average (uptime)" "uptime_output.txt"
run_command "vmstat 5 10" "Collect CPU and Memory Over Time (vmstat)" "vmstat_detailed_output.txt"
run_command "sar -u -r -b -n DEV 5 10" "Collect System Activity Over Time (sar)" "sar_detailed_output.txt"
run_command "pidstat -u -r -d 5 10" "Collect Per-Process Resource Usage Over Time (pidstat)" "pidstat_detailed_output.txt"
run_command "systemctl list-units --type=service --state=running" "List Running Services" "running_services.txt"
run_command "df -h" "Check Disk Space" "disk_space.txt"

# --- Generate Report ---
REPORT_FILE="system_report.txt"
generate_report "$REPORT_FILE"

# --- Collect Logs ---

log_patterns=(
    "/var/log/messages*"
    "/var/log/kern*"
    "/var/log/algosec-top-*"
    "/home/afa/.fa-history*"
    "/data/ms-metro/logs/catalina.out*"
    "/var/log/algosec-pidstat*"                 
    "/var/log/algosec_toolbox/sizing_calculator/*"
)

# ** FIX for Issue 2: Expand wildcards before checking/zipping **
expanded_log_files=()
echo "Expanding log file patterns..."
# Enable nullglob to handle patterns that match nothing
shopt -s nullglob
for pattern in "${log_patterns[@]}"; do
    # Perform glob expansion here. Intentionally unquoted.
    expanded_paths=( $pattern )
    if [ ${#expanded_paths[@]} -gt 0 ]; then
        # Add the expanded, existing files to the list
        expanded_log_files+=( "${expanded_paths[@]}" )
    else
        # Warn if a pattern didn't match any files
        echo "Warning: Log pattern '$pattern' did not match any files." >&2
    fi
done
# Disable nullglob again
shopt -u nullglob

echo "Checking existence of specific log files..."
# Now call collect_files with the *expanded* list
collect_files "${expanded_log_files[@]}"

# --- Compress the output ---

echo "Creating zip archive: $zip_filename"

# ** FIX for Issue 1: Create zip file outside the temp dir **
# Use '.' to refer to all files in the current directory ($output_dir)
# Use the expanded list of log files.
# The zip command will store the absolute paths for the log files.
zip -r "$zip_filename" . "${expanded_log_files[@]}"

# Check zip command success
zip_status=$?
popd > /dev/null # Return to the original directory

if [ $zip_status -eq 0 ]; then
    echo "Successfully created zip archive: $zip_filename"
    # ** FIX for Issue 1: Update the location message **
    echo "The archive is located in: $(dirname "$zip_filename")" # Show the directory (/tmp)
    echo "Please provide this file to the support engineer."
else
    echo "Error: Failed to create zip archive: $zip_filename" >&2
    # The trap will still run for cleanup
    exit 1
fi

# Cleanup is now handled by the trap EXIT function

echo "Script finished."
exit 0
