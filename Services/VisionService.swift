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
    ///
    /// DISABLED (experiment, 2026-11-24): polish+save dies on Appetize
    /// whenever the day has a photo to rank, and the aesthetics request is
    /// the least battle-tested of the three Vision passes (iOS 17+, distinct
    /// model). Bypassing it to test whether it is the crash. Ranking
    /// degrades gracefully: aestheticScore nil -> neutral 0.15, and the
    /// utility penalty never applies while this is off. Re-enable (delete
    /// the early return) if the probe shows the crash is elsewhere.
    func aesthetics(for image: UIImage) async -> (score: Double, isUtility: Bool)? {
        return nil
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
