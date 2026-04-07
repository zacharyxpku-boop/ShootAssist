import Vision

// MARK: - Shared Pose Types
// Single source of truth for types shared across VisionService, PoseCompletionService, PoseMatchingService

/// Source of a detected/inferred joint point
enum JointSource { case detected, interpolated, lastKnown }

/// All joint names tracked by the pose pipeline
let allPoseJointNames: [VNHumanBodyPoseObservation.JointName] = [
    .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
    .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee,
    .leftAnkle, .rightAnkle, .root
]
