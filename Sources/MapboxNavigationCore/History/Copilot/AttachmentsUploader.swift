import Foundation
import MapboxCommon

struct AttachmentArchive {
    struct FileType {
        var format: String
        var type: String

        static var gzip: Self { .init(format: "gz", type: "zip") }
    }

    var fileUrl: URL
    var fileName: String
    var fileId: String
    var sessionId: String
    var fileType: FileType
    var createdAt: Date
}

protocol AttachmentsUploader {
    func upload(accessToken: String, archive: AttachmentArchive) async throws
}

final class AttachmentsUploaderImpl: AttachmentsUploader {
    private enum Constants {
#if DEBUG
        static let baseUploadURL = "https://api-events-staging.tilestream.net"
#else
        static let baseUploadURL = "https://events.mapbox.com"
#endif
        static let mediaTypeZip = "application/zip"
    }

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
            .withFullTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withColonSeparatorInTimeZone,
        ]
        return formatter
    }()

    let options: MapboxCopilot.Options
    var sdkInformation: SdkInformation {
        options.sdkInformation
    }

    private var _filesDir: URL?
    private let lock = NSLock()
    private var filesDir: URL {
        lock.withLock {
            if let url = _filesDir {
                return url
            }

            let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
                ?? NSTemporaryDirectory()
            let url = URL(fileURLWithPath: cacheDir, isDirectory: true)
                .appendingPathComponent("NavigationHistoryAttachments")
            if FileManager.default.fileExists(atPath: url.path) == false {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            _filesDir = url
            return url
        }
    }

    init(options: MapboxCopilot.Options) {
        self.options = options
    }

    func upload(accessToken: String, archive: AttachmentArchive) async throws {
        let metadata: [String: String] = [
            "name": archive.fileName,
            "fileId": archive.fileId,
            "sessionId": archive.sessionId,
            "format": archive.fileType.format,
            "created": dateFormatter.string(from: archive.createdAt),
            "type": archive.fileType.type,
        ]
        let jsonData = (try? JSONEncoder().encode([metadata])) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        let log = options.log
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try HttpServiceFactory.getInstance().upload(for: .init(
                    filePath: archive.fileUrl.path,
                    url: uploadURL(accessToken),
                    headers: [:],
                    metadata: jsonString,
                    mediaType: Constants.mediaTypeZip,
                    sdkInformation: sdkInformation
                )) { status in
                    switch status.state {
                    case .failed:
                        let errorMessage = status.error?.message ?? "Unknown upload error"
                        let error = CopilotError(
                            errorType: .failedToUploadHistoryFile,
                            userInfo: ["errorMessage": errorMessage]
                        )
                        log?("Failed to upload session to attachements. \(errorMessage)")
                        continuation.resume(throwing: error)
                    case .finished:
                        continuation.resume()
                    case .pending, .inProgress:
                        break
                    @unknown default:
                        break
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func uploadURL(_ accessToken: String) throws -> String {
        return Constants.baseUploadURL + "/attachments/v1?access_token=\(accessToken)"
    }
}
