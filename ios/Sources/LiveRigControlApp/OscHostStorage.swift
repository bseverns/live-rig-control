import Foundation

enum OscHostStorage {
    private static let key = "osc_host"

    static func loadDefault() -> String {
        let stored = UserDefaults.standard.string(forKey: key)
        if let stored, !stored.isEmpty {
            return stored
        }
        let plist = Bundle.main.object(forInfoDictionaryKey: "OSC_HOST") as? String
        return plist ?? ""
    }

    static func save(_ host: String) {
        UserDefaults.standard.set(host, forKey: key)
    }
}
