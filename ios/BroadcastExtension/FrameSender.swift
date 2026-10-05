import Foundation

/// Cliente do socket Unix aberto pelo app principal no contêiner do App Group.
/// Reconecta sozinho caso o app ainda não esteja rodando ou seja reiniciado.
final class FrameSender {
  /// Chamado (em uma fila interna) sempre que uma nova conexão é estabelecida.
  var onConnected: (() -> Void)?
  /// Chamado (em uma fila interna) quando um envio termina e o próximo quadro pode ir.
  var onIdle: (() -> Void)?

  private let queue = DispatchQueue(label: "com.carplaymirror.sender", qos: .userInteractive)
  private var socketFD: Int32 = -1 // somente em `queue`
  private var reconnectTimer: DispatchSourceTimer? // somente em `queue`

  private let lock = NSLock()
  private var running = false
  private var connected = false
  private var busy = false

  var isConnected: Bool { withLock { connected } }
  var isBusy: Bool { withLock { busy } }

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
      let header = FrameHeader(
        payloadLength: UInt32(frame.jpeg.count),
        width: UInt32(frame.width),
        height: UInt32(frame.height)
      )
      let ok = self.socketFD >= 0 && self.writeAll(header.encoded()) && self.writeAll(frame.jpeg)
      if !ok {
        self.closeSocket()
      }
      self.withLock { self.busy = false }
      if ok {
        self.onIdle?()
      }
    }
  }

  // MARK: - Socket (queue)

  private func connectIfNeeded() {
    guard withLock({ running }), socketFD < 0,
          let path = MirrorShared.socketPath,
          let address = makeUnixSocketAddress(path: path)
    else { return }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }

    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var bufferSize: Int32 = 1 << 20
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
    // Se o app estiver suspenso, não fica bloqueado para sempre.
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    let result = withSocketAddress(address) { connect(fd, $0, $1) }
    guard result == 0 else {
      close(fd)
      return
    }

    socketFD = fd
    withLock { connected = true }
    onConnected?()
  }

  private func closeSocket() {
    if socketFD >= 0 {
      close(socketFD)
      socketFD = -1
    }
    withLock { connected = false }
  }

  private func writeAll(_ data: Data) -> Bool {
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
      guard var pointer = raw.baseAddress else { return true }
      var remaining = raw.count
      while remaining > 0 {
        let written = write(socketFD, pointer, remaining)
        if written < 0 {
          if errno == EINTR { continue }
          return false
        }
        remaining -= written
        pointer = pointer.advanced(by: written)
      }
      return true
    }
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
