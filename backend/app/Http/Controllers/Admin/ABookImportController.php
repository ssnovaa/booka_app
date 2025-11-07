<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Symfony\Component\Process\Process;

class ABookImportController extends Controller
{
    public function import()
    {
        // 🚀 Запускаем CLI-процесс в ФОНЕ:
        // php -d max_execution_time=0 artisan abooks:import-ftp
        // Это избавляет от ограничения 30 сек. в веб-запросе.

        // 1) Путь к PHP-CLI: берём из .env (если задан) либо активный бинарник PHP
        $phpBin  = env('PHP_CLI', \PHP_BINARY);   // Пример для .env: PHP_CLI=/usr/bin/php или "C:\php\php.exe"
        $artisan = base_path('artisan');          // Полный путь к artisan в корне проекта

        // 2) Формируем команду без сокращений
        $command = [
            $phpBin,
            '-d', 'max_execution_time=0',
            $artisan,
            'abooks:import-ftp',
        ];

        // 3) Стартуем отдельный процесс и сразу возвращаем ответ (никаких ожиданий)
        $process = new Process($command, base_path());
        $process->setTimeout(null);      // Без ограничения времени на процесс
        $process->disableOutput();       // Не тянем stdout/stderr в HTTP
        $process->start();               // ВАЖНО: start(), а не run()

        // 4) Мгновенный ответ админке
        return redirect()
            ->route('admin.abooks.index')
            ->with('success', 'Імпорт запущено у фоні (CLI з max_execution_time=0). Перевірте книги за кілька хвилин.');
    }
}
