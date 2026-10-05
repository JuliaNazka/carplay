import UIKit

/// Conteúdo da janela do CarPlay: o último quadro recebido do iPhone, ou uma
/// mensagem explicando como iniciar quando ainda não há transmissão.
final class CarPlayMirrorViewController: UIViewController, MirrorRenderer {
  private let frameView = UIView()
  private let placeholder = UIStackView()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    frameView.frame = view.bounds
    frameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    frameView.clipsToBounds = true
    frameView.layer.magnificationFilter = .linear
    frameView.layer.minificationFilter = .linear
    view.addSubview(frameView)

    setUpPlaceholder()

    MirrorSession.shared.renderer = self
    if let frame = MirrorSession.shared.currentFrame {
      display(frame: frame)
    }
  }

  // MARK: - MirrorRenderer

  func display(frame: CGImage) {
    CATransaction.begin()
    CATransaction.setDisableActions(true) // sem animação implícita entre quadros
    frameView.layer.contents = frame
    CATransaction.commit()
    placeholder.isHidden = true
  }

  func mirrorStateDidChange() {
    let session = MirrorSession.shared
    frameView.layer.contentsGravity = session.fillMode == "fill" ? .resizeAspectFill : .resizeAspect
    if session.currentFrame == nil {
      frameView.layer.contents = nil
      placeholder.isHidden = false
    }
  }

  // MARK: - Layout

  private func setUpPlaceholder() {
    let icon = UIImageView(image: UIImage(systemName: "iphone.and.arrow.forward"))
    icon.tintColor = .white
    icon.contentMode = .scaleAspectFit
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)

    let title = UILabel()
    title.text = "Aguardando o iPhone"
    title.textColor = .white
    title.font = .preferredFont(forTextStyle: .title2)

    let subtitle = UILabel()
    subtitle.text = "No iPhone, abra o CarPlay Mirror e toque em “Iniciar espelhamento”."
    subtitle.textColor = UIColor(white: 1, alpha: 0.7)
    subtitle.font = .preferredFont(forTextStyle: .body)
    subtitle.numberOfLines = 0
    subtitle.textAlignment = .center

    placeholder.axis = .vertical
    placeholder.alignment = .center
    placeholder.spacing = 12
    [icon, title, subtitle].forEach(placeholder.addArrangedSubview)
    placeholder.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(placeholder)

    NSLayoutConstraint.activate([
      placeholder.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
      placeholder.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -48),
    ])
  }
}
