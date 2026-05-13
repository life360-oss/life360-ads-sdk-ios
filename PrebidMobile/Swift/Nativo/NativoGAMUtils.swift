import UIKit
import WebKit
import ObjectiveC.runtime

/// Extracts the GAM click URL from the GAM banner's internal WKWebView.
/// The click URL is in an anchor tag: `<a id="exchange-ping-url" href="https://adclick.g.doubleclick.net/pcs/click?...">`
@objcMembers
public class NativoGAMUtils: NSObject {
    
    public static func extractClickURL(
        from bannerView: UIView,
        completion: @escaping (URL?) -> Void
    ) {
        guard let webView = findWebView(in: bannerView) else {
            Log.debug("NativoGAMClickExtractor: No WKWebView found")
            completion(nil)
            return
        }

        webView.evaluateJavaScript(extractionJS) { result, error in
            if let error = error {
                Log.debug("NativoGAMClickExtractor: JS error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            if let urlString = result as? String, let url = URL(string: urlString) {
                Log.debug("NativoGAMClickExtractor: Extracted click URL: \(urlString)")
                completion(url)
            } else {
                Log.debug("NativoGAMClickExtractor: No click URL found")
                completion(nil)
            }
        }
    }
    
    public static func fire(url: URL) {
        let delegate = NoRedirectDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        session.dataTask(with: url) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            session.invalidateAndCancel()
        }.resume()
    }
    
    // MARK: - Private functions

    private static func readIvar(of object: AnyObject, name: String) -> AnyObject? {
        var cls: AnyClass? = type(of: object)
        while let currentClass = cls {
            var count: UInt32 = 0
            if let ivars = class_copyIvarList(currentClass, &count) {
                defer { free(ivars) }
                for i in 0..<Int(count) {
                    if let ivarName = ivar_getName(ivars[i]), String(cString: ivarName) == name {
                        guard let typeEncoding = ivar_getTypeEncoding(ivars[i]) else { return nil }
                        let encoding = String(cString: typeEncoding)
                        guard encoding.hasPrefix("@") else { return nil }
                        return object_getIvar(object, ivars[i]) as AnyObject?
                    }
                }
            }
            cls = class_getSuperclass(currentClass)
        }
        return nil
    }

    // MARK: - WKWebView Discovery
    
    private static func findWebView(in bannerView: UIView) -> WKWebView? {
        guard let gadWebAdView = findGADWebAdView(in: bannerView) else { return nil }
        guard let webViewController = readIvar(of: gadWebAdView, name: "_webViewController") else { return nil }
        return readIvar(of: webViewController, name: "_webView") as? WKWebView
    }

    private static func findGADWebAdView(in view: UIView) -> UIView? {
        let className = String(describing: type(of: view))
        if className == "GADWebAdView" { return view }
        for subview in view.subviews {
            if let found = findGADWebAdView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Click URL Extraction

    private static var extractionJS: String {
        return "(function() {"
            // Primary: find the exchange-ping-url anchor by ID
            + "var el = document.getElementById('exchange-ping-url');"
            + "if (el && el.href) return el.href;"
            // Fallback: any anchor with adclick or /pcs/click URL
            + "var anchors = document.querySelectorAll('a[href]');"
            + "for (var i = 0; i < anchors.length; i++) {"
            + "  var href = anchors[i].href;"
            + "  if (href.indexOf('adclick') !== -1 || href.indexOf('/pcs/click') !== -1) return href;"
            + "}"
            + "return null;"
            + "})();"
    }
}

private class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
