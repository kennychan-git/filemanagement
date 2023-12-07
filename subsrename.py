import os
import shutil

# Specify the path to the folder you want to scan
folder_path = r"R:\House.of.the.Dragon.S01.BDRip.x265-ION265\Subs"

# Print the folder path
print("Folder Path:", folder_path)

# Check if the folder exists
if os.path.exists(folder_path):
    # Initialize a list to store directories
    directories = []

    # Traverse through directories using os.walk
    for root, dirnames, filenames in os.walk(folder_path):
        # Add each directory to the list
        directories.extend(dirnames)

    # Print the number of directories found
    print("Number of directories found:", len(directories))

# Define the target directory for copying the files
    parent_directory = os.path.dirname(folder_path)

    # Loop through each directory and rename the largest file
    for directory in directories:
        # Get the full path to the current directory
        directory_path = os.path.join(folder_path, directory)

        # Get a list of all .srt files in the current directory
        srt_files = [f for f in os.listdir(directory_path) if os.path.isfile(os.path.join(directory_path, f)) and f.endswith("_English.srt")]

        # Print the list of .srt files found
        print("Files in", directory_path + ":")
        print(srt_files)

        # Find the largest .srt file in the directory
        largest_srt = max(srt_files, key=lambda f: os.path.getsize(os.path.join(directory_path, f)))

        # Print the largest .srt file found
        print("Largest file in", directory_path + ":", largest_srt)

        # Rename the largest .srt file to match the directory name
        old_path = os.path.join(directory_path, largest_srt)
        new_name = directory + ".srt"
        new_path = os.path.join(folder_path, new_name)
        try:
            os.rename(old_path, new_path)
            print("Renamed", old_path, "to", new_path)
        except shutil.SameFileError:
            print("Failed to rename", old_path)

        # Copy the renamed file to the folder 1 level above
        try:
        # add newpath2 as root
            target_path = os.path.join(parent_directory, new_name)
            os.rename(new_path, target_path)
            print("Moved", new_path, "to", target_path)
        except OSError as e:
            print("Failed to move", new_path, "Error:", e)

    print("Renaming and copying completed.")
else:
    print("Folder not found:", folder_path)
