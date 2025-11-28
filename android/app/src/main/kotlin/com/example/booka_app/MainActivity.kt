package com.example.booka_app

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // 🟢 Имя канала, используемое во Flutter-коде (EntryScreen.dart)
    private val CHANNEL = "com.booka_app/platform_exit"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // 🟢 МЕТОД 1: Имитация кнопки "Домой" (сворачивание, не закрытие)
                "minimizeApp" -> {
                    // moveTaskToBack(true) — это нативный способ перевести Activity в фон,
                    // имитируя нажатие Home, что не ломает биллинг.
                    val moved = moveTaskToBack(true)
                    result.success(moved)
                }

                // МЕТОД 2: Жёсткий выход по запросу Flutter (для кнопки "Вийти")
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