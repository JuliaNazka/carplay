import ImageIO
import ReplayKit
import UIKit

/// Quem desenha os quadros (a tela do CarPlay).
protocol MirrorRenderer: AnyObject {
  func display(frame: CGImage)
  func mirrorStateDidChange()
}

/// Estado central do espelhamento. Use somente na main thread
/// (exceto pelos callbacks internos de rede/decodificação).
/// Exposta ao Objective-C com o nome fixo `MirrorSession`: o módulo nativo (RCTScreenMirror.mm)
/// a encontra em tempo de execução. Mantenha os nomes em @objc(...) em sincronia com o .mm.
@objc(MirrorSession)
public final class MirrorSession: NSObject {
  @objc public static let shared = MirrorSession()

  /// Postada na main thread quando as preferências mudam (ex.: modo de ajuste).
  static let settingsDidChangeNotification = Notification.Name("MirrorSessionSettingsDidChange")

  weak var renderer: MirrorRenderer? {
    didSet { renderer?.mirrorStateDidChange() }
  }

  private(set) var currentFrame: CGImage?
  private(set) var isCarPlayConnected = false
  private(set) var isBroadcasting = false
  private(set) var isDemoMode = false
  private(set) var settings = MirrorSettings.load()

  private let receiver = FrameReceiver()
  private var started = false
  private var errorMessage = ""
  private var framesReceived = 0
  private var recentFrameTimes: [TimeInterval] = []
  private var lastFrameTime: TimeInterval?
  private var demoTimer: Timer?
  private var foregroundObserver: NSObjectProtocol?

  private let decodeQueue = DispatchQueue(label: "com.carplaymirror.decode", qos: .userInteractive)
  private let decodeLock = NSLock()
  private var pendingJPEG: Data? // protegido por decodeLock
  private var decodeScheduled = false // protegido por decodeLock
  private var pendingImage: CGImage? // protegido por decodeLock
  private var presentScheduled = false // protegido por decodeLock

  private lazy var broadcastPicker: RPSystemBroadcastPickerView = {
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: -200, y: -200, width: 44, height: 44))
    picker.preferredExtension = Self.broadcastExtensionIdentifier()
    picker.showsMicrophoneButton = false
    return picker
  }()

  override private init() {
    super.init()
  }

  // MARK: - Ciclo de vida

  /// Chamado no launch do app (inclusive quando o iOS abre o app só para o CarPlay).
  func start() {
    guard !started else { return }
    started = true

    receiver.onConnectionChange = { [weak self] connected in
      DispatchQueue.main.async { self?.broadcastConnectionChanged(connected) }
    }
    receiver.onFrame = { [weak self] jpeg in
      self?.enqueueDecode(jpeg)
    }
    receiver.start(settings: settings) { [weak self] error in
      DispatchQueue.main.async { self?.errorMessage = error ?? "" }
    }

    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIScene.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.receiver.restartIfIdle { error in
        DispatchQueue.main.async { self?.errorMessage = error ?? "" }
      }
    }
  }

  func carPlayDidConnect() {
    isCarPlayConnected = true
  }

  func carPlayDidDisconnect() {
    isCarPlayConnected = false
  }

  var fillMode: String { settings.fillMode }

  // MARK: - API usada pelo React Native

  @objc(statusDictionary)
  public func statusDictionary() -> [String: Any] {
    let now = ProcessInfo.processInfo.systemUptime
    recentFrameTimes.removeAll { now - $0 > 1 }
    return [
      "carPlayConnected": isCarPlayConnected,
      "broadcasting": isBroadcasting,
      "demoMode": isDemoMode,
      "fps": recentFrameTimes.count,
      "frameWidth": currentFrame?.width ?? 0,
      "frameHeight": currentFrame?.height ?? 0,
      "framesReceived": framesReceived,
      "lastFrameAgeMs": lastFrameTime.map { Int((now - $0) * 1000) } ?? -1,
      "maxFps": settings.maxFPS,
      "jpegQuality": settings.jpegQuality,
      "maxDimension": settings.maxDimension,
      "fillMode": settings.fillMode,
      "error": errorMessage,
    ]
  }

  /// Abre o seletor do sistema "Transmitir tela" já apontando para a nossa extensão.
  @objc(showBroadcastPicker)
  public func showBroadcastPicker() {
    guard let window = phoneWindow() else { return }
    let picker = broadcastPicker
    if picker.superview !== window {
      window.addSubview(picker)
    }
    // Não há API pública para iniciar a transmissão; tocar no botão interno do seletor é o caminho usual.
    Self.findButton(in: picker)?.sendActions(for: .allEvents)
  }

  /// Pede para a extensão encerrar a transmissão.
  @objc(stopBroadcast)
  public func stopBroadcast() {
    receiver.sendStop()
  }

  @objc(updateSettingsWithMaxFPS:jpegQuality:maxDimension:fillMode:)
  public func updateSettings(maxFPS: Int, jpegQuality: Double, maxDimension: Int, fillMode: String) {
    let updated = MirrorSettings(
      maxFPS: maxFPS,
      jpegQuality: jpegQuality,
      maxDimension: maxDimension,
      fillMode: fillMode
    ).clamped()
    guard updated != settings else { return }
    settings = updated
    settings.save()
    receiver.send(settings: updated)
    NotificationCenter.default.post(name: Self.settingsDidChangeNotification, object: self)
    renderer?.mirrorStateDidChange()
  }

  func toggleFillMode() {
    updateSettings(
      maxFPS: settings.maxFPS,
      jpegQuality: settings.jpegQuality,
      maxDimension: settings.maxDimension,
      fillMode: settings.fillMode == "fill" ? "fit" : "fill"
    )
  }

  /// Modo demonstração: espelha a própria tela do app no CarPlay. Serve para testar a
  /// parte do CarPlay no Simulador, onde a extensão de transmissão não funciona.
  @objc(setDemoModeEnabled:)
  public func setDemoMode(_ enabled: Bool) {
    guard enabled != isDemoMode else { return }
    isDemoMode = enabled
    demoTimer?.invalidate()
    demoTimer = nil
    if enabled {
      let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
        self?.captureDemoFrame()
      }
      // Modo .common: continua capturando enquanto o usuário rola a tela.
      RunLoop.main.add(timer, forMode: .common)
      demoTimer = timer
    } else if !isBroadcasting {
      clearFrame()
    }
    renderer?.mirrorStateDidChange()
  }

  // MARK: - Quadros

  private func broadcastConnectionChanged(_ connected: Bool) {
    isBroadcasting = connected
    if !connected && !isDemoMode {
      clearFrame()
    }
    renderer?.mirrorStateDidChange()
  }

  /// Decodifica sempre o JPEG mais recente; se chegar outro durante a decodificação, o
  /// intermediário é descartado (mas o último nunca se perde).
  private func enqueueDecode(_ jpeg: Data) {
    decodeLock.lock()
    pendingJPEG = jpeg
    let shouldStart = !decodeScheduled
    decodeScheduled = true
    decodeLock.unlock()

    guard shouldStart else { return }
    decodeQueue.async { [weak self] in self?.decodeLoop() }
  }

  private func decodeLoop() {
    while true {
      decodeLock.lock()
      guard let jpeg = pendingJPEG else {
        decodeScheduled = false
        decodeLock.unlock()
        return
      }
      pendingJPEG = nil
      decodeLock.unlock()

      guard let image = Self.decodeJPEG(jpeg) else { continue }
      schedulePresent(image)
    }
  }

  /// Entrega à main thread só a imagem decodificada mais recente. Se a main thread estiver
  /// ocupada, as imagens intermediárias são descartadas em vez de se acumularem na fila.
  private func schedulePresent(_ image: CGImage) {
    decodeLock.lock()
    pendingImage = image
    let shouldSchedule = !presentScheduled
    presentScheduled = true
    decodeLock.unlock()

    guard shouldSchedule else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.decodeLock.lock()
      let image = self.pendingImage
      self.pendingImage = nil
      self.presentScheduled = false
      self.decodeLock.unlock()

      guard let image, self.isBroadcasting else { return }
      self.present(frame: image)
    }
  }

  private static func decodeJPEG(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
    return CGImageSourceCreateImageAtIndex(source, 0, options)
  }

  private func present(frame: CGImage) {
    let now = ProcessInfo.processInfo.systemUptime
    currentFrame = frame
    framesReceived += 1
    lastFrameTime = now
    recentFrameTimes.append(now)
    recentFrameTimes.removeAll { now - $0 > 1 }
    renderer?.display(frame: frame)
  }

  private func clearFrame() {
    currentFrame = nil
    lastFrameTime = nil
    recentFrameTimes.removeAll()
  }

  private func captureDemoFrame() {
    guard !isBroadcasting, let window = phoneWindow(), window.bounds.width > 0 else { return }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    format.opaque = true
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
    }
    if let frame = image.cgImage {
      present(frame: frame)
    }
  }

  // MARK: - Utilidades

  private func phoneWindow() -> UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.session.role == .windowApplication }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first
  }

  /// Bundle ID da extensão embutida, lido em tempo de execução (ferramentas como o
  /// Sideloadly podem trocar os bundle IDs ao reassinar o app).
  private static func broadcastExtensionIdentifier() -> String? {
    guard
      let pluginsURL = Bundle.main.builtInPlugInsURL,
      let items = try? FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil)
    else { return nil }

    for item in items where item.pathExtension == "appex" {
      guard
        let bundle = Bundle(url: item),
        let info = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
        info["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload"
      else { continue }
      return bundle.bundleIdentifier
    }
    return nil
  }

  private static func findButton(in view: UIView) -> UIButton? {
    if let button = view as? UIButton { return button }
    for subview in view.subviews {
      if let button = findButton(in: subview) { return button }
    }
    return nil
  }
}
