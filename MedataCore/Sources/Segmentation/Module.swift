// Segmentation module — Core ML wrapper, pre/post-processing, ownership inputs
// (design §3.5 / §6.5). The public surface is split across:
//
//   ClassPalette.swift       — palette type + Pb* bridges
//   SegmentationTypes.swift  — ProbabilityTensor, ArgmaxMap, SegmentationResult, errors
//   FP16Bytes.swift          — FP16 LE encode/decode for the portable byte contract
//   PreProcessing.swift      — §6.5 steps 1–7 (canonicalise → letterbox → normalise → FP16)
//   PostProcessing.swift     — §6.5 steps 8–13 (softmax → resize back → argmax → σ_seg)
//   CoreMLSegmenter.swift    — high-level wrapper + production Core ML engine
public enum SegmentationModule {
    public static let moduleName = "Segmentation"
}
