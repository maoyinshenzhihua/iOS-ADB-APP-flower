import SwiftUI

struct FileListItem: View {
    let file: FileInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: file.isDirectory ? "folder.fill" : fileIcon)
                    .font(.title3)
                    .foregroundColor(file.isDirectory ? .blue : .gray)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if !file.isDirectory {
                            Text(file.sizeString)
                        }
                        Text(file.permissionString)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var fileIcon: String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "webp": return "photo"
        case "mp4", "avi", "mkv", "mov": return "film"
        case "mp3", "wav", "flac", "aac": return "music.note"
        case "txt", "log", "md", "json", "xml", "csv": return "doc.text"
        case "apk": return "app.fill"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        default: return "doc"
        }
    }
}
