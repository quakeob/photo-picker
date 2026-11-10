import AppKit
import SwiftUI

/// Keeps the photo centred when it is smaller than the window.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

/// Fit-to-window photo with pinch, double-click and Z to see actual pixels, drag to pan.
final class ZoomView: NSScrollView {
    private let imageView = NSImageView()
    private var photoID: String?
    private(set) var isZoomed = false
    private var dragStart: (point: NSPoint, origin: NSPoint)?
    var onZoomChange: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        let clip = CenteringClipView()
        clip.drawsBackground = true
        clip.backgroundColor = ZoomView.canvas
        contentView = clip
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isEditable = false
        imageView.unregisterDraggedTypes()
        documentView = imageView
        allowsMagnification = true
        maxMagnification = 6
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        drawsBackground = true
        backgroundColor = ZoomView.canvas
    }
    required init?(coder: NSCoder) { fatalError() }

    static let canvas = NSColor(white: 0.105, alpha: 1)

    func show(_ image: NSImage?, pixelSize: CGSize?, id: String?) {
        let newPhoto = id != photoID
        photoID = id
        imageView.image = image
        guard let px = pixelSize ?? image?.size, px.width > 0, px.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let doc = NSSize(width: px.width / scale, height: px.height / scale)   // 1.0 magnification = actual pixels
        if imageView.frame.size != doc {
            imageView.frame = NSRect(origin: .zero, size: doc)
            if !isZoomed { fit() }
        }
        if newPhoto { isZoomed = false; fit() }
    }

    private var fitMagnification: CGFloat {
        let doc = imageView.frame.size, avail = frame.size
        guard doc.width > 0, doc.height > 0, avail.width > 0 else { return 1 }
        return min(avail.width / doc.width, avail.height / doc.height)
    }

    private func fit() {
        let m = fitMagnification
        minMagnification = min(m, 1)
        magnification = m
    }

    func setZoomed(_ z: Bool, at point: NSPoint? = nil) {
        guard z != isZoomed else { return }
        isZoomed = z
        if z {
            let p = point ?? NSPoint(x: imageView.frame.midX, y: imageView.frame.midY)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                animator().setMagnification(max(1, fitMagnification * 1.01), centeredAt: p)
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                animator().magnification = fitMagnification
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !isZoomed { fit() } else { minMagnification = min(fitMagnification, 1) }
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        let z = magnification > fitMagnification * 1.02
        if z != isZoomed { isZoomed = z; onZoomChange?(z) }
    }

    override func endGesture(with event: NSEvent) {
        super.endGesture(with: event)
        if !isZoomed { setZoomed(false); fit() }
    }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 {
            let p = imageView.convert(e.locationInWindow, from: nil)
            setZoomed(!isZoomed, at: p)
            onZoomChange?(isZoomed)
        } else if isZoomed {
            dragStart = (e.locationInWindow, contentView.bounds.origin)
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with e: NSEvent) {
        guard let start = dragStart else { return }
        let dx = (e.locationInWindow.x - start.point.x) / magnification
        let dy = (e.locationInWindow.y - start.point.y) / magnification
        contentView.scroll(to: NSPoint(x: start.origin.x - dx, y: start.origin.y - dy))
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with e: NSEvent) {
        if dragStart != nil { NSCursor.pop() }
        dragStart = nil
    }

    override func resetCursorRects() {
        if isZoomed { addCursorRect(bounds, cursor: .openHand) }
    }
}

struct PhotoCanvas: NSViewRepresentable {
    @ObservedObject var lib: Library

    func makeNSView(context: Context) -> ZoomView {
        let v = ZoomView()
        v.onZoomChange = { z in DispatchQueue.main.async { if lib.zoomed != z { lib.zoomed = z } } }
        return v
    }

    func updateNSView(_ v: ZoomView, context: Context) {
        v.show(lib.currentImage, pixelSize: lib.currentInfo?.pixelSize, id: lib.current?.id)
        v.setZoomed(lib.zoomed)
        v.window?.invalidateCursorRects(for: v)
    }
}
