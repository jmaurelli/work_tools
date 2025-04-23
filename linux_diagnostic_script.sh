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
        eval "$command" >"$output_file" 2>&1 # Redirect output and errors
    else
        eval "$command" >/dev/null 2>&1 # Redirect output and errors to /dev/null
    fi
    local status=$?

    if [ $status -eq 0 ]; then
        echo "Command '$command' successful.  Press Enter to continue..."
        read -r dummy
    else
        echo "Command '$command' failed with exit status $status.  Exiting."
        exit 1
    fi
}

# Function to collect files and handle errors.
collect_files() {
    local files=("$@")
    local missing_files=()

    for file in "${files[@]}"; do
        if [ ! -e "$file" ]; then
            missing_files+=("$file")
            echo "Warning: File not found: $file" # echo to standard error.
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "Some files were not found. Collection will continue without them."
    fi
}

# Function to generate the report
generate_report() {
    local report_file="$1"

    echo "Generating system performance report..."
    echo " " >> "$report_file"
    echo " --- System Performance Report --- " >> "$report_file"
    echo " Date: $(date)" >> "$report_file"
    echo " Hostname: $(hostname)" >> "$report_file"
    echo " " >> "$report_file"

    echo " --- Uptime --- " >> "$report_file"
    uptime >> "$report_file"
    echo " " >> "$report_file"

    echo " --- CPU Information --- " >> "$report_file"
    lscpu >> "$report_file" # Add CPU info
    echo " " >> "$report_file"

    echo " --- Memory Information --- " >> "$report_file"
    free -h >> "$report_file"
    echo " " >> "$report_file"

    echo " --- Disk Information --- " >> "$report_file"
    df -h >> "$report_file"
    echo " " >> "$report_file"

    echo " --- Network Interfaces ---" >> "$report_file"
    ip link show >> "$report_file" # show interfaces
    echo " " >> "$report_file"

    echo " --- Running Services ---" >> "$report_file"
    systemctl list-units --type=service --state=running >> "$report_file"
    echo " " >> "$report_file"

    echo " --- End of Report --- " >> "$report_file"
    echo " " >> "$report_file"
    echo "Report generation complete."
}


# --- Main Script ---

echo "Starting System Performance Diagnostics Collection Script"

# Check if zip is installed
if ! command -v zip &>/dev/null; then
    echo "Error: 'zip' utility is not installed.  Please install it (e.g., 'sudo yum install zip -y') and run this script again."
    exit 1
fi

# Create a temporary directory to store the output files
output_dir="/tmp/asms_system_diagnostics_$(date +'%Y%m%d_%H%M%S')"
mkdir -p "$output_dir"
if [ ! -d "$output_dir" ]; then
    echo "Error: Failed to create output directory: $output_dir"
    exit 1
fi

# Change to the output directory
cd "$output_dir"

# --- Collect Data ---

run_command "top -n 1 > top_output.txt" "Collect CPU Utilization (top)" "top_output.txt"
run_command "free -h > memory_output.txt" "Collect Memory Utilization (free)" "memory_output.txt"
run_command "iostat -xz > iostat_output.txt" "Collect Disk I/O (iostat)" "iostat_output.txt"
run_command "sar -n DEV 1 1 > network_output.txt" "Collect Network Utilization (sar -n DEV)" "network_output.txt"
run_command "uptime > uptime_output.txt" "Collect Load Average (uptime)" "uptime_output.txt"
run_command "vmstat 5 10 > vmstat_detailed_output.txt" "Collect CPU and Memory Over Time (vmstat)" "vmstat_detailed_output.txt"
run_command "sar -u -r -b -n DEV 5 10 > sar_detailed_output.txt" "Collect System Activity Over Time (sar)" "sar_detailed_output.txt"
run_command "pidstat -u -r -d 5 10 > pidstat_detailed_output.txt" "Collect Per-Process Resource Usage Over Time (pidstat)" "pidstat_detailed_output.txt"
run_command "systemctl list-units --type=service --state=running > running_services.txt" "List Running Services" "running_services.txt"
run_command "df -h > disk_space.txt" "Check Disk Space" "disk_space.txt"

# --- Generate Report ---
REPORT_FILE="system_report.txt"
generate_report "$REPORT_FILE"

# --- Collect Logs ---

log_files=(
    "/var/log/messages*"
    "/var/log/kern*"
    "/var/log/algosec-top-*"
    "/home/afa/.fa-history*"
    "/data/ms-metro/logs/catalina.out*"
)

collect_files "${log_files[@]}" #check if the log files exist.

# --- Compress the output ---

# Create the zip file name
zip_filename="asms-system_performance_$(date +'%m-%d')-$(hostname).zip"

# Add all collected files to the zip archive.  Include files from the current directory, and the log files.
zip -r "$zip_filename" * "${log_files[@]}"

if [ $? -eq 0 ]; then
    echo "Successfully created zip archive: $zip_filename"
    echo "The archive is located in: $output_dir"
    echo "Please provide this file to the support engineer."
else
    echo "Error: Failed to create zip archive: $zip_filename"
    exit 1
fi

# Clean up the temporary directory
rm -rf "$output_dir" # Remove the directory and its contents
if [ $? -eq 0 ]; then
    echo "Successfully removed temporary directory: $output_dir"
else
    echo "Error: Failed to remove temporary directory: $output_dir.  You may need to remove it manually."

fi
echo "Script finished."
exit 0
