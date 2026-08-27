# Aweme Camera Enhancer

Target: Douyin 40.2.0 (`com.ss.iphone.ugc.Aweme`), iOS 15+, rootless jailbreak.

Features:

- Prefer video instead of photo when entering the camera from `+`.
- Raise the normal recording ceiling to 24 hours (practically unlimited; storage and system limits still apply).
- Enable Douyin's native Live Photo first-entry switch through its own feature gate.
- Save a successfully captured still image to Photos and restore the record button state.
- Write diagnostics to `Documents/AwemeCameraEnhancer.log` in the app container.
- Add a `相机增强` entry to Douyin's general Settings page. Each feature has an
  independent switch and all switches default to enabled.

The log also records the runtime class returned by the native system Live Photo
callback. This is used to add paired image/video saving without guessing the
private result object's layout if the app does not save the motion asset itself.

The hooks are deliberately limited to camera-domain classes and exact semantic selectors found in Douyin 40.2.0. No global view-controller or camera-framework hooks are used.
