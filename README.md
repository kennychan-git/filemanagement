# Universal Media Pipeline v4.7 (AVX-512 Optimized)

A high-performance, modular PowerShell media pipeline designed for **11th Gen+ Intel Core (Tiger Lake/Rocket Lake)** architectures. This suite optimizes video libraries for modern SoCs (Amlogic S922-H, Nvidia Shield) and Jellyfin servers.

---

## 🚀 The Hardware Advantage: AVX-512
This pipeline is specifically tuned for the **Intel i9-11950H**.
* **Engine:** `libx265` with `asm=avx512`.
* **Benefit:** Utilizing 512-bit wide registers allows for significantly higher throughput in HEVC motion estimation and pixel processing compared to standard AVX2.



---

## 🛠 The 3-Stage Workflow

### Stage 1: Universal Remuxer (`remux_to_mkv.ps1`)
**Goal:** Standardize container format and perform initial integrity checks.
* **Logic:** Switches containers (MP4, MOV, AVI) to MKV using `-c copy`.
* **Optimization:** Strips problematic data streams (`-map -0:d`) common in mobile/action-cam footage.
* **Verification:** Performs a high-speed QSV/CUDA hardware audit immediately after remuxing to catch corrupted bitstreams.

### Stage 2: Batch Transcoder (`transcode_v4.7.ps1`)
**Goal:** Efficient 10-bit HEVC encoding and TV-optimized audio.
* **Video:** Transcodes x264 to **x265 10-bit (yuv420p10le)** at CRF 28.
* **Audio Strategy:** * Preserves all original high-fidelity tracks (DTS-HD, TrueHD).
    * **TV Optimized Track:** Injects a stereo track using a surround-aware downmix: $FL = FL + 0.707C + 0.5SL$.
    * **Loudness:** Normalizes the TV track to **-16 LUFS** (Home Theater Standard) via the `loudnorm` filter.
* **Integrity:** Compares original vs. new duration; flags mismatches to prevent data loss.



### Stage 3: Universal Fleet Auditor (`fleet_auditor.ps1`)
**Goal:** Final Production Quality Control.
* **Logic:** Attempts a full hardware-accelerated decode of the final file.
* **Bimodal Governor:** Dynamically throttles threads based on GPU VRAM availability (Safety mode for 4GB cards, High-Perf for 8GB+).
* **Reporting:** Generates `failed_audit.txt` for any files that fail bitstream verification.

---

## 📂 Target Architecture
Designed for seamless playback on:
* **Jellyfin / Plex Servers** (Direct Play focus).
* **Amlogic S922-H / S922-X** SoCs (Native MKV/HEVC/PGS support).
* **Nvidia Shield TV Pro**.

## ⚠️ Requirements
* **FFmpeg v7.0+** (v8.0.1 recommended for latest AVX-512 optimizations).
* **PowerShell 7.x** (Required for `-Parallel` processing in Stage 3).
* **Hardware:** 11th Gen Intel CPU or newer for AVX-512 instruction support.


## Subsrename

Subsrename is a Python script that renames the largest .srt file in each directory within a specified folder. It is useful when you have a folder structure containing multiple directories, each with their own .srt files, and you want to rename the largest .srt file in each directory to match the directory name.

### Note
The script assumes that each directory contains .srt files and that you want to rename the largest .srt file in each directory. It specifically looks for files ending with "_English.srt".

If there are multiple .srt files with the same size in a directory, the script will rename the first one it encounters.

The renamed .srt files are also copied to the folder one level above the specified folder.

## Rename

Rename is a Python script that renames files in a specified directory according to a specified pattern. It is useful when you have a directory containing files with a certain naming convention and you want to rename them to a different format.

### Note
The script uses the glob module to get the list of files in the directory based on the provided file extension (.mp4 in this example). Make sure to modify the extension if you're working with files of a different type.

The script uses regular expressions to match the old file names and generate the new file names. Ensure that the pattern and format match your specific file naming convention.

If a new file name already exists in the directory, the script will not overwrite it and will print a warning message.

By default, the script is set to verbose mode, which provides detailed output for each file processed. If you prefer minimal output, set verbose_mode to False at the beginning of the script.
