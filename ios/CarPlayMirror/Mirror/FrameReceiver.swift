import Foundation

/// Servidor TCP em 127.0.0.1 que recebe os quadros JPEG da extensão de transmissão e
/// envia a ela as preferências e o pedido de parada. Só aceita conexões que provem
/// conhecer o token da instalação (veja `MirrorShared.sessionToken`).
final class FrameReceiver {
  /// Chamado na fila interna com o JPEG mais recente de cada leitura.
  var onFrame: ((Data) -> Void)?
  /// Chamado na fila interna quando a extensão conecta/desconecta.
  var onConnectionChange: ((Bool) -> Void)?

  private final class Client {
    let fd: Int32
    let source: DispatchSourceRead
    var parser = MessageParser()
    var authenticated = false

    init(fd: Int32, source: DispatchSourceRead) {
      self.fd = fd
      self.source = source
    }
  }

  private let queue = DispatchQueue(label: "com.carplaymirror.receiver", qos: .userInteractive)
  private let chunkSize = 256 * 1024
  private let chunk: UnsafeMutablePointer<UInt8>

  // Acessados somente em `queue`.
  private var acceptSource: DispatchSourceRead?
  private var listenFD: Int32 = -1
  private var active: Client?
  private var pending: [Client] = []
  private var settings = MirrorSettings.standard

  init() {
    chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
  }

  deinit {
    chunk.deallocate()
  }

  /// Abre o socket de escuta. `completion` recebe uma mensagem de erro ou nil.
  func start(settings: MirrorSettings, completion: @escaping (String?) -> Void) {
    queue.async {
      self.settings = settings
      completion(self.openListener())
    }
  }

  /// Recria o socket de escuta se nenhuma extensão estiver conectada
  /// (o iOS pode invalidar sockets de apps que ficaram suspensos).
  func restartIfIdle(completion: @escaping (String?) -> Void) {
    queue.async {
      guard self.active == nil else { return completion(nil) }
      self.closeListener()
      completion(self.openListener())
    }
  }

  func send(settings: MirrorSettings) {
    queue.async {
      self.settings = settings
      if let active = self.active {
        self.write(Message.settings(settings), to: active)
      }
    }
  }

  func sendStop() {
    queue.async {
      if let active = self.active {
        self.write(Message.stop, to: active)
      }
    }
  }

  // MARK: - Escuta (queue)

  private func openListener() -> String? {
    guard listenFD < 0 else { return nil }

    let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    guard fd >= 0 else { return "socket() falhou: \(LoopbackSocket.lastError())" }
    LoopbackSocket.setOption(fd, SOL_SOCKET, SO_REUSEADDR, 1)

    guard LoopbackSocket.withAddress(port: MirrorShared.port, { bind(fd, $0, $1) }) == 0 else {
      let message = "Não foi possível usar a porta \(MirrorShared.port): \(LoopbackSocket.lastError())"
      close(fd)
      return message
    }
    guard listen(fd, 4) == 0 else {
      let message = "listen() falhou: \(LoopbackSocket.lastError())"
      close(fd)
      return message
    }
    LoopbackSocket.setNonBlocking(fd)

    listenFD = fd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.acceptClients() }
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

  private func acceptClients() {
    while true {
      let fd = accept(listenFD, nil, nil)
      guard fd >= 0 else { return }

      // Poucos handshakes simultâneos bastam; o resto é recusado.
      guard pending.count < 4 else {
        close(fd)
        continue
      }
      LoopbackSocket.setOption(fd, SOL_SOCKET, SO_NOSIGPIPE, 1)
      LoopbackSocket.setOption(fd, IPPROTO_TCP, TCP_NODELAY, 1)
      LoopbackSocket.setOption(fd, SOL_SOCKET, SO_RCVBUF, 1 << 20)
      LoopbackSocket.setNonBlocking(fd)

      let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
      let client = Client(fd: fd, source: source)
      source.setEventHandler { [weak self, weak client] in
        guard let self, let client else { return }
        self.readAvailable(from: client)
      }
      source.setCancelHandler { close(fd) }
      source.resume()
      pending.append(client)

      // Quem não completar o handshake em 5 s é desconectado.
      queue.asyncAfter(deadline: .now() + 5) { [weak self, weak client] in
        guard let self, let client, !client.authenticated else { return }
        self.disconnect(client)
      }
    }
  }

  private func disconnect(_ client: Client) {
    client.source.cancel() // o cancel handler fecha o descritor
    pending.removeAll { $0 === client }
    if active === client {
      active = nil
      onConnectionChange?(false)
    }
  }

  private func write(_ message: Message, to client: Client) {
    if !LoopbackSocket.writeAll(client.fd, message.encoded(), timeoutMs: 500) {
      disconnect(client)
    }
  }

  // MARK: - Leitura (queue)

  private func readAvailable(from client: Client) {
    var closed = false
    while true {
      let count = read(client.fd, chunk, chunkSize)
      if count > 0 {
        client.parser.append(chunk, count: count)
      } else if count < 0 && errno == EINTR {
        continue
      } else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
        break
      } else {
        closed = true // a extensão encerrou ou houve erro
        break
      }
    }

    // Processa o que já chegou completo antes de tratar o fechamento.
    guard let messages = try? client.parser.nextMessages() else {
      disconnect(client) // fluxo corrompido
      return
    }

    var latestJPEG: Data?
    for message in messages {
      guard !client.source.isCancelled else { return }
      if !client.authenticated {
        guard message.isValidHello else {
          disconnect(client)
          return
        }
        authenticate(client)
      } else if let jpeg = message.frameJPEG {
        latestJPEG = jpeg
      }
    }

    // Se vários quadros chegaram juntos, só o mais novo interessa.
    if let latestJPEG {
      onFrame?(latestJPEG)
    }
    if closed || (!client.authenticated && client.parser.bufferedCount > 1024) {
      disconnect(client)
    }
  }

  private func authenticate(_ client: Client) {
    client.authenticated = true
    pending.removeAll { $0 === client }

    // Só existe uma transmissão por vez: a conexão autenticada mais nova substitui a anterior.
    if let previous = active {
      active = nil
      previous.source.cancel()
    }
    active = client

    write(Message.hello(), to: client)
    write(Message.settings(settings), to: client)
    if active === client {
      onConnectionChange?(true)
    }
  }
}
