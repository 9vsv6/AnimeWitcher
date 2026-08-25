package com.animewitcher.app

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.View
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.animewitcher.app.player/pip"
    private val TV_CHANNEL = "com.animewitcher.app/tv_channel"
    private val PLAYER_CHANNEL = "com.animewitcher.app/external_player"

    private var pipChannel: MethodChannel? = null
    private var isPlaying = false
    private var pipSessionActive = false
    private var pipEnabled = true
    private var pipWidth = 16
    private var pipHeight = 9

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Official Android PiP: Activity.enterPictureInPictureMode +
        // PictureInPictureParams (API 26+), with setAutoEnterEnabled on
        // Android 12 so Home / gesture navigation can enter PiP.
        // https://developer.android.com/develop/ui/views/picture-in-picture
        pipChannel = MethodChannel(messenger, CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    applyPipArguments(call.arguments)
                    pipSessionActive = true
                    result.success(enterPipNow())
                }
                "updatePip", "setPipState" -> {
                    applyPipArguments(call.arguments)
                    refreshPipParams()
                    result.success(null)
                }
                "isPipAvailable" -> result.success(isPipSupported())
                else -> result.notImplemented()
            }
        }

        // Android TV Channel
        MethodChannel(messenger, TV_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "createTvChannel" -> {
                    TvChannelUtils.createTvChannel(this)
                    result.success(null)
                }
                "addPrograms" -> {
                    Thread {
                        val channelId = TvChannelUtils.getChannelId(this, getString(R.string.app_name))
                        if (channelId != null) {
                             val items = call.argument<List<Map<String, Any>>>("programs") ?: emptyList()
                             TvChannelUtils.addPrograms(this, channelId, items)
                             runOnUiThread { result.success(null) }
                        } else {
                             TvChannelUtils.createTvChannel(this)
                             val newId = TvChannelUtils.getChannelId(this, getString(R.string.app_name))
                             if (newId != null) {
                                  val items = call.argument<List<Map<String, Any>>>("programs") ?: emptyList()
                                  TvChannelUtils.addPrograms(this, newId, items)
                                  runOnUiThread { result.success(null) }
                             } else {
                                  runOnUiThread { result.error("NO_CHANNEL", "Channel not found and creation failed", null) }
                             }
                        }
                    }.start()
                }
                "deleteStoredPrograms" -> {
                    Thread {
                        TvChannelUtils.deleteStoredPrograms(this)
                        runOnUiThread { result.success(null) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        // External Player Channel — uses native Intent to avoid Uri.parse() issues
        MethodChannel(messenger, PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "launchVideoInPlayer") {
                val videoUrl = call.argument<String>("url") ?: run {
                    result.error("INVALID_ARGS", "url is required", null)
                    return@setMethodCallHandler
                }
                val packageName = call.argument<String>("package")
                val mimeType = call.argument<String>("mimeType") ?: "video/*"
                val title = call.argument<String>("title")

                try {
                    val uri = if (videoUrl.startsWith("file://") || (videoUrl.startsWith("/") && File(videoUrl).exists())) {
                        val filePath = if (videoUrl.startsWith("file://")) {
                            videoUrl.substring(7)
                        } else {
                            videoUrl
                        }
                        FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileProvider", File(filePath))
                    } else {
                        Uri.parse(videoUrl)
                    }

                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mimeType)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (!packageName.isNullOrEmpty()) setPackage(packageName)
                        if (!title.isNullOrEmpty()) {
                            putExtra("title", title)
                            putExtra("android.intent.extra.TITLE", title)
                        }
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: android.content.ActivityNotFoundException) {
                    result.success(false) // Player not installed / not found
                } catch (e: Exception) {
                    result.error("LAUNCH_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun applyPipArguments(raw: Any?) {
        val args = raw as? Map<*, *> ?: return
        (args["isPlaying"] as? Boolean)?.let { isPlaying = it }
        (args["active"] as? Boolean)?.let { pipSessionActive = it }
        (args["enabled"] as? Boolean)?.let { pipEnabled = it }
        intArg(args, "width")?.let { if (it > 0) pipWidth = it }
        intArg(args, "height")?.let { if (it > 0) pipHeight = it }
    }

    private fun intArg(args: Map<*, *>, key: String): Int? {
        return when (val raw = args[key]) {
            is Int -> raw
            is Long -> raw.toInt()
            is Double -> raw.toInt()
            is Float -> raw.toInt()
            else -> null
        }
    }

    private fun isPipSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun shouldAutoEnterPip(): Boolean {
        return pipSessionActive && pipEnabled && isPlaying && isPipSupported()
    }

    private fun pipAspectRatio(): Rational {
        val ratio = pipWidth.toDouble() / pipHeight.toDouble()
        val min = 1.0 / 2.39
        val max = 2.39
        return when {
            ratio < min -> Rational(100, 239)
            ratio > max -> Rational(239, 100)
            else -> Rational(pipWidth, pipHeight)
        }
    }

    private fun sourceRectHint(): Rect {
        val hint = Rect()
        findViewById<View>(android.R.id.content)?.getGlobalVisibleRect(hint)
        if (hint.width() <= 0 || hint.height() <= 0) {
            window.decorView.getGlobalVisibleRect(hint)
        }
        return hint
    }

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(pipAspectRatio())
            .setSourceRectHint(sourceRectHint())
            .setActions(createPipActions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(shouldAutoEnterPip())
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun refreshPipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isPipSupported()) return
        try {
            setPictureInPictureParams(buildPipParams())
        } catch (_: IllegalStateException) {
        } catch (_: IllegalArgumentException) {
        }
    }

    private fun enterPipNow(): Boolean {
        if (!isPipSupported() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (isInPictureInPictureMode) return true
        return try {
            enterPictureInPictureMode(buildPipParams())
        } catch (_: IllegalStateException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }
    
    // Action Constants
    private val ACTION_MEDIA_CONTROL = "media_control"
    private val EXTRA_CONTROL_TYPE = "control_type"
    private val CONTROL_TYPE_PLAY = 1
    private val CONTROL_TYPE_PAUSE = 2
    private val CONTROL_TYPE_REWIND = 3
    private val CONTROL_TYPE_FORWARD = 4

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_MEDIA_CONTROL) {
                val type = intent.getIntExtra(EXTRA_CONTROL_TYPE, 0)
                val method = when (type) {
                    CONTROL_TYPE_PLAY -> "play"
                    CONTROL_TYPE_PAUSE -> "pause"
                    CONTROL_TYPE_REWIND -> "seekBackward"
                    CONTROL_TYPE_FORWARD -> "seekForward"
                    else -> null
                }
                if (method != null) {
                    pipChannel?.invokeMethod(method, null)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val filter = IntentFilter(ACTION_MEDIA_CONTROL)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
        }
    }

    override fun onDestroy() {
        pipSessionActive = false
        super.onDestroy()
        try {
            unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 12+ uses setAutoEnterEnabled instead of this callback.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (shouldAutoEnterPip()) {
            enterPipNow()
        }
    }

    private fun mediaControlIntent(controlType: Int): Intent {
        return Intent(ACTION_MEDIA_CONTROL).apply {
            setPackage(packageName)
            putExtra(EXTRA_CONTROL_TYPE, controlType)
        }
    }

    private fun createPipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()

        val actions = mutableListOf<RemoteAction>()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        val rewindPendingIntent = PendingIntent.getBroadcast(
            this, CONTROL_TYPE_REWIND, mediaControlIntent(CONTROL_TYPE_REWIND), flags
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, R.drawable.ic_replay_10),
                "Rewind",
                "Rewind 10s",
                rewindPendingIntent
            )
        )

        val playPauseReqCode = if (isPlaying) CONTROL_TYPE_PAUSE else CONTROL_TYPE_PLAY
        val playPausePendingIntent = PendingIntent.getBroadcast(
            this, playPauseReqCode, mediaControlIntent(playPauseReqCode), flags
        )
        val playPauseTitle = if (isPlaying) "Pause" else "Play"
        val playPauseIconIdx = if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play_arrow
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, playPauseIconIdx),
                playPauseTitle,
                playPauseTitle,
                playPausePendingIntent
            )
        )

        val forwardPendingIntent = PendingIntent.getBroadcast(
            this, CONTROL_TYPE_FORWARD, mediaControlIntent(CONTROL_TYPE_FORWARD), flags
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, R.drawable.ic_forward_10),
                "Forward",
                "Forward 10s",
                forwardPendingIntent
            )
        )

        return actions
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
        refreshPipParams()
    }
}
