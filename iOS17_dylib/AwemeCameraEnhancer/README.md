# Aweme Camera Enhancer

Target: Douyin 40.2.0 (`com.ss.iphone.ugc.Aweme`), iOS 15+, rootless jailbreak.

Features:

- Prefer video instead of photo when entering the camera from `+`.
- Raise the normal recording ceiling to 24 hours (displayed by Douyin as 1440 minutes).
- Keep Douyin's native Live Photo mode selected and use its native Live Photo capture flow.
- Save paired image/video resources as a real Live Photo, return to the camera, and show a save-result toast.
- Write diagnostics to `Documents/AwemeCameraEnhancer.log` in the app container.
- Add a `相机增强` entry across Douyin's old and new Settings controllers. Every feature has an independent switch and defaults to enabled.

Version 1.2.0 removes the delayed global experiment-gate scan that could dismiss the first camera entry. A Live Photo is saved only when both the photo and paired-video resource are available; the plugin will not silently downgrade it to a static photo.

The hooks are limited to camera-domain classes and exact settings controller classes found in Douyin 40.2.0.
