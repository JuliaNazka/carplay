import Foundation

/// Servidor de socket Unix (no contêiner do App Group) que recebe os quadros JPEG
/// enviados pela extensão de transmissão.
final class FrameReceiver {
  /// Chamado na fila interna com o JPEG mais recente de cada leitura.
  var onFrame: ((Data) -> Void)?
  /// Chamado na fila interna quando a extensão conecta/desconecta.
  var onConnectionChange: ((Bool) -> Void)?

  private let queue = DispatchQueue(label: "com.carplaymirror.receiver", qos: .userInteractive)
  private let chunkSize = 256 * 1024
  private let chunk: UnsafeMutablePointer<UInt8>

  // Acessados somente em `queue`.
  private var acceptSource: DispatchSourceRead?
  private var listenFD: Int32 = -1
  private var readSource: DispatchSourceRead?
  private var clientFD: Int32 = -1
  private var buffer = Data()

  init() {
    chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
  }

  deinit {
    chunk.deallocate()
  }

  /// Abre o socket de escuta. `completion` recebe uma mensagem de erro ou nil.
  func start(completion: @escaping (String?) -> Void) {
    queue.async { completion(self.openListener()) }
  }

  /// Recria o socket de escuta se nenhuma extensão estiver conectada
  /// (o iOS pode invalidar sockets de apps que ficaram suspensos).
  func restartIfIdle(completion: @escaping (String?) -> Void) {
    queue.async {
      guard self.clientFD < 0 else { return completion(nil) }
      self.closeListener()
      completion(self.openListener())
    }
  }

  // MARK: - Escuta (queue)

  private func openListener() -> String? {
    guard listenFD < 0 else { return nil }
    guard let path = MirrorShared.socketPath else {
      return "App Group indisponível. Confira MIRROR_APP_GROUP_ID em ios/Config.xcconfig e a capability App Groups."
    }
    guard let address = makeUnixSocketAddress(path: path) else {
      return "Caminho do socket muito longo: \(path)"
    }

    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return "socket() falhou: \(Self.lastError())" }

    guard withSocketAddress(address, { bind(fd, $0, $1) }) == 0 else {
      let message = "bind() falhou: \(Self.lastError())"
      close(fd)
      return message
    }
    guard listen(fd, 4) == 0 else {
      let message = "listen() falhou: \(Self.lastError())"
      close(fd)
      return message
    }
    Self.setNonBlocking(fd)

    listenFD = fd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.acceptClient() }
    source.setCancelHandler { close(fd) }
    source.resume()
    acceptSource = source
    return nil
  }

  private func closeListener() {
    acceptSource?.cancel() // o cancel handler fecha o descritor
    acceptSource = nil
    listenFD = -1
  }

  private func acceptClient() {
    let fd = accept(listenFD, nil, nil)
    guard fd >= 0 else { return }

    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var bufferSize: Int32 = 1 << 20
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
    Self.setNonBlocking(fd)

    // Só existe uma transmissão por vez: a conexão mais nova substitui a anterior.
    disconnectClient(notify: false)
    clientFD = fd
    buffer.removeAll(keepingCapacity: true)

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.readAvailable() }
    source.setCancelHandler { close(fd) }
    source.resume()
    readSource = source
    onConnectionChange?(true)
  }

  private func disconnectClient(notify: Bool) {
    guard clientFD >= 0 else { return }
    readSource?.cancel() // o cancel handler fecha o descritor
    readSource = nil
    clientFD = -1
    buffer.removeAll(keepingCapacity: false)
    if notify {
      onConnectionChange?(false)
    }
  }

  // MARK: - Leitura (queue)

  private func readAvailable() {
    while clientFD >= 0 {
      let count = read(clientFD, chunk, chunkSize)
      if count > 0 {
        buffer.append(chunk, count: count)
      } else if count == 0 {
        parseFrames() // entrega o que já chegou completo antes de fechar
        disconnectClient(notify: true) // a extensão encerrou
        return
      } else if errno == EINTR {
        continue
      } else if errno == EAGAIN || errno == EWOULDBLOCK {
        break
      } else {
        disconnectClient(notify: true)
        return
      }
    }
    parseFrames()
  }

  private func parseFrames() {
    var offset = 0
    var latest: Data?

    while buffer.count - offset >= FrameHeader.size {
      guard let header = FrameHeader.decode(from: buffer, at: offset) else {
        disconnectClient(notify: true) // fluxo corrompido
        return
      }
      let total = FrameHeader.size + Int(header.payloadLength)
      guard buffer.count - offset >= total else { break }

      let start = buffer.startIndex + offset + FrameHeader.size
      latest = buffer.subdata(in: start..<(start + Int(header.payloadLength)))
      offset += total
    }

    if offset > 0 {
      buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + offset))
    }
    // Se vários quadros chegaram juntos, só o mais novo interessa.
    if let latest {
      onFrame?(latest)
    }
  }

  private static func setNonBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
  }

  private static func lastError() -> String {
    String(cString: strerror(errno))
  }
}
