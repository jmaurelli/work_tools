#!/bin/bash

# test_linux_diagnostic_script.sh - Unit tests for linux_diagnostic_script.sh functions

# --- Test Setup ---

# Path to the script containing the functions under test
SCRIPT_UNDER_TEST="./linux_diagnostic_script.sh"
# Check if script exists before sourcing
if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
    echo "FATAL: Script under test not found: $SCRIPT_UNDER_TEST"
    exit 1
fi

# Source the functions
# shellcheck source=./linux_diagnostic_script.sh
source "$SCRIPT_UNDER_TEST"

# Create a temporary directory for test outputs and dummy files
setUp() {
    SHUNIT_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/shunit_test_XXXXXX")
    # Go into temp dir for easier file handling
    cd "$SHUNIT_TMPDIR" || exit 1
    # Store original PATH
    ORIGINAL_PATH=$PATH
}

# Clean up the temporary directory and restore PATH
tearDown() {
    # Restore original PATH if mocks were used
    PATH=$ORIGINAL_PATH
    # Get out of the temp dir before removing it
    cd - > /dev/null 2>&1
    if [ -d "$SHUNIT_TMPDIR" ]; then
        rm -rf "$SHUNIT_TMPDIR"
    fi
}

# --- Mock Functions ---
# These override real commands ONLY during specific tests

mock_date() { echo "Mock Date: $(command date '+%Y-%m-%d %H:%M:%S')"; }
mock_hostname() { echo "mock-hostname"; }
mock_uptime() { echo "mock uptime output"; }
mock_lscpu() { echo "mock lscpu output"; }
mock_free() { echo "mock free -h output"; }
mock_df() { echo "mock df -h output"; }
mock_ip() { echo "mock ip link show output"; }
mock_systemctl() { echo "mock systemctl list-units output"; }

# Function to activate mocks by adjusting PATH
activate_mocks() {
    # Create dummy scripts for commands to be mocked in a dedicated bin dir
    mkdir -p "$SHUNIT_TMPDIR/mock_bin"
    # Make mock functions available to subshells/commands if needed
    export -f mock_date mock_hostname mock_uptime mock_lscpu mock_free mock_df mock_ip mock_systemctl

    # Create wrapper scripts in the mock bin directory
    cat << EOF > "$SHUNIT_TMPDIR/mock_bin/date"
#!/bin/bash
mock_date "\$@"
EOF
    cat << EOF > "$SHUNIT_TMPDIR/mock_bin/hostname"
#!/bin/bash
mock_hostname "\$@"
EOF
    cat << EOF > "$SHUNIT_TMPDIR/mock_bin/uptime"
#!/bin/bash
mock_uptime "\$@"
EOF
    cat << EOF > "$SHUNIT_TMPDIR/mock_bin/lscpu"
#!/bin/bash
mock_lscpu "\$@"
EOF
     cat << EOF > "$SHUNIT_TMPDIR/mock_bin/free"
#!/bin/bash
mock_free "\$@"
EOF
     cat << EOF > "$SHUNIT_TMPDIR/mock_bin/df"
#!/bin/bash
mock_df "\$@"
EOF
     cat << EOF > "$SHUNIT_TMPDIR/mock_bin/ip"
#!/bin/bash
mock_ip "\$@"
EOF
     cat << EOF > "$SHUNIT_TMPDIR/mock_bin/systemctl"
#!/bin/bash
mock_systemctl "\$@"
EOF

    # Make the mock scripts executable
    chmod +x "$SHUNIT_TMPDIR"/mock_bin/*

    # Prepend the mock bin directory to the PATH
    PATH="$SHUNIT_TMPDIR/mock_bin:$PATH"
}


# --- Test Cases for run_command (Copied from previous example for completeness) ---

test_run_command_success_with_output() {
    local cmd="echo 'Test Success Data'"
    local desc="Test Success With Output"
    local outfile="success_output.txt"
    local expected_stdout_msg="Command '$cmd' successful.  Press Enter to continue..."

    local stdout
    stdout=$( (run_command "$cmd" "$desc" "$outfile") <<< '' )
    local subshell_status=$?

    assertEquals "Subshell should exit successfully (status 0)" 0 "$subshell_status"
    assertTrue "Output file should be created" "[ -f '$outfile' ]"
    assertEquals "Output file content should match" "Test Success Data" "$(cat "$outfile")"
    assertContains "Standard output should contain description" "$stdout" "Running: $desc"
    assertContains "Standard output should contain success message" "$stdout" "$expected_stdout_msg"
}

test_run_command_failure_with_output() {
    local cmd="ls /non_existent_dir_for_test_run_cmd" # Command guaranteed to fail
    local desc="Test Failure With Output"
    local outfile="failure_output.txt"
    local expected_stdout_msg_part="Command '$cmd' failed with exit status" # Status varies

    local stdout
    stdout=$( (run_command "$cmd" "$desc" "$outfile") <<< '' )
    local subshell_status=$?

    assertEquals "Subshell should exit with status 1 due to function's exit" 1 "$subshell_status"
    assertTrue "Output file should be created" "[ -f '$outfile' ]"
    assertContains "Output file should contain stderr from command" "$(cat "$outfile")" "No such file or directory" || \
    assertContains "Output file should contain stderr from command (alternative)" "$(cat "$outfile")" "cannot access" # Handle different ls error messages
    assertContains "Standard output should contain description" "$stdout" "Running: $desc"
    assertContains "Standard output should contain failure message part" "$stdout" "$expected_stdout_msg_part"
}


# --- Test Cases for collect_files ---

test_collect_files_all_exist() {
    # Setup: Create dummy files
    touch file1.log file2.txt file3.conf
    local files=("file1.log" "file2.txt" "file3.conf")

    # Execute: Capture stdout
    local output
    output=$(collect_files "${files[@]}")
    local status=$? # collect_files itself doesn't exit, check its return status

    # Assertions
    assertEquals "Function should return success (status 0)" 0 "$status"
    assertNull "No output expected when all files exist" "$output"
    # Double check no warnings were printed
    assertNotContains "Output should not contain 'Warning: File not found'" "$output" "Warning: File not found"
    assertNotContains "Output should not contain 'Some files were not found'" "$output" "Some files were not found"
}

test_collect_files_some_missing() {
    # Setup: Create some files, leave others non-existent
    touch existing1.log existing2.data
    local files=("existing1.log" "missing1.txt" "existing2.data" "missing2.conf")
    local expected_warning1="Warning: File not found: missing1.txt"
    local expected_warning2="Warning: File not found: missing2.conf"
    local expected_summary="Some files were not found. Collection will continue without them."

    # Execute: Capture stdout
    local output
    output=$(collect_files "${files[@]}")
    local status=$?

    # Assertions
    assertEquals "Function should return success (status 0)" 0 "$status"
    assertNotNull "Output is expected when files are missing" "$output"
    assertContains "Should warn about missing1.txt" "$output" "$expected_warning1"
    assertContains "Should warn about missing2.conf" "$output" "$expected_warning2"
    assertContains "Should print summary message" "$output" "$expected_summary"
    assertNotContains "Should not warn about existing1.log" "$output" "Warning: File not found: existing1.log"
}

test_collect_files_all_missing() {
    # Setup: Ensure files don't exist
    local files=("nonexistent1.log" "nonexistent2.txt")
    local expected_warning1="Warning: File not found: nonexistent1.log"
    local expected_warning2="Warning: File not found: nonexistent2.txt"
    local expected_summary="Some files were not found. Collection will continue without them."

    # Execute: Capture stdout
    local output
    output=$(collect_files "${files[@]}")
    local status=$?

    # Assertions
    assertEquals "Function should return success (status 0)" 0 "$status"
    assertNotNull "Output is expected when all files are missing" "$output"
    assertContains "Should warn about nonexistent1.log" "$output" "$expected_warning1"
    assertContains "Should warn about nonexistent2.txt" "$output" "$expected_warning2"
    assertContains "Should print summary message" "$output" "$expected_summary"
}

test_collect_files_empty_input() {
    # Setup: No files
    local files=()

    # Execute: Capture stdout
    local output
    output=$(collect_files "${files[@]}")
    local status=$?

    # Assertions
    assertEquals "Function should return success (status 0)" 0 "$status"
    assertNull "No output expected for empty input" "$output"
}

# --- Test Cases for generate_report ---

test_generate_report_creates_file_and_contains_mocked_data() {
    local report_file="test_report.txt"

    # Activate mocks for external commands
    activate_mocks

    # Execute
    # Capture stdout to check the "Generating..." and "complete" messages
    local stdout_gen
    stdout_gen=$(generate_report "$report_file")
    local status=$?

    # Assertions
    assertEquals "generate_report should return success (status 0)" 0 "$status"
    assertTrue "Report file should be created" "[ -f '$report_file' ]"
    assertContains "Stdout should show generation start" "$stdout_gen" "Generating system performance report..."
    assertContains "Stdout should show generation complete" "$stdout_gen" "Report generation complete."

    # Check file content for static text and mocked output
    local report_content
    report_content=$(cat "$report_file")
    assertContains "Report should contain main header" "$report_content" "--- System Performance Report ---"
    assertContains "Report should contain Date (mocked)" "$report_content" "Date: Mock Date:" # Check prefix
    assertContains "Report should contain Hostname (mocked)" "$report_content" "Hostname: mock-hostname"
    assertContains "Report should contain Uptime header" "$report_content" "--- Uptime ---"
    assertContains "Report should contain uptime output (mocked)" "$report_content" "mock uptime output"
    assertContains "Report should contain CPU header" "$report_content" "--- CPU Information ---"
    assertContains "Report should contain lscpu output (mocked)" "$report_content" "mock lscpu output"
    assertContains "Report should contain Memory header" "$report_content" "--- Memory Information ---"
    assertContains "Report should contain free output (mocked)" "$report_content" "mock free -h output"
    assertContains "Report should contain Disk header" "$report_content" "--- Disk Information ---"
    assertContains "Report should contain df output (mocked)" "$report_content" "mock df -h output"
    assertContains "Report should contain Network header" "$report_content" "--- Network Interfaces ---"
    assertContains "Report should contain ip output (mocked)" "$report_content" "mock ip link show output"
    assertContains "Report should contain Services header" "$report_content" "--- Running Services ---"
    assertContains "Report should contain systemctl output (mocked)" "$report_content" "mock systemctl list-units output"
    assertContains "Report should contain end marker" "$report_content" "--- End of Report ---"
}


# --- Load and Run shunit2 ---

# Source shunit2 (adjust path as necessary)
# If shunit2 is in your PATH, you might just need: . shunit2
# If it's in the same directory:
SHUNIT2_PATH="./shunit2"
if [ ! -f "$SHUNIT2_PATH" ]; then
    echo "FATAL: shunit2 not found at $SHUNIT2_PATH"
    # Attempt to find it in common locations or PATH
    if command -v shunit2 >/dev/null 2>&1; then
       SHUNIT2_PATH=$(command -v shunit2)
       echo "Found shunit2 in PATH: $SHUNIT2_PATH"
    else
       echo "Please download shunit2 and place it as './shunit2' or ensure it's in your PATH."
       exit 1
    fi
fi
# shellcheck source=./shunit2
. "$SHUNIT2_PATH"
