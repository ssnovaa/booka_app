<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\AChapter;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Auth;
use Laravel\Sanctum\PersonalAccessToken;

class AudioStreamController extends Controller
{
    public function stream(Request $request, $id)
    {
        // --- Bearer авторизация (Sanctum) для web-роута ---
        if ($token = $request->bearerToken()) {
            if ($pat = PersonalAccessToken::findToken($token)) {
                if ($pat->tokenable) {
                    Auth::login($pat->tokenable);
                }
            }
        }

        // --- Ищем главу ---
        /** @var AChapter|null $chapter */
        $chapter = AChapter::find($id);
        if (!$chapter) {
            abort(404, 'Глава не найдена');
        }

        // Первая глава книги (демо)
        $firstChapter = AChapter::where('a_book_id', $chapter->a_book_id)
            ->orderBy('order')
            ->first();

        // Доступ: не первая глава → только авторизованным
        if (optional($firstChapter)->id !== $chapter->id && !Auth::check()) {
            abort(403, 'Доступ только для зарегистрированных пользователей');
        }

        // Путь к файлу в private storage
        $path = storage_path('app/private/' . ltrim($chapter->audio_path, '/\\'));
        if (!is_file($path)) {
            abort(404, 'Файл не найден');
        }

        // Надёжно определяем размер файла
        $filesize = 0;
        $st = @stat($path);
        if (is_array($st) && isset($st['size'])) {
            $filesize = (int) $st['size'];
        } else {
            // Фоллбек: измеряем через fseek/ftell
            $fpSize = @fopen($path, 'rb');
            if ($fpSize) {
                @fseek($fpSize, 0, SEEK_END);
                $pos = @ftell($fpSize);
                if (is_int($pos) && $pos >= 0) {
                    $filesize = $pos;
                }
                @fclose($fpSize);
            }
        }

        $mime = 'audio/mpeg';

        // Базовые заголовки
        $headers = [
            'Content-Type'        => $mime,
            'Accept-Ranges'       => 'bytes',
            'Content-Disposition' => 'inline; filename="' . basename($path) . '"',
            'Content-Encoding'    => 'identity',   // исключаем сжатие
            'X-Accel-Buffering'   => 'no',         // просим не буферизовать
        ];

        // ---- Разбор Range ----
        $status = 200;
        $start  = 0;
        $end    = $filesize > 0 ? $filesize - 1 : 0;
        $rangeHeader = $request->headers->get('Range');

        if ($rangeHeader && preg_match('/bytes=(\d*)-(\d*)/i', $rangeHeader, $m)) {
            $rangeStart = ($m[1] !== '') ? (int)$m[1] : null;
            $rangeEnd   = ($m[2] !== '') ? (int)$m[2] : null;

            if ($rangeStart === null && $rangeEnd !== null) {
                // bytes=-N (последние N байт)
                $length = max(0, min($rangeEnd, $filesize));
                $start  = max($filesize - $length, 0);
                $end    = $filesize > 0 ? $filesize - 1 : 0;
            } else {
                // bytes=START-END
                $start = max($rangeStart ?? 0, 0);
                $end   = ($rangeEnd !== null && $rangeEnd < $filesize) ? $rangeEnd : ($filesize > 0 ? $filesize - 1 : 0);
            }

            // Валидация диапазона
            if ($filesize <= 0 || $start > $end || $start >= $filesize) {
                $headers['Content-Range'] = 'bytes */' . max($filesize, 0);
                return response('', 416, $headers);
            }

            $status = 206;
            $headers['Content-Range']  = 'bytes ' . $start . '-' . $end . '/' . $filesize;
            $headers['Content-Length'] = (string) ($end - $start + 1);
        } else {
            // Полный файл: выставляем Content-Length ТОЛЬКО если он >0
            if ($filesize > 0) {
                $headers['Content-Length'] = (string) $filesize;
            }
        }

        // HEAD → только заголовки
        if ($request->isMethod('HEAD')) {
            return response('', $status, $headers);
        }

        // ---- Стрим сегмента файла ----
        return response()->stream(function () use ($path, $start, $end) {
            // Гасим любые буферы/компрессию PHP
            if (function_exists('apache_setenv')) {
                @apache_setenv('no-gzip', '1');
            }
            @ini_set('zlib.output_compression', '0');
            @ini_set('output_buffering', '0');
            while (ob_get_level() > 0) {
                @ob_end_clean();
            }

            @set_time_limit(0);
            $chunkSize = 1024 * 256; // 256 KB

            $fp = @fopen($path, 'rb');
            if ($fp === false) {
                return;
            }

            try {
                if ($start > 0) {
                    @fseek($fp, $start);
                }

                $bytesToOutput = $end - $start + 1;
                while ($bytesToOutput > 0 && !feof($fp)) {
                    $readLength = ($bytesToOutput > $chunkSize) ? $chunkSize : $bytesToOutput;
                    $buffer = @fread($fp, $readLength);
                    if ($buffer === false || $buffer === '') {
                        break;
                    }
                    echo $buffer;
                    @flush();
                    $bytesToOutput -= strlen($buffer);
                }
            } finally {
                @fclose($fp);
            }
        }, $status, $headers);
    }
}
