<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Проміжний шар IsAdmin гарантує, що доступ до захищених маршрутів
 * отримують лише ті користувачі, які авторизовані та позначені як адміністратори.
 *
 * Вимоги:
 * - У моделі користувача має існувати булеве поле is_admin (каст до boolean).
 * - Маршрути адміністративної частини повинні бути огорнуті цим мідлваром.
 */
class IsAdmin
{
    /**
     * Обробити вхідний запит та перевірити наявність адміністративних прав.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Closure  $next
     * @return \Symfony\Component\HttpFoundation\Response
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // Перевіряємо авторизацію та прапорець адміністратора
        $isAdmin = $user ? (bool) ($user->is_admin ?? false) : false;

        if (!$isAdmin) {
            // Якщо це очікувано JSON (API, AJAX), повертаємо JSON-відповідь з кодом 403
            if ($request->expectsJson()) {
                return response()->json(['message' => 'Доступ заборонено'], 403);
            }
            // Для звичайних веб-запитів повертаємо сторінку помилки 403
            abort(403, 'Доступ заборонено');
        }

        return $next($request);
        }
}
