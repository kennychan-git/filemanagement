import os
import glob
import re
from pathlib import Path

directory = "R:\\"  # Specify the directory path where the files are located

# Define the pattern and format for renaming
pattern = r'EP\.(\d+).*\.mp4'
format_str = 'Episode S01E{:02d}.mp4'

# Get the list of files in the directory
files = glob.glob(os.path.join(directory, "*.mp4"))

# Initialize a count for renamed files and a list for renamed episodes
renamed_count = 0
renamed_episodes = []

verbose_mode = True  # Set to True for verbose output, False for minimal output

# Iterate through each file
for file in files:
    # Extract the episode number from the file name using pattern matching
    match = re.search(pattern, os.path.basename(file))
    if match:
        episode_number = int(match.group(1))
        
        # Generate the new name using the format string
        new_name = format_str.format(episode_number)
        
        # Get the full file path of the old and new names
        old_path = Path(file)
        new_path = old_path.with_name(new_name)
        
        # Print information about the file and the renaming process
        if verbose_mode:
            print(f"File: {file}")
            print(f"Old Path: {old_path}")
            print(f"New Path: {new_path}")
        
        # Check if the new file name already exists
        if new_path.exists():
            print(f"New file name already exists: {new_path}")
        else:
            try:
                # Rename the file using pathlib
                old_path.rename(new_path)
                
                # Increment the count of renamed files
                renamed_count += 1
                
                # Add the renamed episode to the list
                renamed_episodes.append((file, str(new_path)))
                
                if verbose_mode:
                    print(f"Renamed {old_path} to {new_path}")
                else:
                    print(f"Renamed {old_path}")
            except Exception as e:
                print(f"Failed to rename {old_path}. Error: {str(e)}")
    else:
        print(f"No match found for file: {file}")

# Print the total number of episodes detected and renamed
print(f"Detected {len(renamed_episodes)} episodes. Renamed {renamed_count} files.")

if verbose_mode:
    print("List of renamed episodes:")
    for old_name, new_name in renamed_episodes:
        print(f"    {old_name} -> {new_name}")
