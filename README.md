# PhotoSorts for macOS

**PhotoSorts** automatically organizes your photos and videos into date-based folders — safely, privately, and beautifully designed for macOS.

Available on the **Mac App Store** → [Coming Soon]

---

## Overview

PhotoSorts helps you instantly declutter your camera folders.
It detects the real capture date (from EXIF or video metadata) and sorts your media into folders by day, month, or year — all locally, with zero internet dependency.

---

## Key Features

- **Smart organization**
  - Sorts photos/videos by real capture date (not file modified date)
  - Choose between folder styles:
    - `YYYY`
    - `YYYY/MM`
    - `YYYY/MM/DD`
    - `Nested YYYY → YYYY_MM → YYYY_MM_DD`

- **Safety built in**
  - Detects and skips duplicates
  - Logs skipped files with clear reasons
  - Preflight permission and write tests

- **Privacy-first**
  - 100% local processing — no uploads, no accounts, no analytics
  - Works entirely within the macOS sandbox

- **User-friendly**
  - Drag & drop simplicity
  - Configurable “Move” or “Copy” behavior
  - Fully sandboxed and App Store approved

---

## How It Works

1. Choose a **Source Folder** (like your camera SD card or backup drive).  
2. Choose a **Destination Folder** (like `Desktop/Sorted`).  
3. Select your preferred **Folder Naming Format**.  
4. Click **Scan & Sort** — and watch your media organize itself.  
5. Review the optional `SkippedFiles-<timestamp>.txt` log if needed.

All processing happens locally on your Mac.  
PhotoSorts never reads or transmits personal data.

---

## System Requirements

- macOS **13.0 (Ventura)** or later  
- Apple Silicon or Intel Mac  
- Downloadable via the **Mac App Store**

---

## Support & Feedback

For any questions, suggestions, or bug reports, please create issues within GitHub.

---

## License

© 2025 Mario Abramovic. All Rights Reserved.  
Distributed exclusively via the Apple App Store.

---

## Developer Notes

Built entirely in **SwiftUI** using:
- AVFoundation  
- UniformTypeIdentifiers  
- ImageIO  
- AppKit  

PhotoSorts is sandbox-compliant, respecting all macOS file-access permissions through the standard folder picker.

---

## 🚀 Coming Soon
[App Store link placeholder] – expected release Q1 2026.
