import Foundation

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    private let appGroupID = "group.com.adshield.pro"
    private let sharedRulesFileName = "sharedBlockerList.json"

    func beginRequest(with context: NSExtensionContext) {
        // 1. Try loading custom rules from shared App Group if valid and non-empty
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let sharedFileURL = groupURL.appendingPathComponent(sharedRulesFileName)
            if let data = try? Data(contentsOf: sharedFileURL),
               !data.isEmpty,
               (try? JSONSerialization.jsonObject(with: data)) != nil,
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
