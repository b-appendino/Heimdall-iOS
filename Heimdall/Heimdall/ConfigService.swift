import Foundation
import os.log

class ConfigService {
    static let shared = ConfigService()

    private var settings: [String: Any] = [:]

    private init() {
        loadPlist()
    }
    
    // load the content of the Info.plist file
    private func loadPlist() {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let xml = FileManager.default.contents(atPath: path) else {
            NSLog("Failed to find .plist file in the bundle.")
            return
        }
        
        do {
            if let plistData = try PropertyListSerialization.propertyList(from: xml, options: .mutableContainers, format: nil) as? [String: Any] {
                settings = plistData
                NSLog("Successfully loaded .plist file.")
            }
        } catch {
            NSLog("Error reading plist: \(error.localizedDescription)")
        }
    }

    // get a plist string entry
    func stringValue(forKey key: String) -> String {
        guard let value = settings[key] as? String else {
            NSLog("Attempted to access String value for non-existent or incompatible key: \(key)")
            return ""
        }
        return value
    }
    
    // get a plist entry
    func arrayValue(forKey key: String) -> [Any]? {
        guard let value = settings[key] as? [Any] else {
            NSLog("Attempted to access Array value for non-existent or incompatible key: \(key)")
            return nil
        }
        return value
    }
}
