import SwiftUI
import Vision

// MARK: - CompletedPose
struct CompletedPose {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let jointSources: [VNHumanBodyPoseObservation.JointName: JointSource]
    let observedCount: Int
    let inferredCount: Int
    let completenessScore: Float   // 0..1, based on key anchor coverage
    let canUseForMatching: Bool     // true if torso anchors + enough joints exist
    let reliabilityNote: String?    // nil if fine, else human-readable warning
}

// MARK: - PoseCompletionService
class PoseCompletionService {
    // Torso anchors = shoulders + hips + neck/root. Need at least 3 of 6 to be reliable.
    static let torsosAnchors: [VNHumanBodyPoseObservation.JointName] = [
        .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .root
    ]

    // MARK: - Main completion method
    func complete(
        _ rawJoints: [VNHumanBodyPoseObservation.JointName: CGPoint],
        boundingBox: CGRect?,
        lastKnownJoints: [VNHumanBodyPoseObservation.JointName: CGPoint],
        frameCount: Int,
        jointLastSeenFrame: [VNHumanBodyPoseObservation.JointName: Int],
        maxMissingFrames: Int
    ) -> CompletedPose {
        // Step 1: Merge with Last Known Joints (preserves for up to maxMissingFrames)
        var merged = rawJoints
        
        // Merge raw joints into result (rawJoints always wins)
        merged = rawJoints
        
        // Fill missing joints with last known if within tolerance
        for joint in allPoseJointNames {
            if merged[joint] == nil {
                if let lastPt = lastKnownJoints[joint],
                   let lastFrame = jointLastSeenFrame[joint],
                   frameCount - lastFrame <= maxMissingFrames {
                    merged[joint] = lastPt
                }
            }
        }
        
        // Step 2: Interpolate Missing Joints using kinematic chain
        let interpolatedJoints = interpolateMissingJoints(merged, boundingBox: boundingBox)
        
        // Step 3: Build Joint Sources mapping
        let sources = buildJointSources(raw: rawJoints, merged: merged, interpolated: interpolatedJoints)
        
        // Count observed vs inferred
        let observedCount = rawJoints.count
        let inferredCount = interpolatedJoints.count - observedCount
        
        // Compute completeness score: (observed torso anchors / 6) * 0.6 + (total observed / 15) * 0.4
        let torsoAnchorObserved = Self.torsosAnchors.filter { rawJoints[$0] != nil }.count
        let torsoAnchorFraction = CGFloat(torsoAnchorObserved) / 6.0
        let totalObservedFraction = CGFloat(observedCount) / 15.0
        let completenessScore = Float(torsoAnchorFraction * 0.6 + totalObservedFraction * 0.4)
        
        // Determine canUseForMatching: needs ≥ 0.35 score AND at least one shoulder pair
        // Accept shoulders from detection OR interpolation (neck+hip fallback)
        let hasShoulderPair = interpolatedJoints[.leftShoulder] != nil && interpolatedJoints[.rightShoulder] != nil
        let canUseForMatching = completenessScore >= 0.35 && hasShoulderPair
        
        // Build reliability note
        var reliabilityNote: String?
        if rawJoints[.leftShoulder] == nil && rawJoints[.rightShoulder] == nil {
            reliabilityNote = "未检测到肩部，骨架可靠性低"
        } else if observedCount < 4 {
            reliabilityNote = "关键点过少，补全仅供参考"
        }
        
        return CompletedPose(
            joints: interpolatedJoints,
            jointSources: sources,
            observedCount: observedCount,
            inferredCount: inferredCount,
            completenessScore: completenessScore,
            canUseForMatching: canUseForMatching,
            reliabilityNote: reliabilityNote
        )
    }

    // MARK: - Interpolate Missing Joints using kinematic chain
    func interpolateMissingJoints(
        _ joints: [VNHumanBodyPoseObservation.JointName: CGPoint],
        boundingBox personBox: CGRect?
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var result = joints
        
        // Helper to get joint or fallback to placeholder
        func get(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            return joints[joint]
        }
        
        // Helper to set joint only if missing
        func setIfMissing(_ joint: VNHumanBodyPoseObservation.JointName, _ pt: CGPoint) {
            if result[joint] == nil {
                result[joint] = pt
            }
        }
        
        // --- Shoulder estimation from neck + hips ---
        if result[.leftShoulder] == nil || result[.rightShoulder] == nil {
            if let neck = get(.neck) {
                // Estimate shoulder spread from hip width or default 0.15
                let spread: CGFloat
                if let leftHip = get(.leftHip), let rightHip = get(.rightHip) {
                    spread = abs(rightHip.x - leftHip.x) * 0.65 // shoulders ~65% of hip width on each side
                } else {
                    spread = 0.15
                }
                if result[.leftShoulder] == nil {
                    setIfMissing(.leftShoulder, CGPoint(x: neck.x - spread, y: neck.y))
                }
                if result[.rightShoulder] == nil {
                    setIfMissing(.rightShoulder, CGPoint(x: neck.x + spread, y: neck.y))
                }
            }
        }

        // --- Root estimation ---
        if result[.root] == nil {
            if let leftShoulder = get(.leftShoulder),
               let rightShoulder = get(.rightShoulder),
               let leftHip = get(.leftHip),
               let rightHip = get(.rightHip) {
                // Use midpoint of shoulders and hips
                let shoulderMid = CGPoint(x: (leftShoulder.x + rightShoulder.x) / 2,
                                          y: (leftShoulder.y + rightShoulder.y) / 2)
                let hipMid = CGPoint(x: (leftHip.x + rightHip.x) / 2,
                                     y: (leftHip.y + rightHip.y) / 2)
                let rootEstimate = CGPoint(x: (shoulderMid.x + hipMid.x) / 2,
                                           y: (shoulderMid.y + hipMid.y) / 2)
                setIfMissing(.root, rootEstimate)
            } else if let leftShoulder = get(.leftShoulder),
                      let rightShoulder = get(.rightShoulder) {
                // Shoulder width as proxy
                let shoulderWidth = abs(rightShoulder.x - leftShoulder.x)
                let torsoHeight = shoulderWidth * 1.3
                let shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2
                let rootY = shoulderMidY - torsoHeight
                let rootX = (leftShoulder.x + rightShoulder.x) / 2
                setIfMissing(.root, CGPoint(x: rootX, y: rootY))
            }
        }
        
        // --- Hip estimation ---
        if result[.leftHip] == nil || result[.rightHip] == nil {
            if let leftShoulder = get(.leftShoulder),
               let rightShoulder = get(.rightShoulder),
               let root = get(.root) {
                let shoulderWidth = abs(rightShoulder.x - leftShoulder.x)
                let torsoHeight = shoulderWidth * 1.3
                let shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2
                let shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2
                let hipY = shoulderMidY - torsoHeight
                
                if result[.leftHip] == nil {
                    setIfMissing(.leftHip, CGPoint(x: shoulderMidX - shoulderWidth/2, y: hipY))
                }
                if result[.rightHip] == nil {
                    setIfMissing(.rightHip, CGPoint(x: shoulderMidX + shoulderWidth/2, y: hipY))
                }
            }
        }
        
        // --- Knee estimation ---
        if result[.leftKnee] == nil || result[.rightKnee] == nil {
            if let leftHip = get(.leftHip),
               let rightHip = get(.rightHip) {
                let hipWidth = abs(rightHip.x - leftHip.x)
                let thighLength = hipWidth * 1.15
                let leftHipY = leftHip.y
                let rightHipY = rightHip.y
                
                if result[.leftKnee] == nil {
                    setIfMissing(.leftKnee, CGPoint(x: leftHip.x, y: leftHipY - thighLength))
                }
                if result[.rightKnee] == nil {
                    setIfMissing(.rightKnee, CGPoint(x: rightHip.x, y: rightHipY - thighLength))
                }
            }
        }
        
        // --- Ankle estimation ---
        if result[.leftAnkle] == nil || result[.rightAnkle] == nil {
            if let leftKnee = get(.leftKnee),
               let rightKnee = get(.rightKnee) {
                let kneeWidth = abs(rightKnee.x - leftKnee.x)
                let shinLength = kneeWidth * 0.95
                let leftKneeY = leftKnee.y
                let rightKneeY = rightKnee.y
                
                if result[.leftAnkle] == nil {
                    setIfMissing(.leftAnkle, CGPoint(x: leftKnee.x, y: leftKneeY - shinLength))
                }
                if result[.rightAnkle] == nil {
                    setIfMissing(.rightAnkle, CGPoint(x: rightKnee.x, y: rightKneeY - shinLength))
                }
            }
        }
        
        // --- Final ankle fallback: use bounding box bottom anchor ---
        if result[.leftAnkle] == nil || result[.rightAnkle] == nil {
            guard let personBox else {
                // No bbox fallback: use knee/hip Y
                if result[.leftAnkle] == nil {
                    if let leftKnee = get(.leftKnee) {
                        setIfMissing(.leftAnkle, CGPoint(x: leftKnee.x, y: leftKnee.y - 0.1))
                    } else if let leftHip = get(.leftHip) {
                        setIfMissing(.leftAnkle, CGPoint(x: leftHip.x, y: leftHip.y - 0.15))
                    }
                }
                if result[.rightAnkle] == nil {
                    if let rightKnee = get(.rightKnee) {
                        setIfMissing(.rightAnkle, CGPoint(x: rightKnee.x, y: rightKnee.y - 0.1))
                    } else if let rightHip = get(.rightHip) {
                        setIfMissing(.rightAnkle, CGPoint(x: rightHip.x, y: rightHip.y - 0.15))
                    }
                }
                return result
            }
            
            let ankleYAnchor = personBox.minY + 0.02
            if result[.leftAnkle] == nil {
                if let leftKnee = get(.leftKnee) {
                    setIfMissing(.leftAnkle, CGPoint(x: leftKnee.x, y: ankleYAnchor))
                } else if let leftHip = get(.leftHip) {
                    setIfMissing(.leftAnkle, CGPoint(x: leftHip.x, y: ankleYAnchor))
                }
            }
            if result[.rightAnkle] == nil {
                if let rightKnee = get(.rightKnee) {
                    setIfMissing(.rightAnkle, CGPoint(x: rightKnee.x, y: ankleYAnchor))
                } else if let rightHip = get(.rightHip) {
                    setIfMissing(.rightAnkle, CGPoint(x: rightHip.x, y: ankleYAnchor))
                }
            }
        }
        
        return result
    }

    // MARK: - Build Joint Sources mapping
    func buildJointSources(
        raw: [VNHumanBodyPoseObservation.JointName: CGPoint],
        merged: [VNHumanBodyPoseObservation.JointName: CGPoint],
        interpolated: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> [VNHumanBodyPoseObservation.JointName: JointSource] {
        var sources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:]
        
        for joint in allPoseJointNames {
            if raw[joint] != nil {
                sources[joint] = .detected
            } else if merged[joint] != nil && interpolated[joint] == merged[joint] {
                sources[joint] = .lastKnown
            } else if interpolated[joint] != nil {
                sources[joint] = .interpolated
            }
        }
        
        return sources
    }
}
