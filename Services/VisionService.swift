import Vision
import UIKit

/// On-device Vision analysis. Everything here is a built-in framework:
/// no model download, no network, no cost.
actor VisionService {
    func labels(for image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNClassifyImageRequest { req, _ in
                // 0.05 admitted near-noise labels ("building" at 0.06
                // tagged everything); 0.2 keeps only labels Vision
                // actually believes.
                let results = (req.results as? [VNClassificationObservation])?
                    .filter { $0.confidence > 0.2 }
                    .prefix(8).map { $0.identifier } ?? []
                cont.resume(returning: results)
            }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([req]) } catch { Log.event("Vision", "labels failed: \(error.localizedDescription)"); cont.resume(returning: []) }
        }
    }

    /// Aesthetic quality in -1...1 plus whether Vision classifies the image
    /// as utility (screenshot / receipt / document). Used for ranking.
    func aesthetics(for image: UIImage) async -> (score: Double, isUtility: Bool)? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { cont in
            let req = VNCalculateImageAestheticsScoresRequest { req, _ in
                guard let obs = (req.results as? [VNImageAestheticsScoresObservation])?.first else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: (Double(obs.overallScore), obs.isUtility))
            }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([req]) } catch { Log.event("Vision", "aesthetics failed: \(error.localizedDescription)"); cont.resume(returning: nil) }
        }
    }

    func faceCount(for image: UIImage) async -> Int {
        guard let cg = image.cgImage else { return 0 }
        return await withCheckedContinuation { cont in
            let req = VNDetectFaceRectanglesRequest { req, _ in
                cont.resume(returning: req.results?.count ?? 0)
            }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([req]) } catch { Log.event("Vision", "faces failed: \(error.localizedDescription)"); cont.resume(returning: 0) }
        }
    }

    /// All features PhotoRanker needs, in one pass over one thumbnail.
    func features(for image: UIImage, isFavorite: Bool, isVideo: Bool) async -> PhotoFeatures {
        async let labels = labels(for: image)
        async let aes = aesthetics(for: image)
        async let faces = faceCount(for: image)
        let a = await aes
        let f = PhotoFeatures(labels: await labels,
                              aestheticScore: a?.score,
                              isUtility: a?.isUtility ?? false,
                              faceCount: await faces,
                              isFavorite: isFavorite,
                              isVideo: isVideo)
        // All three Vision passes failing at once used to be silent — a
        // photo ranked on nothing. One log line makes it visible.
        if f.labels.isEmpty && f.aestheticScore == nil && f.faceCount == 0 {
            Log.event("Vision", "all three feature passes failed for a thumbnail (labels, aesthetics, faces empty)")
        }
        return f
    }
}
