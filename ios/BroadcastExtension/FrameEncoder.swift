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
  private let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
  private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

  func encode(
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    maxDimension: Int,
    quality: Double
  ) -> EncodedFrame? {
    // Coloca a imagem "em pé" (o iPhone em paisagem entrega o buffer rotacionado).
    var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)

    let longestSide = max(image.extent.width, image.extent.height)
    if longestSide > CGFloat(maxDimension), longestSide > 0 {
      let scale = CGFloat(maxDimension) / longestSide
      image = image.applyingFilter(
        "CILanczosScaleTransform",
        parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
      )
    }

    // Normaliza a origem para (0, 0) e descarta frações de pixel.
    let extent = image.extent
    let rect = CGRect(x: extent.minX, y: extent.minY, width: extent.width.rounded(.down), height: extent.height.rounded(.down))
    guard rect.width >= 1, rect.height >= 1 else { return nil }
    image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))

    let options: [CIImageRepresentationOption: Any] = [
      CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality,
    ]
    guard let jpeg = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options) else {
      return nil
    }
    return EncodedFrame(jpeg: jpeg, width: Int(rect.width), height: Int(rect.height))
  }
}
