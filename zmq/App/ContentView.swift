import SwiftUI

struct ContentView: View {
    @EnvironmentObject var adbClient: ADBClient
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DeviceConnectView()
                .tabItem {
                    Label("连接", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)

            DeviceInfoView()
                .tabItem {
                    Label("信息", systemImage: "info.circle")
                }
                .tag(1)

            ScreenMirrorView()
                .tabItem {
                    Label("投屏", systemImage: "display")
                }
                .tag(2)

            FileManagerView()
                .tabItem {
                    Label("文件", systemImage: "folder")
                }
                .tag(3)

            ConsoleView()
                .tabItem {
                    Label("控制台", systemImage: "terminal")
                }
                .tag(4)
        }
    }
}
