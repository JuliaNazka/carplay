import CarPlay
import UIKit

/// Cena do CarPlay. Como app de navegação (entitlement com.apple.developer.carplay-maps),
/// recebemos uma `CPWindow` onde podemos desenhar livremente — é nela que a tela do
/// iPhone é exibida. Os botões ficam num `CPMapTemplate` sobreposto.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?
  private var carWindow: CPWindow?
  private var mapTemplate: CPMapTemplate?
  private var settingsObserver: NSObjectProtocol?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    self.interfaceController = interfaceController
    carWindow = window
    window.rootViewController = CarPlayMirrorViewController()

    let template = CPMapTemplate()
    // Esconde a barra de botões depois de alguns segundos para liberar a tela inteira.
    template.automaticallyHidesNavigationBar = true
    template.hidesButtonsWithNavigationBar = true
    mapTemplate = template
    refreshButtons()
    interfaceController.setRootTemplate(template, animated: false, completion: nil)

    // Mantém o título do botão em sincronia quando o ajuste muda pelo iPhone.
    settingsObserver = NotificationCenter.default.addObserver(
      forName: MirrorSession.settingsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshButtons()
    }

    MirrorSession.shared.carPlayDidConnect()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    MirrorSession.shared.carPlayDidDisconnect()
    if let settingsObserver {
      NotificationCenter.default.removeObserver(settingsObserver)
    }
    settingsObserver = nil
    window.rootViewController = nil
    self.interfaceController = nil
    carWindow = nil
    mapTemplate = nil
  }

  private func refreshButtons() {
    guard let mapTemplate else { return }
    let fillTitle = MirrorSession.shared.fillMode == "fill" ? "Ajustar" : "Preencher"
    let fillButton = CPBarButton(title: fillTitle) { _ in
      MirrorSession.shared.toggleFillMode()
    }
    let stopButton = CPBarButton(title: "Parar") { _ in
      MirrorSession.shared.stopBroadcast()
    }
    mapTemplate.leadingNavigationBarButtons = [fillButton]
    mapTemplate.trailingNavigationBarButtons = [stopButton]
  }
}
