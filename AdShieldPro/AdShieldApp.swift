import SwiftUI

@main
struct AdShieldApp: App {
    @StateObject private var adBlockManager = AdBlockManager()
    @StateObject private var ruleStore = BlockerRuleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(adBlockManager)
                .environmentObject(ruleStore)
                .preferredColorScheme(.dark)
        }
    }
}
