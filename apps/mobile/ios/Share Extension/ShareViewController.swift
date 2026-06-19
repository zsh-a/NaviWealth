import Social
import UniformTypeIdentifiers
import UIKit

private let shareSchemePrefix = "ShareMedia"
private let shareDefaultsKey = "ShareKey"
private let shareMessageKey = "ShareMessageKey"
private let appGroupInfoKey = "AppGroupId"

private enum SharedMediaType: String, Codable {
  case image
  case file
  case text
  case url
}

private struct SharedMediaFile: Codable {
  let path: String
  let mimeType: String?
  let thumbnail: String?
  let duration: Double?
  let message: String?
  let type: SharedMediaType
}

class ShareViewController: SLComposeServiceViewController {
  private var didProcessInput = false

  override func isContentValid() -> Bool {
    true
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !didProcessInput else { return }
    didProcessInput = true
    processInputAndRedirect()
  }

  override func didSelectPost() {
    processInputAndRedirect()
  }

  override func configurationItems() -> [Any]! {
    []
  }

  override func presentationAnimationDidFinish() {
    super.presentationAnimationDidFinish()
    navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "Send"
  }

  private func processInputAndRedirect() {
    let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    guard !attachments.isEmpty || !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      completeRequest()
      return
    }

    var shared = [SharedMediaFile]()
    let lock = NSLock()
    let group = DispatchGroup()

    if !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      shared.append(
        SharedMediaFile(
          path: contentText,
          mimeType: "text/plain",
          thumbnail: nil,
          duration: nil,
          message: contentText,
          type: .text
        )
      )
    }

    for attachment in attachments {
      if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
        group.enter()
        attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
          defer { group.leave() }
          guard let url = item as? URL else { return }
          lock.lock()
          shared.append(
            SharedMediaFile(
              path: url.absoluteString,
              mimeType: nil,
              thumbnail: nil,
              duration: nil,
              message: self.contentText,
              type: .url
            )
          )
          lock.unlock()
        }
      } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
        group.enter()
        attachment.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
          defer { group.leave() }
          guard let text = item as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
          }
          lock.lock()
          shared.append(
            SharedMediaFile(
              path: text,
              mimeType: "text/plain",
              thumbnail: nil,
              duration: nil,
              message: self.contentText,
              type: .text
            )
          )
          lock.unlock()
        }
      } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        group.enter()
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
          defer { group.leave() }
          guard let saved = self.saveImageItem(item) else { return }
          lock.lock()
          shared.append(saved)
          lock.unlock()
        }
      } else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          defer { group.leave() }
          guard let url = item as? URL, let saved = self.copyFile(url) else { return }
          lock.lock()
          shared.append(saved)
          lock.unlock()
        }
      }
    }

    group.notify(queue: .main) {
      self.save(shared)
      self.redirectToHostApp()
    }
  }

  private func saveImageItem(_ item: Any?) -> SharedMediaFile? {
    if let url = item as? URL {
      return copyFile(url, forcedType: .image)
    }
    guard let image = item as? UIImage else { return nil }
    let url = containerUrl().appendingPathComponent("\(UUID().uuidString).png")
    guard let data = image.pngData() else { return nil }
    do {
      try data.write(to: url, options: .atomic)
      return SharedMediaFile(
        path: url.absoluteString.removingPercentEncoding ?? url.absoluteString,
        mimeType: "image/png",
        thumbnail: nil,
        duration: nil,
        message: contentText,
        type: .image
      )
    } catch {
      return nil
    }
  }

  private func copyFile(_ sourceUrl: URL, forcedType: SharedMediaType? = nil) -> SharedMediaFile? {
    let destination = containerUrl().appendingPathComponent(
      sourceUrl.lastPathComponent.isEmpty ? UUID().uuidString : sourceUrl.lastPathComponent
    )
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: sourceUrl, to: destination)
      return SharedMediaFile(
        path: destination.absoluteString.removingPercentEncoding ?? destination.absoluteString,
        mimeType: UTType(filenameExtension: destination.pathExtension)?.preferredMIMEType,
        thumbnail: nil,
        duration: nil,
        message: contentText,
        type: forcedType ?? .file
      )
    } catch {
      return nil
    }
  }

  private func save(_ media: [SharedMediaFile]) {
    guard let data = try? JSONEncoder().encode(media) else { return }
    let defaults = UserDefaults(suiteName: appGroupId())
    defaults?.set(data, forKey: shareDefaultsKey)
    defaults?.set(contentText, forKey: shareMessageKey)
    defaults?.synchronize()
  }

  private func redirectToHostApp() {
    guard let url = URL(string: "\(shareSchemePrefix)-\(hostBundleId()):share") else {
      completeRequest()
      return
    }
    let selectorOpenUrl = sel_registerName("openURL:")
    var responder: UIResponder? = self
    while let current = responder {
      if current.responds(to: selectorOpenUrl) {
        _ = current.perform(selectorOpenUrl, with: url)
        completeRequest()
        return
      }
      responder = current.next
    }
    completeRequest()
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  private func containerUrl() -> URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId())!
  }

  private func appGroupId() -> String {
    (Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String) ?? "group.\(hostBundleId())"
  }

  private func hostBundleId() -> String {
    let extensionBundleId = Bundle.main.bundleIdentifier ?? "com.naviwealth.naviwealth.ShareExtension"
    return extensionBundleId.split(separator: ".").dropLast().joined(separator: ".")
  }
}
