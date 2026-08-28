#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

/// Utilities for creating and styling CarPlay image assets and SF Symbols.
@MainActor
enum CarPlayImageHelper {
    private static let cache = NSCache<NSString, UIImage>()

    /// Standard artwork size for CarPlay list item icons.
    static let itemImageSize = CGSize(width: 48, height: 48)

    /// Formats a cover artwork image into a rounded square for CarPlay.
    static func formatArtwork(_ image: UIImage, size: CGSize = CGSize(width: 48, height: 48), cornerRadius: CGFloat = 8) -> UIImage {
        let key = "art-\(image.hash)-\(Int(size.width))x\(Int(size.height))-\(Int(cornerRadius))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let rendered = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            path.addClip()

            let sourceAspect = image.size.width / max(image.size.height, 1)
            var drawRect = rect
            if sourceAspect > 1 {
                drawRect.size.width = size.height * sourceAspect
                drawRect.origin.x = -(drawRect.size.width - size.width) / 2
            } else if sourceAspect < 1 {
                drawRect.size.height = size.width / sourceAspect
                drawRect.origin.y = -(drawRect.size.height - size.height) / 2
            }
            image.draw(in: drawRect)
        }

        cache.setObject(rendered, forKey: key)
        return rendered
    }

    /// Formats an artist avatar into a circle for CarPlay.
    static func formatAvatar(_ image: UIImage, diameter: CGFloat = 48) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let key = "avatar-\(image.hash)-\(Int(diameter))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let rendered = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(ovalIn: rect)
            path.addClip()

            let sourceAspect = image.size.width / max(image.size.height, 1)
            var drawRect = rect
            if sourceAspect > 1 {
                drawRect.size.width = diameter * sourceAspect
                drawRect.origin.x = -(drawRect.size.width - diameter) / 2
            } else if sourceAspect < 1 {
                drawRect.size.height = diameter / sourceAspect
                drawRect.origin.y = -(drawRect.size.height - diameter) / 2
            }
            image.draw(in: drawRect)
        }

        cache.setObject(rendered, forKey: key)
        return rendered
    }

    /// Creates a styled icon badge with an SF Symbol and background fill.
    static func symbolBadge(
        systemName: String,
        tint: UIColor = .systemRed,
        backgroundColor: UIColor? = nil,
        size: CGSize = CGSize(width: 48, height: 48),
        pointSize: CGFloat = 22,
        cornerRadius: CGFloat = 10
    ) -> UIImage {
        let key = "badge-\(systemName)-\(tint.description)-\(backgroundColor?.description ?? "none")-\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let bg = backgroundColor ?? tint.withAlphaComponent(0.15)
        let rendered = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            bg.setFill()
            bgPath.fill()

            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            if let symbol = UIImage(systemName: systemName, withConfiguration: config)?.withTintColor(tint, renderingMode: .alwaysOriginal) {
                let symbolSize = symbol.size
                let drawRect = CGRect(
                    x: (size.width - symbolSize.width) / 2,
                    y: (size.height - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbol.draw(in: drawRect)
            }
        }

        cache.setObject(rendered, forKey: key)
        return rendered
    }

    /// Placeholder image for songs / tracks.
    static var trackPlaceholder: UIImage {
        symbolBadge(
            systemName: "music.note",
            tint: .secondaryLabel,
            backgroundColor: UIColor.secondarySystemFill,
            pointSize: 20
        )
    }

    /// Placeholder image for playlists.
    static var playlistPlaceholder: UIImage {
        symbolBadge(
            systemName: "music.note.list",
            tint: .systemRed,
            backgroundColor: UIColor.systemRed.withAlphaComponent(0.12),
            pointSize: 20
        )
    }

    /// Placeholder image for albums.
    static var albumPlaceholder: UIImage {
        symbolBadge(
            systemName: "opticaldisc",
            tint: .systemOrange,
            backgroundColor: UIColor.systemOrange.withAlphaComponent(0.12),
            pointSize: 20
        )
    }

    /// Placeholder image for artists.
    static var artistPlaceholder: UIImage {
        symbolBadge(
            systemName: "music.mic",
            tint: .systemIndigo,
            backgroundColor: UIColor.systemIndigo.withAlphaComponent(0.12),
            pointSize: 20,
            cornerRadius: 24
        )
    }
}
#endif
