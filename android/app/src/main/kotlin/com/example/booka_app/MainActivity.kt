package com.example.booka_app

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Канал для общения Dart ↔️ Android
    private val CHANNEL = "com.example.booka_app/navigation"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Опциональный метод: свернуть приложение (если где-то ещё пригодится)
                "moveTaskToBack" -> {
                    val moved = moveTaskToBack(true)
                    result.success(moved)
                }

                // Жёсткий выход по запросу Flutter:
                // finishAffinity() пытается закрыть всю задачу (как свайп из recent apps)
                "exitApp" -> {
                    try {
                        // Закрываем всю задачу (все Activity внутри этой задачи)
                        finishAffinity()
                        // Подстраховка: дополнительно сворачиваем задачу
                        moveTaskToBack(true)
                    } catch (e: Exception) {
                        // Ничего страшного, система всё равно может добить процесс сама
                    }
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
