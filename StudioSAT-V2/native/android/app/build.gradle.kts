plugins { id("com.android.application") }

android {
    namespace = "br.com.studiosat.v2"
    compileSdk = 37
    defaultConfig {
        applicationId = "br.com.studiosatweb.radio.v2"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "2.0.0-alpha.1"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.appcompat:appcompat:1.8.0")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-session:1.11.1")
}
