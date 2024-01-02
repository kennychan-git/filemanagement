import os
import cv2

# Function to get the fps from a video file
def get_fps(video_path):
    try:
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        return fps
    except Exception as e:
        return None

# Function to recursively scan for video files with fps of 200
def find_videos_with_fps(start_dir):
    target_fps = 200
    video_files = []

    for root, dirs, files in os.walk(start_dir):
        for file in files:
            if file.lower().endswith(('.mp4', '.mkv')):
                file_path = os.path.join(root, file)
                fps = get_fps(file_path)
                if fps is not None and fps == target_fps:
                    video_files.append(file_path)

    return video_files

# Specify the directory to start the scan
start_directory = "/path/to/your/directory"

# Find video files with fps of 200
result = find_videos_with_fps(start_directory)

# Print the list of filenames
for file in result:
    print(file)
