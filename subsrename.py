import os
import shutil

# specify the path to the folder you want to scan
folder_path = r"R:\Succession.S01.1080p.BluRay.x265-RARBG\Subs"

#folder_path = r"R:\House.S01.1080p.BluRay.x265-RARBG\Subs"

# get a list of all directories inside the specified folder
directories = [d for d in os.listdir(folder_path) if os.path.isdir(os.path.join(folder_path, d))]

# print the number of directories found
print("Number of directories found:", len(directories))

# loop through each directory and rename the largest file
for directory in directories:
    # get the full path to the current directory
    directory_path = os.path.join(folder_path, directory)
    
    # get a list of all .srt files in the current directory
    srt_files = [f for f in os.listdir(directory_path) if os.path.isfile(os.path.join(directory_path, f)) and f.endswith("_English.srt")]
    
    # find the largest .srt file in the directory
    largest_srt = max(srt_files, key=lambda f: os.path.getsize(os.path.join(directory_path, f)))
    
    # rename the largest .srt file to match the directory name
    old_path = os.path.join(directory_path, largest_srt)
    new_name = directory + ".srt"
    new_path = os.path.join(folder_path, new_name)
    try:
        os.rename(old_path, new_path)
    except shutil.SameFileError:
        pass
        
    # copy the renamed file to the folder 1 level above
    try:
        shutil.copy2(new_path, folder_path)
    except shutil.SameFileError:
        pass

    # move on to next folder
    continue
