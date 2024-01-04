import sys
import os
import time
from moviepy.editor import VideoFileClip

# Function to check frame rate from a video file
def get_frame_rate(video_path):
    try:
        clip = VideoFileClip(video_path)
        frame_rate = clip.fps
        clip.close()
        return frame_rate
    except Exception as e:
        return None

# Function to recursively scan for movie files with a frame rate of 200 fps
def find_movie_files_with_frame_rate(start_dir, target_frame_rate=200):
    if not os.path.exists(start_dir):
        raise FileNotFoundError("The specified directory does not exist.")
    
    movie_files = []

    for root, dirs, files in os.walk(start_dir):
        for file in files:
            if file.lower().endswith(('.mp4', '.mkv')):
                file_path = os.path.join(root, file)
                frame_rate = get_frame_rate(file_path)
                if frame_rate is not None and frame_rate == target_frame_rate:
                    movie_files.append(file_path)

    return movie_files

# Specify the directory to start the scan
start_directory = "E:\\Shows\\the.mutatios.2023"

# Check if the specified directory exists
if not os.path.exists(start_directory):
    print(f"The specified directory: {start_directory} does not exist.")
else:
    # Start the timer
    start_time = time.time()

    # Find movie files with a frame rate of 200 fps
    result = find_movie_files_with_frame_rate(start_directory)

    # Stop the timer
    end_time = time.time()

    # Calculate the elapsed time
    elapsed_time = end_time - start_time

    # Check if any files were found and print them, or print "None"
    if result:
        for file_path in result:
            frame_rate = get_frame_rate(file_path)
            print("File: {} | Frame Rate: {:.2f} fps".format(file_path, frame_rate))
    else:
        print("None")
    # Print the directory being checked
    print(f"Checked Directory: {start_directory}")
    
    # Print the elapsed time
    print(f"Elapsed Time: {elapsed_time:.2f} seconds")
