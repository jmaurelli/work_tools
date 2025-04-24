Linux Diagnostic Script Edit Notes.

04/23
Issue 1: Zip file created in the temporary directory which is then deleted.

Problem: The script changes into the $output_dir (cd "$output_dir"). When zip is called with "$zip_filename", it creates the zip file inside the current directory ($output_dir). Immediately after, rm -rf "$output_dir" deletes this directory and the zip file within it.
Solution: Specify an output path for the zip file that is outside the $output_dir. A simple choice is /tmp/ itself. We also need to adjust the source paths within the zip command since we are no longer in the $output_dir when creating the zip (or adjust how we specify the files from within the directory). The easiest way is to create the zip file in /tmp/ while still being inside $output_dir, referencing the contents of the current directory (.) for the zip command.
Issue 2: Log files with wildcards are reported as "not found" by collect_files and potentially not added to the zip.

Problem: The collect_files function iterates through the arguments ("${log_files[@]}") literally. When it encounters /var/log/messages*, it checks for a file literally named messages* using [ ! -e "$file" ]. This file doesn't exist; the wildcard * is not expanded by the -e test. Therefore, collect_files correctly reports (based on its logic) that the literal pattern string doesn't exist as a file. However, when the zip command is invoked later (zip ... "${log_files[@]}"), the shell does expand the wildcards before zip runs (this is called globbing). So, zip likely is getting the correct list of expanded files (e.g., /var/log/messages, /var/log/messages-20230101, etc.), but the earlier warnings from collect_files are confusing and incorrect regarding the intended files.
Solution: We need to expand the wildcards before passing the list to collect_files and zip. We can create a new array containing the expanded file paths. We should use shopt -s nullglob temporarily to ensure that if a pattern matches no files, it expands to nothing instead of the pattern itself.
Here are the proposed edits with explanations:

Summary of Changes:

Zip File Location (Issue 1):
Defined zip_filename with the full path /tmp/... at the beginning.
Modified the zip command to output to $zip_filename (which is now /tmp/...).
Used . inside the zip command to include all files from the current directory ($output_dir).
Updated the success message to correctly state the archive is in /tmp/.

Log File Wildcards (Issue 2):
Renamed log_files to log_patterns for clarity.
Added a loop that iterates through log_patterns.
Used shopt -s nullglob and shopt -u nullglob around the expansion expanded_paths=( $pattern ) to correctly handle patterns matching zero or multiple files.
Created a new array expanded_log_files to store the actual file paths found after globbing.
Added a warning if a pattern matches no files.
Called collect_files with the expanded_log_files array, so it checks actual files.
Called zip with the expanded_log_files array, ensuring it tries to add the specific files found.

General Improvements:
Used mktemp -d for safer temporary directory creation.
Added a trap cleanup EXIT function to ensure the temporary directory is removed even if the script fails midway.
Redirected error/warning messages from collect_files and script errors to standard error (>&2).
Used printf instead of echo in generate_report for potentially better consistency.
Used pushd/popd for directory navigation (slightly safer than cd).
Added -b (batch mode) to top command to make its output suitable for redirection.
Added count 1 to iostat to prevent it from running indefinitely if interval is specified.
Removed the output_file argument from run_command calls as it was redundant with the redirection already happening inside the function based on the 3rd argument.