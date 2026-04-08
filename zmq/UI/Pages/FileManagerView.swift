import SwiftUI

struct FileManagerView: View {
    @EnvironmentObject var adbClient: ADBClient
    @State private var currentPath = "/sdcard"
    @State private var files: [FileInfo] = []
    @State private var isLoading = false
    @State private var pathHistory: [String] = []
    @State private var showTransferSheet = false
    @State private var transferProgress: Float = 0

    var body: some View {
        NavigationView {
            VStack {
                pathBreadcrumb

                if isLoading {
                    ProgressView("加载中...")
                } else {
                    List(files) { file in
                        FileListItem(file: file) {
                            if file.isDirectory {
                                navigateTo(file.path)
                            }
                        }
                    }
                }
            }
            .navigationTitle("文件管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshList) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!adbClient.isConnected)
                }
            }
            .onAppear {
                if adbClient.isConnected {
                    refreshList()
                }
            }
        }
    }

    private var pathBreadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("root") {
                    navigateTo("/")
                }
                .foregroundColor(.primary)

                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(component) {
                        let newPath = "/" + pathComponents[0...index].joined(separator: "/")
                        navigateTo(newPath)
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private var pathComponents: [String] {
        currentPath.split(separator: "/").map(String.init)
    }

    private func navigateTo(_ path: String) {
        var cleanPath = path
        if cleanPath.hasSuffix("/") && cleanPath != "/" {
            cleanPath.removeLast()
        }

        if !pathHistory.contains(currentPath) {
            pathHistory.append(currentPath)
        }
        currentPath = cleanPath
        refreshList()
    }

    private func refreshList() {
        guard adbClient.isConnected else { return }
        isLoading = true

        let fileSync = ADBFileSync(client: adbClient)

        Task {
            let list = await fileSync.listDirectory(path: currentPath)
            await MainActor.run {
                files = list
                isLoading = false
            }
        }
    }
}
