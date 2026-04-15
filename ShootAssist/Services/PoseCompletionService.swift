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
        // 降到 0.2：只要有头+一个肩膀的半身照也能用
        let canUseForMatching = completenessScore >= 0.20 && hasShoulderPair
        
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
                    spread = abs(rightHip.x - leftHip.x) * 0.50 // shoulders ~50% of hip width per side (total ≈ hip width)
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

        // --- Elbow estimation from shoulder + wrist, or default hanging position ---
        if result[.leftElbow] == nil {
            if let ls = result[.leftShoulder], let lw = result[.leftWrist] {
                setIfMissing(.leftElbow, CGPoint(x: (ls.x + lw.x) / 2, y: (ls.y + lw.y) / 2))
            } else if let ls = result[.leftShoulder] {
                // Default: arm hanging at 45 degrees
                let armLen: CGFloat = 0.08
                setIfMissing(.leftElbow, CGPoint(x: ls.x - armLen * 0.5, y: ls.y - armLen))
            }
        }
        if result[.rightElbow] == nil {
            if let rs = result[.rightShoulder], let rw = result[.rightWrist] {
                setIfMissing(.rightElbow, CGPoint(x: (rs.x + rw.x) / 2, y: (rs.y + rw.y) / 2))
            } else if let rs = result[.rightShoulder] {
                let armLen: CGFloat = 0.08
                setIfMissing(.rightElbow, CGPoint(x: rs.x + armLen * 0.5, y: rs.y - armLen))
            }
        }

        // --- Wrist estimation from shoulder + elbow extrapolation ---
        if result[.leftWrist] == nil {
            if let ls = result[.leftShoulder], let le = result[.leftElbow] {
                // Extrapolate: wrist = elbow + (elbow - shoulder) * 0.9
                let dx = le.x - ls.x
                let dy = le.y - ls.y
                setIfMissing(.leftWrist, CGPoint(x: le.x + dx * 0.9, y: le.y + dy * 0.9))
            }
        }
        if result[.rightWrist] == nil {
            if let rs = result[.rightShoulder], let re = result[.rightElbow] {
                let dx = re.x - rs.x
                let dy = re.y - rs.y
                setIfMissing(.rightWrist, CGPoint(x: re.x + dx * 0.9, y: re.y + dy * 0.9))
            }
        }

        // --- Neck estimation from shoulders or nose ---
        if result[.neck] == nil {
            if let ls = result[.leftShoulder], let rs = result[.rightShoulder] {
                setIfMissing(.neck, CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2 + 0.03))
            } else if let nose = result[.nose], let ls = result[.leftShoulder] {
                setIfMissing(.neck, CGPoint(x: (nose.x + ls.x) / 2, y: (nose.y + ls.y) / 2))
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
                let torsoHeight = shoulderWidth * 1.5
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
                let torsoHeight = shoulderWidth * 1.5
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
        
        // --- Knee estimation (anatomically correct) ---
        // 用肩宽做基准：大腿长 ≈ 1.8× 肩宽（达芬奇人体比例）
        // 旧代码用 hipWidth × 1.15 = 约 0.9× 肩宽，导致腿短如侏儒
        if result[.leftKnee] == nil || result[.rightKnee] == nil {
            // 肩宽优先（最准）；无肩宽回退到 hipWidth × 2.3 近似还原肩宽
            let thighLength: CGFloat
            if let ls = result[.leftShoulder], let rs = result[.rightShoulder] {
                thighLength = abs(rs.x - ls.x) * 1.8
            } else if let lh = result[.leftHip], let rh = result[.rightHip] {
                thighLength = abs(rh.x - lh.x) * 2.3
            } else {
                thighLength = 0.22  // 归一化兜底值
            }

            if let leftHip = get(.leftHip), result[.leftKnee] == nil {
                setIfMissing(.leftKnee, CGPoint(x: leftHip.x, y: leftHip.y - thighLength))
            }
            if let rightHip = get(.rightHip), result[.rightKnee] == nil {
                setIfMissing(.rightKnee, CGPoint(x: rightHip.x, y: rightHip.y - thighLength))
            }
        }

        // --- Ankle estimation (anatomically correct) ---
        // 小腿长 ≈ 1.6× 肩宽，略短于大腿
        if result[.leftAnkle] == nil || result[.rightAnkle] == nil {
            let shinLength: CGFloat
            if let ls = result[.leftShoulder], let rs = result[.rightShoulder] {
                shinLength = abs(rs.x - ls.x) * 1.6
            } else if let lh = result[.leftHip], let rh = result[.rightHip] {
                shinLength = abs(rh.x - lh.x) * 2.0
            } else {
                shinLength = 0.20
            }

            if let leftKnee = get(.leftKnee), result[.leftAnkle] == nil {
                setIfMissing(.leftAnkle, CGPoint(x: leftKnee.x, y: leftKnee.y - shinLength))
            }
            if let rightKnee = get(.rightKnee), result[.rightAnkle] == nil {
                setIfMissing(.rightAnkle, CGPoint(x: rightKnee.x, y: rightKnee.y - shinLength))
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
