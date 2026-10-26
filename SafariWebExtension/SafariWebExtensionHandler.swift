import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let appGroupID = "group.com.adshield.pro"

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(iOS 15.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        let defaults = UserDefaults(suiteName: appGroupID)
        var responseDict: [String: Any] = [
            "blockExternalNav": defaults?.bool(forKey: "adshield.blockExternalNav") ?? true,
            "strictLockAllLinks": defaults?.bool(forKey: "adshield.strictLockAllLinks") ?? false,
            "longPressZapEnabled": defaults?.bool(forKey: "adshield.longPressZapEnabled") ?? true,
            "zappedSelectors": defaults?.stringArray(forKey: "adshield.zappedSelectors") ?? []
        ]

        if let msgDict = message as? [String: Any], let action = msgDict["action"] as? String {
            if action == "saveZappedSelector", let selector = msgDict["selector"] as? String {
                var current = defaults?.stringArray(forKey: "adshield.zappedSelectors") ?? []
                if !current.contains(selector) {
                    current.append(selector)
                    defaults?.set(current, forKey: "adshield.zappedSelectors")
                }
                responseDict["zappedSelectors"] = current
            } else if action == "updateSettings" {
                if let b = msgDict["blockExternalNav"] as? Bool {
                    defaults?.set(b, forKey: "adshield.blockExternalNav")
                    responseDict["blockExternalNav"] = b
                }
                if let s = msgDict["strictLockAllLinks"] as? Bool {
                    defaults?.set(s, forKey: "adshield.strictLockAllLinks")
                    responseDict["strictLockAllLinks"] = s
                }
                if let l = msgDict["longPressZapEnabled"] as? Bool {
                    defaults?.set(l, forKey: "adshield.longPressZapEnabled")
                    responseDict["longPressZapEnabled"] = l
                }
            }
        }

        let response = NSExtensionItem()
        if #available(iOS 15.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseDict]
        } else {
            response.userInfo = ["message": responseDict]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
