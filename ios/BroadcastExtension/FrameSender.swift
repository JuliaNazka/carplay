import Foundation

/// Cliente TCP (127.0.0.1) que envia os quadros ao app principal. Faz um handshake com o
/// token da instalação antes de mandar qualquer imagem e reconecta sozinho caso o app
/// ainda não esteja rodando ou seja reiniciado.
final class FrameSender {
  /// Chamado (em uma fila interna) sempre que uma nova conexão é estabelecida.
  var onConnected: (() -> Void)?
  /// Chamado (em uma fila interna) quando um envio termina e o próximo quadro pode ir.
  var onIdle: (() -> Void)?
  /// Chamado (em uma fila interna) quando o app envia novas preferências.
  var onSettings: ((MirrorSettings) -> Void)?
  /// Chamado (em uma fila interna) quando o app pede para encerrar a transmissão.
  var onStop: (() -> Void)?

  private let queue = DispatchQueue(label: "com.carplaymirror.sender", qos: .userInteractive)
  private let chunkSize = 64 * 1024
  private let chunk: UnsafeMutablePointer<UInt8>

  // Acessados somente em `queue`.
  private var socketFD: Int32 = -1
  private var readSource: DispatchSourceRead?
  private var parser = MessageParser()
  private var reconnectTimer: DispatchSourceTimer?

  private let lock = NSLock()
  private var running = false
  private var connected = false
  private var busy = false

  var isConnected: Bool { withLock { connected } }
  var isBusy: Bool { withLock { busy } }

  init() {
    chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
  }

  deinit {
    chunk.deallocate()
  }

  func start() {
    withLock { running = true }
    queue.async {
      self.connectIfNeeded()
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now() + 1, repeating: 1)
      timer.setEventHandler { [weak self] in self?.connectIfNeeded() }
      timer.resume()
      self.reconnectTimer = timer
    }
  }

  func stop() {
    withLock { running = false }
    queue.async {
      self.reconnectTimer?.cancel()
      self.reconnectTimer = nil
      self.closeSocket()
    }
  }

  /// Envia um quadro. Se já houver um envio em andamento ou não houver conexão, descarta.
  func send(_ frame: EncodedFrame) {
    let accepted: Bool = withLock {
      guard connected, !busy else { return false }
      busy = true
      return true
    }
    guard accepted else { return }

    queue.async {
      let message = Message.frame(jpeg: frame.jpeg, width: frame.width, height: frame.height)
      let ok = self.socketFD >= 0 && LoopbackSocket.writeAll(self.socketFD, message.encoded())
      if !ok {
        self.closeSocket()
      }
      self.withLock { self.busy = false }
      if ok {
        self.onIdle?()
      }
    }
  }

  // MARK: - Conexão (queue)

  private func connectIfNeeded() {
    guard withLock({ running }), socketFD < 0 else { return }

    let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    guard fd >= 0 else { return }
    LoopbackSocket.setOption(fd, SOL_SOCKET, SO_NOSIGPIPE, 1)
    LoopbackSocket.setOption(fd, IPPROTO_TCP, TCP_NODELAY, 1)
    LoopbackSocket.setOption(fd, SOL_SOCKET, SO_SNDBUF, 1 << 20)
    // Se o app estiver suspenso, não fica bloqueado para sempre.
    LoopbackSocket.setTimeout(fd, SO_SNDTIMEO, seconds: 2)
    LoopbackSocket.setTimeout(fd, SO_RCVTIMEO, seconds: 2)

    guard
      LoopbackSocket.withAddress(port: MirrorShared.port, { connect(fd, $0, $1) }) == 0,
      LoopbackSocket.writeAll(fd, Message.hello().encoded())
    else {
      close(fd)
      return
    }

    // Handshake: o app precisa responder com o mesmo token antes de recebermos qualquer
    // imagem (impede que outro app escutando nessa porta receba a tela).
    parser.reset()
    var reply: [Message] = []
    while reply.isEmpty {
      let count = read(fd, chunk, chunkSize)
      if count < 0 && errno == EINTR { continue }
      guard count > 0 else {
        close(fd)
        return
      }
      parser.append(chunk, count: count)
      guard let messages = try? parser.nextMessages(), parser.bufferedCount <= 1024 || !messages.isEmpty else {
        close(fd)
        return
      }
      reply = messages
    }
    guard reply[0].isValidHello else {
      close(fd)
      return
    }

    socketFD = fd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.readAvailable() }
    source.setCancelHandler { close(fd) }
    source.resume()
    readSource = source

    withLock { connected = true }
    reply.dropFirst().forEach(handle)
    onConnected?()
  }

  private func readAvailable() {
    guard socketFD >= 0 else { return }
    var closed = false
    while true {
      let count = recv(socketFD, chunk, chunkSize, MSG_DONTWAIT)
      if count > 0 {
        parser.append(chunk, count: count)
      } else if count < 0 && errno == EINTR {
        continue
      } else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
        break
      } else {
        closed = true // o app fechou a conexão ou houve erro
        break
      }
    }

    if let messages = try? parser.nextMessages() {
      messages.forEach(handle)
    } else {
      closed = true
    }
    if closed {
      closeSocket()
    }
  }

  private func handle(_ message: Message) {
    switch message.type {
    case .settings:
      if let settings = message.settingsValue {
        onSettings?(settings)
      }
    case .stop:
      onStop?()
    case .hello, .frame:
      break
    }
  }

  private func closeSocket() {
    if let readSource {
      readSource.cancel() // o cancel handler fecha o descritor
      self.readSource = nil
    } else if socketFD >= 0 {
      close(socketFD)
    }
    socketFD = -1
    parser.reset()
    withLock { connected = false }
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
