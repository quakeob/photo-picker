import AppKit
import ImageIO

let previewExts: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]
let rawExts: Set<String> = ["arw", "cr2", "cr3", "crw", "nef", "nrw", "raf", "orf", "rw2", "dng",
                            "pef", "srw", "3fr", "iiq", "x3f", "rwl", "srf", "sr2", "erf", "mos", "mrw"]
let photoExts = previewExts.union(rawExts)

/// One shot on the card. A RAW + JPEG pair with the same name is one photo.
struct Photo: Identifiable, Hashable {
    let id: String            // path without extension
    var files: [URL]
    var display: URL          // file decoded for the screen (JPEG preferred)
    var date: Date
    var name: String { display.deletingPathExtension().lastPathComponent }
    var kinds: String { files.map { $0.pathExtension.uppercased() }.sorted().joined(separator: " + ") }
}

struct PhotoInfo {
    var pixelSize: CGSize?
    var captured: Date?
    var camera: String?
    var lens: String?
    var exposure: String?
}

enum Imaging {
    static func scan(_ root: URL) -> [Photo] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        // Not .skipsHiddenFiles: that also skips photos carrying the "hidden" file flag, which
        // real cards and card copies do have. Only dot-files (.Trashes, ._DSCF1234.JPG) are skipped.
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsPackageDescendants]) else { return [] }
        var groups: [String: Photo] = [:]
        for case let url as URL in walker {
            if url.lastPathComponent.hasPrefix(".") { walker.skipDescendants(); continue }
            let ext = url.pathExtension.lowercased()
            guard photoExts.contains(ext),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let key = url.deletingPathExtension().path
            let date = v.creationDate ?? v.contentModificationDate ?? .distantPast
            if var p = groups[key] {
                p.files.append(url)
                if previewExts.contains(ext) && !previewExts.contains(p.display.pathExtension.lowercased()) { p.display = url }
                p.date = min(p.date, date)
                groups[key] = p
            } else {
                groups[key] = Photo(id: key, files: [url], display: url, date: date)
            }
        }
        // Cameras number shots in order (and start a new DCIM folder on rollover), so path order
        // is shooting order even when file dates were changed by copying.
        return groups.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private static func source(_ url: URL) -> CGImageSource? {
        CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    /// Decodes at most `maxPixel` on the long edge. Uses the embedded preview when it is at
    /// least `minAcceptable` px (fast for RAW), otherwise decodes the full image.
    static func image(_ url: URL, maxPixel: Int, minAcceptable: Int) -> NSImage? {
        guard let src = source(url) else { return nil }
        func render(fullDecode: Bool) -> CGImage? {
            let opts: [CFString: Any] = [
                (fullDecode ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent): true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
        var cg = render(fullDecode: false)
        if cg == nil || max(cg!.width, cg!.height) < min(minAcceptable, maxPixel) { cg = render(fullDecode: true) ?? cg }
        guard let img = cg else { return nil }
        return NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
    }

    static func info(_ url: URL) -> PhotoInfo {
        var info = PhotoInfo()
        guard let src = source(url),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return info }
        if let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue {
            let o = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            info.pixelSize = o >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        }
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            info.captured = f.date(from: s)
        }
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            let brand = make?.components(separatedBy: " ").first?.lowercased() ?? ""
            info.camera = (make == nil || model.lowercased().hasPrefix(brand)) ? model : "\(make!) \(model)"
        }
        info.lens = exif[kCGImagePropertyExifLensModel] as? String
        var parts: [String] = []
        if let t = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue, t > 0 {
            parts.append(t >= 0.5 ? "\(num(t)) s" : "1/\(Int((1 / t).rounded())) s")
        }
        if let f = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue { parts.append("ƒ/\(num(f))") }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first { parts.append("ISO \(iso.intValue)") }
        if let fl = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue { parts.append("\(num(fl)) mm") }
        info.exposure = parts.isEmpty ? nil : parts.joined(separator: "   ")
        return info
    }

    private static func num(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
