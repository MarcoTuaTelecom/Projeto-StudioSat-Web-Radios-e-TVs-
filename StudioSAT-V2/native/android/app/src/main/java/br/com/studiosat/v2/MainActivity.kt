package br.com.studiosat.v2

import android.content.ComponentName
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.Spinner
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture

/** UI fina: controla Media3; nunca processa o áudio. */
class MainActivity : AppCompatActivity() {
    private lateinit var controllerFuture: ListenableFuture<MediaController>
    private var muted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val spinner = findViewById<Spinner>(R.id.stations)
        val play = findViewById<Button>(R.id.play)
        val mute = findViewById<Button>(R.id.mute)
        val status = findViewById<TextView>(R.id.status)

        spinner.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, Stations.all.map { it.name })

        val token = SessionToken(this, ComponentName(this, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(this, token).buildAsync()
        controllerFuture.addListener({
            controllerFuture.get().addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) = runOnUiThread {
                    status.text = if (isPlaying) "AO VIVO" else "PAUSADO"
                    play.text = if (isPlaying) "Pausar" else "Ouvir"
                }
            })
        }, mainExecutor)

        play.setOnClickListener {
            if (!controllerFuture.isDone) return@setOnClickListener
            val controller = controllerFuture.get()
            if (controller.isPlaying) controller.pause() else {
                val station = Stations.all[spinner.selectedItemPosition]
                if (controller.currentMediaItem?.mediaId != station.id) {
                    controller.setMediaItem(PlaybackService.item(station))
                    controller.prepare()
                }
                controller.play()
            }
        }

        spinner.onItemSelectedListener = SimpleItemSelectedListener { position ->
            if (!controllerFuture.isDone) return@SimpleItemSelectedListener
            val controller = controllerFuture.get()
            val wasPlaying = controller.isPlaying
            controller.setMediaItem(PlaybackService.item(Stations.all[position]))
            controller.prepare()
            if (wasPlaying) controller.play()
        }

        mute.setOnClickListener {
            if (!controllerFuture.isDone) return@setOnClickListener
            muted = !muted
            controllerFuture.get().volume = if (muted) 0f else 1f
            mute.text = if (muted) "Mudo" else "Som"
        }
    }

    override fun onDestroy() {
        if (::controllerFuture.isInitialized) MediaController.releaseFuture(controllerFuture)
        super.onDestroy()
    }
}
