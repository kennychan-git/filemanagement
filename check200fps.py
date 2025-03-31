import sys
import os
import time
import argparse  # Import argparse for command-line arguments
from moviepy.editor import VideoFileClip
from datetime import datetime
from typing import List, Tuple, Optional, Sequence # For type hinting

# --- Constants ---
DEFAULT_TARGET_FRAME_RATE: float = 25.0
SUPPORTED_EXTENSIONS: Tuple[str, ...] = ('.mp4', '.mkv', '.avi', '.mov', '.wmv') # Easily extendable

# --- Functions ---

def get_frame_rate(video_path: str) -> Optional[float]:
    """
    Attempts to extract the frame rate from a video file.

    Args:
        video_path: The path to the video file.

    Returns:
        The frame rate as a float if successful, otherwise None.
    """
    try:
        # Use a 'with' statement for automatic resource management (though moviepy might not strictly need it here)
        with VideoFileClip(video_path) as clip:
            frame_rate = clip.fps
        return frame_rate
    except Exception as e:
        # Log the error for diagnostics but allow the script to continue
        print(f"\nWarning: Could not process file '{os.path.basename(video_path)}'. Error: {e}", file=sys.stderr)
        return None

def find_movie_files_with_frame_rate(
    start_dir: str,
    target_fps: float,
    extensions: Sequence[str]
) -> List[Tuple[str, float]]:
    """
    Recursively scans a directory for movie files exceeding a target frame rate.

    Args:
        start_dir: The directory path to start the scan from.
        target_fps: The frame rate threshold. Files with FPS > target_fps will be returned.
        extensions: A sequence of lowercase file extensions to check (e.g., ('.mp4', '.mkv')).

    Returns:
        A list of tuples, where each tuple contains (file_path, frame_rate)
        for files exceeding the target frame rate.

    Raises:
        FileNotFoundError: If the start_dir does not exist.
    """
    if not os.path.isdir(start_dir): # More specific check for directory
        raise FileNotFoundError(f"The specified directory does not exist or is not a directory: {start_dir}")

    movie_files_found: List[Tuple[str, float]] = []
    file_count = 0

    print(f"Scanning directory: {start_dir}")
    print(f"Looking for files with FPS > {target_fps}")
    print("-" * 30)

    for root, _, files in os.walk(start_dir):
        for file in files:
            if file.lower().endswith(extensions):
                file_path = os.path.join(root, file)
                file_count += 1
                # Provide some feedback to the user
                print(f"\rChecking file {file_count}: {os.path.basename(file_path)}...", end="", flush=True)

                frame_rate = get_frame_rate(file_path)

                if frame_rate is not None and frame_rate > target_fps:
                    movie_files_found.append((file_path, frame_rate))
                    # Print immediately when found (optional, can remove if too noisy)
                    # print(f"\n -> Found: {file_path} | Frame Rate: {frame_rate:.2f} fps")


    print("\n" + "-" * 30) # Newline after progress indicator and separator
    print(f"Scan complete. Checked {file_count} potential video files.")
    return movie_files_found

# --- Main Execution ---

def main():
    """
    Main function to parse arguments and run the scan.
    """
    parser = argparse.ArgumentParser(
        description=f"Scan a directory for video files exceeding a specified frame rate. Supported extensions: {', '.join(SUPPORTED_EXTENSIONS)}"
    )
    parser.add_argument(
        "start_directory",
        help="The directory to start the scan from."
    )
    parser.add_argument(
        "-t", "--target-fps",
        type=float,
        default=DEFAULT_TARGET_FRAME_RATE,
        help=f"The target frame rate. Files with FPS above this value will be listed (default: {DEFAULT_TARGET_FRAME_RATE})."
    )
    parser.add_argument(
        "-e", "--extensions",
        nargs='+', # Allows multiple extensions like -e .mp4 .avi
        default=list(SUPPORTED_EXTENSIONS),
        help=f"List of video file extensions to check (e.g., .mp4 .mkv). Default is {' '.join(SUPPORTED_EXTENSIONS)}."
    )

    args = parser.parse_args()

    # Ensure extensions start with a dot and are lowercase
    valid_extensions = tuple(ext.lower() if ext.startswith('.') else f".{ext.lower()}" for ext in args.extensions)

    try:
        # Get the current date and time before starting
        current_time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"Script started at: {current_time_str}")

        # Start the timer
        start_time = time.monotonic() # Use monotonic clock for measuring intervals

        # Find movie files
        results = find_movie_files_with_frame_rate(
            args.start_directory,
            args.target_fps,
            valid_extensions
        )

        # Stop the timer
        end_time = time.monotonic()
        elapsed_time = end_time - start_time

        # --- Print Results ---
        print("\n--- Results ---")
        if results:
            print(f"Found {len(results)} file(s) with frame rate > {args.target_fps} fps:")
            # Sort results alphabetically by path for consistent output
            results.sort(key=lambda item: item[0])
            for file_path, frame_rate in results:
                 # Use the stored frame_rate, no need to call get_frame_rate again
                print(f"  File: {file_path} | Frame Rate: {frame_rate:.2f} fps")
        else:
            print(f"No files found with frame rate > {args.target_fps} fps in the specified directory.")

        print("-" * 15)
        print(f"Checked Directory: {os.path.abspath(args.start_directory)}") # Show absolute path
        print(f"Target FPS: > {args.target_fps}")
        print(f"Checked Extensions: {', '.join(valid_extensions)}")
        print(f"Elapsed Time: {elapsed_time:.2f} seconds")

    except FileNotFoundError as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1) # Exit with a non-zero status code to indicate error
    except Exception as e:
        print(f"\nAn unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
