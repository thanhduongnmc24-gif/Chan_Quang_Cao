import UIKit
import MobileCoreServices

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    private let appGroupID = "group.com.adshield.pro"
    private let sharedRulesFileName = "sharedBlockerList.json"

    func beginRequest(with context: NSExtensionContext) {
        // 1. Prefer dynamic rules edited inside the main AdShieldPro app via App Group
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let sharedFileURL = groupURL.appendingPathComponent(sharedRulesFileName)
            if FileManager.default.fileExists(atPath: sharedFileURL.path),
               let attachment = NSItemProvider(contentsOf: sharedFileURL) {
                let item = NSExtensionItem()
                item.attachments = [attachment]
                context.completeRequest(returningItems: [item], completionHandler: nil)
                return
            }
        }

        // 2. Fallback to bundled blockerList.json inside the Extension bundle
        guard let bundledURL = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
              let attachment = NSItemProvider(contentsOf: bundledURL) else {
            context.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
