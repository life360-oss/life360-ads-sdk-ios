//
//  RemoteImageLoader.swift
//  Life360AdsDemoiOS
//

import UIKit

/// Loads and caches the remote images a native ad's assets point at.
///
/// Caching matters beyond saving requests here: the main image and icon come from the bid response, and
/// re-downloading them on every layout pass would make the ad's height jitter while it is being scrolled
/// past — exactly the thing viewability measurement is sensitive to.
enum RemoteImageLoader {

    private static let cache = NSCache<NSURL, UIImage>()

    /// Loads `urlString` into `imageView`, from cache when possible.
    ///
    /// The completion fires on the main queue after the image is set, so callers can react to the size
    /// the image gives the layout.
    static func load(_ urlString: String?, into imageView: UIImageView, completion: (() -> Void)? = nil) {
        guard let urlString, let url = URL(string: urlString) else { return }
        load(url, into: imageView, completion: completion)
    }

    static func load(_ url: URL, into imageView: UIImageView, completion: (() -> Void)? = nil) {
        if let cached = cache.object(forKey: url as NSURL) {
            imageView.image = cached
            completion?()
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async {
                imageView.image = image
                completion?()
            }
        }.resume()
    }
}
