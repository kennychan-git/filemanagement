# Subsrename

Subsrename is a Python script that renames the largest .srt file in each directory within a specified folder. It is useful when you have a folder structure containing multiple directories, each with their own .srt files, and you want to rename the largest .srt file in each directory to match the directory name.

# Note
The script assumes that each directory contains .srt files and that you want to rename the largest .srt file in each directory. It specifically looks for files ending with "_English.srt".

If there are multiple .srt files with the same size in a directory, the script will rename the first one it encounters.

The renamed .srt files are also copied to the folder one level above the specified folder.

# Rename

Rename is a Python script that renames files in a specified directory according to a specified pattern. It is useful when you have a directory containing files with a certain naming convention and you want to rename them to a different format.

# Note
The script uses the glob module to get the list of files in the directory based on the provided file extension (.mp4 in this example). Make sure to modify the extension if you're working with files of a different type.

The script uses regular expressions to match the old file names and generate the new file names. Ensure that the pattern and format match your specific file naming convention.

If a new file name already exists in the directory, the script will not overwrite it and will print a warning message.

By default, the script is set to verbose mode, which provides detailed output for each file processed. If you prefer minimal output, set verbose_mode to False at the beginning of the script.
