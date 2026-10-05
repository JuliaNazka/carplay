import CryptoKit
import Foundation

/// Constantes e utilitários compartilhados entre o app e a extensão de transmissão.
/// Este arquivo é compilado nos dois targets (CarPlayMirror e BroadcastExtension).
///
/// O app e a extensão conversam por TCP em 127.0.0.1. Conexões de loopback não exigem
/// App Group nem a permissão de "Rede Local", então o app funciona mesmo instalado com
/// um Apple ID gratuito (ex.: via Sideloadly).
enum MirrorShared {
  static let port: UInt16 = 47_210

  /// Bundle do app principal (a extensão fica em CarPlayMirror.app/PlugIns/).
  static var hostAppBundleURL: URL {
    let url = Bundle.main.bundleURL
    guard url.pathExtension == "appex" else { return url }
    return url.deletingLastPathComponent().deletingLastPathComponent()
  }

  /// Segredo da sessão, derivado da pasta (aleatória a cada instalação) onde o iOS colocou
  /// o app. Outros apps não conseguem ler esse caminho, então só o app e a sua própria
  /// extensão completam o handshake — nenhum outro app recebe a imagem da tela.
  static let sessionToken: Data = {
    let appURL = hostAppBundleURL.resolvingSymlinksInPath()
    let identity = [
      "CarPlayMirror",
      appURL.deletingLastPathComponent().lastPathComponent,
      appURL.lastPathComponent,
    ].joined(separator: "|")
    return Data(SHA256.hash(data: Data(identity.utf8)))
  }()

  static func error(_ message: String, code: Int = 1) -> NSError {
    NSError(domain: "CarPlayMirror", code: code, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

/// Preferências de captura. O app guarda no UserDefaults e envia à extensão pelo socket.
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
    let defaults = UserDefaults.standard
    var settings = MirrorSettings.standard
    if let value = defaults.object(forKey: Key.maxFPS) as? Int { settings.maxFPS = value }
    if let value = defaults.object(forKey: Key.jpegQuality) as? Double { settings.jpegQuality = value }
    if let value = defaults.object(forKey: Key.maxDimension) as? Int { settings.maxDimension = value }
    if let value = defaults.string(forKey: Key.fillMode) { settings.fillMode = value }
    return settings.clamped()
  }

  func save() {
    let defaults = UserDefaults.standard
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

// MARK: - Protocolo

enum MessageType: UInt32 {
  /// Nos dois sentidos, sempre a primeira mensagem. Payload: token de 32 bytes.
  case hello = 1
  /// Extensão → app. Payload: largura (u32), altura (u32), JPEG.
  case frame = 2
  /// App → extensão. Payload: FPS (u32), qualidade × 1000 (u32), lado maior em px (u32).
  case settings = 3
  /// App → extensão: encerra a transmissão. Sem payload.
  case stop = 4
}

/// Mensagem com cabeçalho de 12 bytes (little-endian): magic | tipo | tamanho do payload.
struct Message {
  static let magic: UInt32 = 0x4350_4D31 // "CPM1"
  static let headerSize = 12
  static let maxPayloadLength = 16 * 1024 * 1024

  let type: MessageType
  let payload: Data

  func encoded() -> Data {
    var data = Data(capacity: Self.headerSize + payload.count)
    data.appendUInt32(Self.magic)
    data.appendUInt32(type.rawValue)
    data.appendUInt32(UInt32(payload.count))
    data.append(payload)
    return data
  }

  static func hello() -> Message {
    Message(type: .hello, payload: MirrorShared.sessionToken)
  }

  static func frame(jpeg: Data, width: Int, height: Int) -> Message {
    var payload = Data(capacity: 8 + jpeg.count)
    payload.appendUInt32(UInt32(width))
    payload.appendUInt32(UInt32(height))
    payload.append(jpeg)
    return Message(type: .frame, payload: payload)
  }

  static func settings(_ settings: MirrorSettings) -> Message {
    var payload = Data(capacity: 12)
    payload.appendUInt32(UInt32(settings.maxFPS))
    payload.appendUInt32(UInt32((settings.jpegQuality * 1000).rounded()))
    payload.appendUInt32(UInt32(settings.maxDimension))
    return Message(type: .settings, payload: payload)
  }

  static let stop = Message(type: .stop, payload: Data())

  var isValidHello: Bool {
    type == .hello && payload == MirrorShared.sessionToken
  }

  /// JPEG de uma mensagem `.frame`.
  var frameJPEG: Data? {
    guard type == .frame, payload.count > 8 else { return nil }
    return payload.subdata(in: (payload.startIndex + 8)..<payload.endIndex)
  }

  /// Preferências de uma mensagem `.settings`.
  var settingsValue: MirrorSettings? {
    guard type == .settings, payload.count >= 12 else { return nil }
    return MirrorSettings(
      maxFPS: Int(payload.readUInt32(at: 0)),
      jpegQuality: Double(payload.readUInt32(at: 4)) / 1000,
      maxDimension: Int(payload.readUInt32(at: 8)),
      fillMode: "fit"
    ).clamped()
  }
}

/// Acumula os bytes recebidos e separa as mensagens completas.
struct MessageParser {
  struct InvalidStream: Error {}

  private var buffer = Data()

  var bufferedCount: Int { buffer.count }

  mutating func append(_ bytes: UnsafeMutablePointer<UInt8>, count: Int) {
    buffer.append(bytes, count: count)
  }

  mutating func reset() {
    buffer.removeAll(keepingCapacity: false)
  }

  /// Retorna as mensagens completas disponíveis. Lança erro se o fluxo estiver corrompido.
  mutating func nextMessages() throws -> [Message] {
    var messages: [Message] = []
    var offset = 0
    while buffer.count - offset >= Message.headerSize {
      let length = Int(buffer.readUInt32(at: offset + 8))
      guard
        buffer.readUInt32(at: offset) == Message.magic,
        let type = MessageType(rawValue: buffer.readUInt32(at: offset + 4)),
        length <= Message.maxPayloadLength
      else {
        throw InvalidStream()
      }
      let total = Message.headerSize + length
      guard buffer.count - offset >= total else { break }

      let start = buffer.startIndex + offset + Message.headerSize
      messages.append(Message(type: type, payload: buffer.subdata(in: start..<(start + length))))
      offset += total
    }
    if offset > 0 {
      buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + offset))
    }
    return messages
  }
}

extension Data {
  mutating func appendUInt32(_ value: UInt32) {
    Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
  }

  /// Lê um UInt32 little-endian a `offset` bytes do início.
  func readUInt32(at offset: Int) -> UInt32 {
    withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
  }
}

// MARK: - Socket

enum LoopbackSocket {
  /// Endereço 127.0.0.1:`port`.
  static func address(port: UInt16) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
    return address
  }

  /// Executa `body` com o endereço convertido para `sockaddr` (para bind/connect).
  static func withAddress<Result>(port: UInt16, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result) -> Result {
    var address = address(port: port)
    return withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
  }

  static func setOption(_ fd: Int32, _ level: Int32, _ name: Int32, _ value: Int32) {
    var value = value
    setsockopt(fd, level, name, &value, socklen_t(MemoryLayout<Int32>.size))
  }

  static func setTimeout(_ fd: Int32, _ name: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, name, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  static func setNonBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
  }

  /// Escreve tudo, tratando escritas parciais. Em socket não bloqueante, espera até
  /// `timeoutMs` para o buffer liberar espaço.
  static func writeAll(_ fd: Int32, _ data: Data, timeoutMs: Int32 = 2000) -> Bool {
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
      guard var pointer = raw.baseAddress else { return true }
      var remaining = raw.count
      while remaining > 0 {
        let written = write(fd, pointer, remaining)
        if written > 0 {
          remaining -= written
          pointer = pointer.advanced(by: written)
        } else if written < 0 && errno == EINTR {
          continue
        } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
          var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
          guard poll(&descriptor, 1, timeoutMs) > 0 else { return false }
        } else {
          return false
        }
      }
      return true
    }
  }

  static func lastError() -> String {
    String(cString: strerror(errno))
  }
}
