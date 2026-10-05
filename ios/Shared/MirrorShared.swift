import Foundation

/// Constantes e utilitários compartilhados entre o app e a extensão de transmissão.
/// Este arquivo é compilado nos dois targets (CarPlayMirror e BroadcastExtension).
enum MirrorShared {
  /// Preenchido no Info.plist a partir de MIRROR_APP_GROUP_ID (ios/Config.xcconfig).
  static let appGroupIdentifier: String =
    Bundle.main.object(forInfoDictionaryKey: "MirrorAppGroupIdentifier") as? String ?? ""

  /// Nome curto de propósito: sockaddr_un.sun_path aceita no máximo 104 bytes.
  static let socketFileName = "cpm.sock"

  static var containerURL: URL? {
    guard !appGroupIdentifier.isEmpty else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
  }

  static var socketPath: String? {
    containerURL?.appendingPathComponent(socketFileName).path
  }

  static var defaults: UserDefaults? {
    guard !appGroupIdentifier.isEmpty else { return nil }
    return UserDefaults(suiteName: appGroupIdentifier)
  }

  enum Notifications {
    static var stopBroadcast: String { "\(appGroupIdentifier).stop-broadcast" }
    static var settingsChanged: String { "\(appGroupIdentifier).settings-changed" }
  }

  static func error(_ message: String, code: Int = 1) -> NSError {
    NSError(domain: "CarPlayMirror", code: code, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

/// Preferências de captura, gravadas no UserDefaults do App Group.
struct MirrorSettings: Equatable {
  var maxFPS: Int
  var jpegQuality: Double
  var maxDimension: Int
  var fillMode: String

  static let standard = MirrorSettings(maxFPS: 30, jpegQuality: 0.6, maxDimension: 1280, fillMode: "fit")

  private enum Key {
    static let maxFPS = "mirror.maxFPS"
    static let jpegQuality = "mirror.jpegQuality"
    static let maxDimension = "mirror.maxDimension"
    static let fillMode = "mirror.fillMode"
  }

  static func load() -> MirrorSettings {
    guard let defaults = MirrorShared.defaults else { return .standard }
    var settings = MirrorSettings.standard
    if let value = defaults.object(forKey: Key.maxFPS) as? Int { settings.maxFPS = value }
    if let value = defaults.object(forKey: Key.jpegQuality) as? Double { settings.jpegQuality = value }
    if let value = defaults.object(forKey: Key.maxDimension) as? Int { settings.maxDimension = value }
    if let value = defaults.string(forKey: Key.fillMode) { settings.fillMode = value }
    return settings.clamped()
  }

  func save() {
    guard let defaults = MirrorShared.defaults else { return }
    defaults.set(maxFPS, forKey: Key.maxFPS)
    defaults.set(jpegQuality, forKey: Key.jpegQuality)
    defaults.set(maxDimension, forKey: Key.maxDimension)
    defaults.set(fillMode, forKey: Key.fillMode)
  }

  func clamped() -> MirrorSettings {
    MirrorSettings(
      maxFPS: min(max(maxFPS, 5), 60),
      jpegQuality: min(max(jpegQuality, 0.1), 1.0),
      maxDimension: min(max(maxDimension, 480), 2622),
      fillMode: fillMode == "fill" ? "fill" : "fit"
    )
  }
}

/// Cabeçalho de 16 bytes (little-endian) enviado antes de cada quadro JPEG:
/// magic | tamanho do JPEG | largura | altura.
struct FrameHeader {
  static let size = 16
  static let magic: UInt32 = 0x4350_4D46 // "CPMF"
  static let maxPayloadLength: UInt32 = 16 * 1024 * 1024

  var payloadLength: UInt32
  var width: UInt32
  var height: UInt32

  func encoded() -> Data {
    var data = Data(capacity: Self.size)
    for value in [Self.magic, payloadLength, width, height] {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
  }

  /// Lê um cabeçalho a partir de `offset`. Retorna nil se o magic ou o tamanho forem inválidos.
  static func decode(from data: Data, at offset: Int) -> FrameHeader? {
    guard data.count - offset >= size else { return nil }
    let words: [UInt32] = data.withUnsafeBytes { raw in
      (0..<4).map { index in
        UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + index * 4, as: UInt32.self))
      }
    }
    guard words[0] == magic, words[1] > 0, words[1] <= maxPayloadLength else { return nil }
    return FrameHeader(payloadLength: words[1], width: words[2], height: words[3])
  }
}

/// Monta o endereço de um socket Unix. Retorna nil se o caminho não couber em sun_path.
func makeUnixSocketAddress(path: String) -> sockaddr_un? {
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let pathBytes = path.utf8CString.map { UInt8(bitPattern: $0) } // inclui o terminador NUL
  guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
  withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.copyBytes(from: pathBytes)
  }
  address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
  return address
}

/// Executa `body` com o endereço convertido para `sockaddr` (para bind/connect).
func withSocketAddress<Result>(_ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result) -> Result {
  var address = address
  return withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
  }
}

/// Envio de notificações Darwin (entre processos: app <-> extensão).
enum DarwinNotificationCenter {
  static func post(_ name: String) {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(name as CFString),
      nil,
      nil,
      true
    )
  }
}

/// Observa uma notificação Darwin enquanto a instância estiver viva.
final class DarwinNotificationObserver {
  private let name: String
  private let handler: () -> Void

  init(name: String, handler: @escaping () -> Void) {
    self.name = name
    self.handler = handler
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, _, _, _ in
        guard let observer else { return }
        Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue().handler()
      },
      name as CFString,
      nil,
      .deliverImmediately
    )
  }

  deinit {
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      CFNotificationName(name as CFString),
      nil
    )
  }
}
