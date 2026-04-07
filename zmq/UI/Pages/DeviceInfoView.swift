import SwiftUI

struct DeviceInfoView: View {
    @EnvironmentObject var adbClient: ADBClient
    @State private var device = ADBDevice()
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView("获取设备信息...")
                    } else if adbClient.isConnected {
                        DeviceCard(device: device)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "iphone.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("未连接设备")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 100)
                    }
                }
                .padding()
            }
            .navigationTitle("设备信息")
            .toolbar {
                Button(action: refreshInfo) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!adbClient.isConnected)
            }
        }
    }

    private func refreshInfo() {
        guard adbClient.isConnected else { return }
        isLoading = true

        let shell = ADBShell(client: adbClient)
        let deviceInfo = ADBDeviceInfo(shell: shell)

        Task {
            let info = await deviceInfo.getAllInfo()
            await MainActor.run {
                device = info
                device.isConnected = true
                isLoading = false
            }
        }
    }
}
