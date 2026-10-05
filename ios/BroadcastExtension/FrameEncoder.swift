import CoreImage
import CoreVideo
import ImageIO

struct EncodedFrame {
  let jpeg: Data
  let width: Int
  let height: Int
}

/// Rotaciona, reduz e comprime em JPEG os quadros capturados (via GPU com Core Image).
final class FrameEncoder {
  private let gpuContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
  // Usado só se a GPU recusar o trabalho (ex.: restrições do sistema à extensão).
  private lazy var softwareContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
  private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

  func encode(
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    maxDimension: Int,
    quality: Double
  ) -> EncodedFrame? {
    // Coloca a imagem "em pé" (o iPhone em paisagem entrega o buffer rotacionado).
    var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
    image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

    let longestSide = max(image.extent.width, image.extent.height)
    guard longestSide > 0 else { return nil }
    let scale = min(1, CGFloat(maxDimension) / longestSide)
    let width = (image.extent.width * scale).rounded(.down)
    let height = (image.extent.height * scale).rounded(.down)
    guard width >= 1, height >= 1 else { return nil }

    if scale < 1 {
      // clampedToExtent evita bordas semitransparentes (que viram uma linha escura no JPEG).
      image = image.clampedToExtent().applyingFilter(
        "CILanczosScaleTransform",
        parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
      )
    }
    image = image.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

    let options: [CIImageRepresentationOption: Any] = [
      CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality,
    ]
    guard
      let jpeg = gpuContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
        ?? softwareContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
    else {
      return nil
    }
    return EncodedFrame(jpeg: jpeg, width: Int(width), height: Int(height))
  }
}
