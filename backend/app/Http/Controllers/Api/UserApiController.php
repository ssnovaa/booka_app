<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Auth;
use Laravel\Sanctum\PersonalAccessToken;

class UserApiController extends Controller
{
    /**
     * Профиль пользователя + актуальное «текущее прослушивание».
     *
     * Возвращает:
     * - основные поля пользователя (id, name, email, is_paid)
     * - free_seconds — точный остаток в секундах (listen_credits.seconds_left или minutes*60)
     * - free_minutes — то же, intdiv(free_seconds, 60) для удобства клиентов
     * - favorites, listened — плоские списки с author и cover_url
     * - current_listen: book_id, chapter_id, position, updated_at + вложенные book и chapter
     * - server_time — текущее время сервера (ISO8601, UTC)
     *
     * Кэш HTTP отключён заголовками Cache-Control/Pragma.
     */
    public function profile(Request $request)
    {
        // 1) Пытаемся аутентифицировать пользователя даже на публичном роуте:
        // приоритет: guard sanctum -> стандартный -> ручной разбор bearer.
        $user = Auth::guard('sanctum')->user() ?? $request->user();

        if (!$user) {
            $bearer = $request->bearerToken();
            if ($bearer) {
                $pat = PersonalAccessToken::findToken($bearer);
                if ($pat) {
                    $user = $pat->tokenable; // \App\Models\User
                }
            }
        }

        // helper: безопасно достать секунды из listen_credits
        $safeGetFreeSeconds = static function (?int $userId): int {
            if (!$userId) {
                return 0;
            }
            if (!Schema::hasTable('listen_credits')) {
                return 0;
            }

            $hasSeconds = Schema::hasColumn('listen_credits', 'seconds_left');
            $hasMinutes = Schema::hasColumn('listen_credits', 'minutes');

            if (!$hasSeconds && !$hasMinutes) {
                return 0;
            }

            try {
                $row = DB::table('listen_credits')->where('user_id', $userId)->first();
                if (!$row) {
                    return 0;
                }

                if ($hasSeconds && isset($row->seconds_left) && $row->seconds_left !== null) {
                    return max(0, (int) $row->seconds_left);
                }

                if ($hasMinutes && isset($row->minutes) && $row->minutes !== null) {
                    return max(0, (int) $row->minutes * 60);
                }
            } catch (\Throwable $e) {
                return 0;
            }

            return 0;
        };

        // 2) Гость (нет токена) — отдаём пустой, но валидный профиль + no-cache заголовки
        if (!$user) {
            $freeSeconds = 0;

            return response()
                ->json([
                    'id'             => null,
                    'name'           => null,
                    'email'          => null,
                    'is_paid'        => false,
                    'free_seconds'   => $freeSeconds,
                    'free_minutes'   => intdiv($freeSeconds, 60),
                    'favorites'      => [],
                    'listened'       => [],
                    'current_listen' => null,
                    'server_time'    => now()->toIso8601String(),
                ], 200)
                ->header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
                ->header('Pragma', 'no-cache');
        }

        // 3) Авторизованный пользователь — собираем полный профиль
        $freeSeconds = $safeGetFreeSeconds((int) $user->id);
        $freeMinutes = intdiv($freeSeconds, 60);

        // Избранные книги (плоский JSON)
        $favorites = $user->favoriteBooks()
            ->with('author')
            ->get()
            ->map(function ($book) {
                return [
                    'id'        => (int) $book->id,
                    'title'     => (string) $book->title,
                    'author'    => optional($book->author)->name,
                    'cover_url' => $book->cover_url,
                ];
            })
            ->values();

        // Прослушанные книги (плоский JSON)
        $listened = $user->listenedBooks()
            ->with('author')
            ->get()
            ->map(function ($book) {
                return [
                    'id'        => (int) $book->id,
                    'title'     => (string) $book->title,
                    'author'    => optional($book->author)->name,
                    'cover_url' => $book->cover_url,
                ];
            })
            ->values();

        // Последняя запись прогресса (по updated_at), подгружаем книгу и главу
        $last = $user->listens()
            ->with(['book.author', 'chapter'])
            ->orderByDesc('updated_at')
            ->first();

        $currentListen = null;
        if ($last) {
            $currentListen = [
                'book_id'    => (int) $last->a_book_id,
                'chapter_id' => (int) $last->a_chapter_id,
                'position'   => (int) ($last->position ?? 0),
                'updated_at' => optional($last->updated_at)->toIso8601String(),
                'book'       => [
                    'id'        => (int) $last->a_book_id,
                    'title'     => optional($last->book)->title,
                    'author'    => optional(optional($last->book)->author)->name,
                    'cover_url' => optional($last->book)->cover_url,
                ],
                'chapter'    => [
                    'id'       => (int) $last->a_chapter_id,
                    'title'    => optional($last->chapter)->title,
                    'duration' => optional($last->chapter)->duration,
                ],
            ];
        }

        // Итоговый ответ + no-cache заголовки
        return response()
            ->json([
                'id'             => (int) $user->id,
                'name'           => (string) $user->name,
                'email'          => (string) $user->email,
                'is_paid'        => (bool) $user->is_paid,
                'free_seconds'   => $freeSeconds,
                'free_minutes'   => $freeMinutes,
                'favorites'      => $favorites,
                'listened'       => $listened,
                'current_listen' => $currentListen,
                'server_time'    => now()->toIso8601String(),
            ], 200)
            ->header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
            ->header('Pragma', 'no-cache');
    }
}
