import CoreMedia
import ImageIO
import ReplayKit

/// Extensão de transmissão (ReplayKit). O iOS entrega aqui os quadros da tela inteira do
/// iPhone enquanto a transmissão estiver ativa; eles são reduzidos, comprimidos em JPEG e
/// enviados ao app principal, que os desenha na janela do CarPlay.
final class SampleHandler: RPBroadcastSampleHandler {
  private struct PendingFrame {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
  }

  private let captureQueue = DispatchQueue(label: "com.carplaymirror.capture", qos: .userInteractive)
  private let encoder = FrameEncoder()
  private let sender = FrameSender()

  // Protegidos por `stateLock` (acessados pela fila do ReplayKit e por `captureQueue`).
  private let stateLock = NSLock()
  private var pendingFrame: PendingFrame?
  private var flushQueued = false
  private var settings = MirrorSettings.load()

  // Acessados somente em `captureQueue`.
  private var lastEncodedFrame: EncodedFrame?
  private var lastSendTime: TimeInterval = 0
  private var delayedFlushScheduled = false

  private var stopObserver: DarwinNotificationObserver?
  private var settingsObserver: DarwinNotificationObserver?

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    guard MirrorShared.socketPath != nil else {
      finishBroadcastWithError(MirrorShared.error(
        "App Group não configurado. Confira MIRROR_APP_GROUP_ID em ios/Config.xcconfig."
      ))
      return
    }

    stopObserver = DarwinNotificationObserver(name: MirrorShared.Notifications.stopBroadcast) { [weak self] in
      self?.finishBroadcastWithError(MirrorShared.error("Espelhamento encerrado pelo CarPlay Mirror."))
    }
    settingsObserver = DarwinNotificationObserver(name: MirrorShared.Notifications.settingsChanged) { [weak self] in
      guard let self else { return }
      self.reloadSettings()
      // A gravação no UserDefaults pode chegar depois da notificação: relê mais uma vez.
      self.captureQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reloadSettings() }
    }

    sender.onConnected = { [weak self] in
      guard let self else { return }
      self.captureQueue.async { self.senderDidConnect() }
    }
    sender.onIdle = { [weak self] in
      guard let self else { return }
      self.captureQueue.async { self.flush() }
    }
    sender.start()
  }

  override func broadcastFinished() {
    // As notificações Darwin chegam na main thread: remove os observadores nela
    // para não destruí-los no meio de um callback.
    DispatchQueue.main.async {
      self.stopObserver = nil
      self.settingsObserver = nil
    }
    sender.stop()
  }

  private func reloadSettings() {
    let updated = MirrorSettings.load()
    stateLock.lock()
    settings = updated
    stateLock.unlock()
  }

  override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
    guard sampleBufferType == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    // Guarda só o quadro mais recente; quadros antigos são descartados sem enfileirar.
    let frame = PendingFrame(pixelBuffer: pixelBuffer, orientation: Self.orientation(of: sampleBuffer))
    stateLock.lock()
    pendingFrame = frame
    let shouldKick = !flushQueued
    flushQueued = true
    stateLock.unlock()

    if shouldKick {
      captureQueue.async { self.flush() }
    }
  }

  // MARK: - Envio (captureQueue)

  private func senderDidConnect() {
    stateLock.lock()
    let hasPending = pendingFrame != nil
    stateLock.unlock()

    // Com a tela parada o ReplayKit não gera quadros novos: reenvia o último para o carro
    // não ficar vazio após uma reconexão.
    if !hasPending, let lastEncodedFrame {
      sender.send(lastEncodedFrame)
    } else {
      flush()
    }
  }

  /// Envia o quadro pendente respeitando o limite de FPS. Se o limite ainda não permite,
  /// agenda um novo envio para que a última mudança da tela nunca se perca.
  private func flush() {
    stateLock.lock()
    flushQueued = false
    let hasPending = pendingFrame != nil
    let current = settings
    stateLock.unlock()

    guard hasPending, sender.isConnected, !sender.isBusy else { return }

    let interval = 1.0 / Double(max(current.maxFPS, 1))
    let now = ProcessInfo.processInfo.systemUptime
    let wait = lastSendTime + interval - now
    if wait > 0.001 {
      scheduleDelayedFlush(after: wait)
      return
    }

    stateLock.lock()
    let frame = pendingFrame
    pendingFrame = nil
    stateLock.unlock()

    guard let frame else { return }
    lastSendTime = now

    let encoded = autoreleasepool {
      encoder.encode(
        frame.pixelBuffer,
        orientation: frame.orientation,
        maxDimension: current.maxDimension,
        quality: current.jpegQuality
      )
    }
    guard let encoded else { return }
    lastEncodedFrame = encoded
    sender.send(encoded)
  }

  private func scheduleDelayedFlush(after delay: TimeInterval) {
    guard !delayedFlushScheduled else { return }
    delayedFlushScheduled = true
    captureQueue.asyncAfter(deadline: .now() + delay) {
      self.delayedFlushScheduled = false
      self.flush()
    }
  }

  private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
    guard
      let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil)
        as? NSNumber,
      let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value)
    else {
      return .up
    }
    return orientation
  }
}
