import SwiftUI

@main
struct zmqApp: App {
    @StateObject private var adbClient = ADBClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(adbClient)
        }
    }
}
