import AppKit
import Photos
import UniformTypeIdentifiers

/// Apple Photos as a source. Photos are PHAssets; "picking" writes the asset's original
/// files (JPEG and RAW) into a folder, named like 2026-09-18_DSCF1141.RAF.
enum PhotosSource {
    static func authorize(_ done: @escaping (Bool) -> Void) {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: done(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                DispatchQueue.main.async { done(s == .authorized || s == .limited) }
            }
        default: done(false)
        }
    }

    /// Fujifilm bodies name files DSCF1234 (sRGB) or _DSF1234 (Adobe RGB).
    static func isFujifilm(_ filename: String) -> Bool {
        let u = filename.uppercased()
        return u.hasPrefix("DSCF") || u.hasPrefix("_DSF")
    }

    static func scan(fujifilmOnly: Bool, progress: @escaping (Int, Int) -> Void) -> [Photo] {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: opts)
        var out: [Photo] = []
        result.enumerateObjects { asset, i, _ in
            if i % 250 == 0 { progress(i, result.count) }
            let res = PHAssetResource.assetResources(for: asset).filter { $0.type == .photo || $0.type == .alternatePhoto }
            guard let primary = res.first(where: { $0.type == .photo }) ?? res.first else { return }
            if fujifilmOnly && !res.contains(where: { isFujifilm($0.originalFilename) }) { return }
            out.append(Photo(id: asset.localIdentifier, files: [], display: nil, date: asset.creationDate ?? .distantPast,
                             asset: asset, resources: res,
                             baseName: (primary.originalFilename as NSString).deletingPathExtension))
        }
        progress(result.count, result.count)
        return out
    }

    /// Synchronous; call off the main thread. nil maxPixel = full size.
    static func image(_ asset: PHAsset, maxPixel: Int?) -> NSImage? {
        let o = PHImageRequestOptions()
        o.isSynchronous = true
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true     // originals kept in iCloud get downloaded
        let size = maxPixel.map { CGSize(width: $0, height: $0) } ?? PHImageManagerMaximumSize
        var out: NSImage?
        PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: o) { img, _ in out = img }
        return out
    }

    static func info(_ asset: PHAsset) -> PhotoInfo {
        let o = PHImageRequestOptions()
        o.isSynchronous = true
        o.isNetworkAccessAllowed = true
        o.version = .original
        var info = PhotoInfo()
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: o) { data, _, _, _ in
            if let data, let src = CGImageSourceCreateWithData(data as CFData, nil) { info = Imaging.info(src) }
        }
        info.pixelSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        if info.captured == nil { info.captured = asset.creationDate }
        return info
    }

    static func isRaw(_ r: PHAssetResource) -> Bool {
        UTType(r.uniformTypeIdentifier)?.conforms(to: .rawImage) ?? rawExts.contains((r.originalFilename as NSString).pathExtension.lowercased())
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func exportName(_ r: PHAssetResource, date: Date) -> String {
        "\(day.string(from: date))_\(r.originalFilename)"
    }

    /// Writes one original file. Blocks until done; call off the main thread.
    static func write(_ r: PHAssetResource, to url: URL, date: Date) throws {
        let o = PHAssetResourceRequestOptions()
        o.isNetworkAccessAllowed = true
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        PHAssetResourceManager.default().writeData(for: r, toFile: url, options: o) { error in
            failure = error
            done.signal()
        }
        done.wait()
        if let failure { throw failure }
        // Keep the shot's date on the copy so Finder sorts by when it was taken.
        try? FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
    }
}
