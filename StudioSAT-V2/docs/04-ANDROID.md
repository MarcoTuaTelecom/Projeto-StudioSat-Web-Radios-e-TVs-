# Android V2

Tecnologia: Kotlin + AndroidX Media3.

Referência em 22/09/2026: Media3 1.11.1 e AGP 9.4.0 com Kotlin integrado do AGP 9+.

O `PlaybackService` é dono do ExoPlayer/MediaSession. A Activity apenas envia comandos. Não há WebView, Expo, React Native nem sampling PCM.

```bash
cd native/android
gradle wrapper --gradle-version 9.6.0
./gradlew assembleDebug
```
