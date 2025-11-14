//
//  ContentView.swift
//  PhotoSorts
//
//  Main UI and logic for PhotoSorts app.
//  Created by Mario Abramovic on 11/11/25.
//

import SwiftUI // SwiftUI for declarative UI
import UniformTypeIdentifiers // For file type checking (UTType)
import AVFoundation // For video metadata extraction
import ImageIO // For image metadata extraction
import AppKit // For macOS-specific UI (NSOpenPanel, NSImage)

/// Main app entry point. Sets ContentView as the root window.
@main
struct PhotoSortsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    // MARK: - State variables for UI and logic
    // Source and destination folder URLs
    @State private var sourceFolder: URL? = nil
    @State private var destinationFolder: URL? = nil
    // Options toggles
    @State private var includeSubfolders: Bool = true
    @State private var moveInsteadOfCopy: Bool = false
    @State private var structure: FolderStructure = .yyyy_mm_dd
    @State private var status: String = "Choose a source and destination to begin."
    // Progress and state
    @State private var isRunning = false
    @State private var processedCount = 0
    @State private var skippedCount = 0
    @State private var skippedEntries: [SkipEntry] = []
    @State private var writeSkippedLogToFile: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - App header/logo
            let found = NSImage(named: "LemonRant") != nil
            HStack(alignment: .center, spacing: 12) {
                Image("LemonRant")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photo Sorter")
                        .font(.largeTitle.bold())
                    Text("Sorts photos and videos into date-based folders.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)

            // Show a warning if app asset is missing
            if !found {
                Text("Missing asset: LemonRant")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // MARK: - Source and destination folder pickers
            Group {
                HStack {
                    LabeledContent("Source:") {
                        Text(sourceFolder?.path(percentEncoded: false) ?? "Not set")
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Button("Choose…") { sourceFolder = pickFolder() }
                }
                HStack {
                    LabeledContent("Destination:") {
                        Text(destinationFolder?.path(percentEncoded: false) ?? "Not set")
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Button("Choose…") { destinationFolder = pickFolder() }
                }
            }

            // MARK: - Options for sorting/moving
            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Include subfolders in source", isOn: $includeSubfolders)
                    Toggle("Move files (instead of copying)", isOn: $moveInsteadOfCopy)
                    Toggle("Write skipped files to SkippedFiles-<timestamp>.txt", isOn: $writeSkippedLogToFile)

                    Picker("Folder structure", selection: $structure) {
                        ForEach(FolderStructure.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Show an example of the selected folder structure
                    Text(structure.example)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding(.vertical, 4)
            }

            // MARK: - Action buttons (run, reset)
            HStack {
                Button(action: runSort) {
                    if isRunning { ProgressView().controlSize(.small) }
                    Text(isRunning ? "Running…" : "Scan & Sort")
                }
                // Disable if running or folders not set
                .disabled(sourceFolder == nil || destinationFolder == nil || isRunning)

                Button("Reset counts") {
                    processedCount = 0; skippedCount = 0; skippedEntries.removeAll()
                }
                .disabled(isRunning)
            }

            // MARK: - Status and progress display
            VStack(alignment: .leading, spacing: 6) {
                Text(status)
                Text("Processed: \(processedCount) | Skipped: \(skippedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Skipped files log
            if !skippedEntries.isEmpty {
                GroupBox("Skipped Files Log (why)") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(skippedEntries, id: \.self) { entry in
                                Text("\(entry.filename) — \(entry.reason)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 540)
    }

    // MARK: - Actions

    /// Starts the sorting process in a background thread.
    private func runSort() {
        guard let src = sourceFolder, let dst = destinationFolder else { return }

        // Validate that destination is not inside source (prevents recursion/overwrite)
        if dst.isDescendant(of: src) {
            status = "Error: Destination is inside Source. Choose a different destination (not within the source tree)."
            return
        }
        // Prevent source and destination from being identical
        if src == dst {
            status = "Error: Source and Destination are the same folder."
            return
        }

        // Preflight: Check for write permissions to destination
        switch preflightWriteTest(to: dst) {
        case .ok: break
        case .failed(let reason):
            status = "No write permission to destination: \(reason)"
            return
        }

        isRunning = true
        status = "Scanning…"
        processedCount = 0
        skippedCount = 0
        skippedEntries.removeAll()

        // Perform scan and sort on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Collect all media files from source (recursively if set)
            let urls = collectMediaFiles(in: src, includeSubfolders: includeSubfolders)
            var lastStatus = "Found \(urls.count) files. Sorting…"
            DispatchQueue.main.async { status = lastStatus }

            // Main sorting loop: move/copy each file to its destination
            for (idx, url) in urls.enumerated() {
                do {
                    // Try to extract the capture/creation date from metadata; fallback to file creation date or now
                    let date = extractCaptureDate(for: url) ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                    // Compute the destination folder path based on structure and date
                    let targetFolder = dst.appendingPathComponent(structure.path(for: date), conformingTo: .folder)
                    try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)

                    // Ensure destination file doesn't overwrite an existing file (add suffix if needed)
                    let targetURL = uniqueDestinationURL(baseFolder: targetFolder, originalURL: url)

                    // Move or copy the file as per user selection
                    if moveInsteadOfCopy {
                        try FileManager.default.moveItem(at: url, to: targetURL)
                    } else {
                        try FileManager.default.copyItem(at: url, to: targetURL)
                    }
                    DispatchQueue.main.async { processedCount += 1 }
                } catch {
                    let reason = (error as NSError).localizedDescription
                    DispatchQueue.main.async {
                        skippedCount += 1
                        skippedEntries.append(SkipEntry(filename: url.lastPathComponent, reason: reason))
                    }
                }

                // Periodically update status on main thread
                if idx % 25 == 0 || idx == urls.count - 1 {
                    lastStatus = "\(idx + 1)/\(urls.count) files processed…"
                    DispatchQueue.main.async {
                        status = lastStatus
                    }
                }
            }

            // If enabled, write skipped files log to destination folder
            if writeSkippedLogToFile, !skippedEntries.isEmpty {
                _ = writeSkippedLog(to: dst, entries: skippedEntries)
            }

            // Final UI update on main thread
            DispatchQueue.main.async {
                status = "Done. Moved/Copied \(processedCount) file(s); Skipped \(skippedCount)."
                isRunning = false
            }
        }
    }

    // MARK: - Helpers

    /// Shows a folder picker dialog and returns selected folder URL, or nil if cancelled.
    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Recursively collects image and video files from the given folder.
    private func collectMediaFiles(in folder: URL, includeSubfolders: Bool) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .typeIdentifierKey]
        var results: [URL] = []
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: includeSubfolders ? [.skipsHiddenFiles] : [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        )
        // Allowed file types (images and videos)
        let allowed: Set<UTType> = [.jpeg, .png, .tiff, .heic, .heif, .rawImage, .gif, .bmp, .movie, .video, .mpeg4Movie, .quickTimeMovie, .appleProtectedMPEG4Video]

        while let item = enumerator?.nextObject() as? URL {
            // Guard: Skip files inside the destination folder to avoid infinite loops or recursion
            if let dst = destinationFolder, item.isDescendant(of: dst) { continue }

            do {
                let values = try item.resourceValues(forKeys: Set(keys))
                if values.isDirectory == true { continue }
                // Check if file is an allowed image or video type
                if let uti = values.typeIdentifier, let type = UTType(uti), type.conforms(to: .image) || type.conforms(to: .movie) || allowed.contains(type) {
                    results.append(item)
                }
            } catch { continue }
        }
        return results
    }

    /// Writes the skipped files log to a text file in the given folder.
    private func writeSkippedLog(to folder: URL, entries: [SkipEntry]) -> URL? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd-HHmmss"
        let name = "SkippedFiles-\(df.string(from: Date())).txt"
        let fileURL = folder.appendingPathComponent(name)
        let header = "Photo Sorter — Skipped Files Log\nGenerated: \(Date())\n\n"
        let body = entries.map { "\($0.filename) — \($0.reason)" }.joined(separator: "\n") + "\n"
        do {
            try (header + body).write(to: fileURL, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                status = status + " Saved log to: \(fileURL.lastPathComponent)"
            }
            return fileURL
        } catch {
            DispatchQueue.main.async {
                status = status + " (Failed to save skipped log: \(error.localizedDescription))"
            }
            return nil
        }
    }

    /// Returns a destination URL in the target folder, adding a numeric suffix if needed to avoid overwriting files.
    private func uniqueDestinationURL(baseFolder: URL, originalURL: URL) -> URL {
        let name = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        var candidate = baseFolder.appendingPathComponent("\(name).\(ext)")
        var i = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = baseFolder.appendingPathComponent("\(name)-\(i).\(ext)")
            i += 1
        }
        return candidate
    }

    // Write-permission preflight: try creating & deleting a temp file
    /// Checks if the app can write to the given folder by creating and deleting a temp file.
    private enum PreflightResult { case ok; case failed(String) }
    private func preflightWriteTest(to folder: URL) -> PreflightResult {
        let testURL = folder.appendingPathComponent(".__write_test_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("test".utf8).write(to: testURL)
            try FileManager.default.removeItem(at: testURL)
            return .ok
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
    }
}

// MARK: - Types

/// Log entry for a skipped file (filename and reason)
struct SkipEntry: Hashable {
    let filename: String
    let reason: String
}

// MARK: - URL helpers

/// Checks if the URL is a descendant of the given parent folder (used to prevent recursion).
private extension URL {
    func isDescendant(of parent: URL) -> Bool {
        let p = parent.standardizedFileURL.resolvingSymlinksInPath()
        let s = self.standardizedFileURL.resolvingSymlinksInPath()
        let parentPath = p.path.hasSuffix("/") ? p.path : p.path + "/"
        return s.path != p.path && s.path.hasPrefix(parentPath)
    }
}

// MARK: - Folder structure

/// Enum for supported folder structures (flat, nested, etc.)
enum FolderStructure: CaseIterable {
    case yyyy
    case yyyy_mm
    case yyyy_mm_dd
    case hierarchical  // nested format

    /// Label for UI
    var label: String {
        switch self {
        case .yyyy: return "YYYY"
        case .yyyy_mm: return "YYYY/MM"
        case .yyyy_mm_dd: return "YYYY/MM/DD"
        case .hierarchical: return "YYYY/YYYY_MM/YYYY_MM_DD"
        }
    }

    /// Returns a relative folder path for a given date, according to the structure
    func path(for date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)

        switch self {
        case .yyyy:
            return String(format: "%04d", y)
        case .yyyy_mm:
            return String(format: "%04d/%02d", y, m)
        case .yyyy_mm_dd:
            return String(format: "%04d/%02d/%02d", y, m, d)
        case .hierarchical:
            // produces 2025/2025_11/2025_11_11
            let parent = String(format: "%04d", y)
            let mid = String(format: "%04d_%02d", y, m)
            let leaf = String(format: "%04d_%02d_%02d", y, m, d)
            return "\(parent)/\(mid)/\(leaf)"
        }
    }

    /// Example path for UI
    var example: String {
        switch self {
        case .yyyy: return "Example: 2025/"
        case .yyyy_mm: return "Example: 2025/11/"
        case .yyyy_mm_dd: return "Example: 2025/11/11/"
        case .hierarchical: return "Example: 2025/2025_11/2025_11_11/"
        }
    }
}

// MARK: - Metadata extraction

/// Extracts the capture/creation date for photos and videos from metadata when possible.
/// Returns nil if no date found.
func extractCaptureDate(for url: URL) -> Date? {
    let ext = url.pathExtension.lowercased()
    if ["mov", "mp4", "m4v", "avi", "mkv", "hevc"].contains(ext) {
        // Video file: try to extract video date
        return extractVideoDate(url)
    } else {
        // Photo file: try to extract photo date
        return extractPhotoDate(url)
    }
}

@available(macOS 13.0, *)
/// Async video date extraction for macOS 13+. Used internally by extractVideoDate.
private func extractVideoDateAsync(_ url: URL) async -> Date? {
    let asset = AVURLAsset(url: url)

    // Try creationDate via new async loader
    if let creationItem = try? await asset.load(.creationDate) {
        if let date = try? await creationItem.load(.dateValue) { return date }
    }

    // Fall back to common metadata with async loaders
    if let items = try? await asset.load(.commonMetadata) {
        for item in items {
            if let d = try? await item.load(.dateValue) { return d }
            if let s = try? await item.load(.stringValue), let parsed = parseEXIFDateString(s) { return parsed }
        }
    }
    return nil
}

// Legacy fallback for macOS < 13 using deprecated properties
@available(macOS, introduced: 10.13, deprecated: 13.0)
private func extractVideoDateLegacy(_ url: URL) -> Date? {
    let asset = AVURLAsset(url: url)
    if let creation = asset.creationDate?.dateValue { return creation }
    for item in asset.commonMetadata {
        if let date = item.dateValue { return date }
        if let str = item.stringValue, let parsed = parseEXIFDateString(str) { return parsed }
    }
    return nil
}

/// Synchronously extract the date from a video file (bridges async if available, or uses legacy)
private func extractVideoDate(_ url: URL) -> Date? {
    if #available(macOS 13.0, *) {
        var result: Date?
        let sem = DispatchSemaphore(value: 0)
        Task {
            result = await extractVideoDateAsync(url)
            sem.signal()
        }
        sem.wait()
        return result
    } else {
        return extractVideoDateLegacy(url)
    }
}

/// Extracts the photo's date from EXIF, TIFF, or GPS metadata, if available.
private func extractPhotoDate(_ url: URL) -> Date? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }

    // EXIF DateTimeOriginal is ideal
    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
        if let dt = exif[kCGImagePropertyExifDateTimeOriginal] as? String, let date = parseEXIFDateString(dt) {
            return date
        }
        // If subsecond time is available, add to original date
        if let sub = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let dt = exif[kCGImagePropertyExifDateTimeOriginal] as? String, var date = parseEXIFDateString(dt) {
            if let subInt = Int(sub) {
                date.addTimeInterval(Double(subInt) / 100.0)
            }
            return date
        }
    }

    // Fallback to TIFF date if available
    if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any], let dt = tiff[kCGImagePropertyTIFFDateTime] as? String, let date = parseEXIFDateString(dt) {
        return date
    }

    // Last resort: GPS timestamp + date
    if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
        if let dateStamp = gps[kCGImagePropertyGPSDateStamp] as? String, let timeStamp = gps[kCGImagePropertyGPSTimeStamp] as? String {
            let dt = dateStamp + " " + timeStamp
            return parseGPSDateTime(dt)
        }
    }

    return nil
}

/// Parses EXIF date string (e.g. "yyyy:MM:dd HH:mm:ss") or ISO8601 date.
private func parseEXIFDateString(_ string: String) -> Date? {
    // EXIF format: "yyyy:MM:dd HH:mm:ss"
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(secondsFromGMT: 0)
    fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
    if let d = fmt.date(from: string) { return d }

    // Sometimes it's ISO8601
    let iso = ISO8601DateFormatter()
    if let d2 = iso.date(from: string) { return d2 }
    return nil
}

/// Parses GPS date+time string for fallback photo date extraction.
private func parseGPSDateTime(_ string: String) -> Date? {
    // "yyyy:MM:dd HH:mm:ss.sss"
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(secondsFromGMT: 0)
    fmt.dateFormat = "yyyy:MM:dd HH:mm:ss.SSS"
    if let d = fmt.date(from: string) { return d }
    fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return fmt.date(from: string)
}

