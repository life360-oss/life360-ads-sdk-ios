import Foundation

/// Reads developer-configured query parameters appended to Life360 bid requests.
enum Life360QueryParameterStore {
    static let customQueryParametersKey = "l360_exchange_params"
    static var all: [String: String] {
        UserDefaults.standard.dictionary(forKey: customQueryParametersKey) as? [String: String] ?? [:]
    }
}
