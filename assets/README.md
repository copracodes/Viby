# assets/

Bundled application assets.

## Placeholder: `sample.mp3`

A short royalty-free `sample.mp3` is expected here for local-playback smoke
testing once the audio pipeline lands. It is **not** committed yet — drop a
file named `sample.mp3` into this folder and it will be picked up.

When you add it, register it in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/sample.mp3
```
