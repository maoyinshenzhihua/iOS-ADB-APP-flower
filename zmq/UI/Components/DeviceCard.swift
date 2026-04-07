import SwiftUI

struct DeviceCard: View {
    let device: ADBDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.blue)
                Text(device.model)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(device.isConnected ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
            }

            Divider()

            InfoRow(icon: "number", label: "序列号", value: device.serialNo)
            InfoRow(icon: "iphone", label: "Android版本", value: device.androidVersion)
            InfoRow(icon: "rectangle", label: "分辨率", value: device.resolution)
            InfoRow(icon: "chip", label: "CPU", value: device.cpu)
            InfoRow(icon: "memorychip", label: "内存", value: device.memory)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.secondary)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
