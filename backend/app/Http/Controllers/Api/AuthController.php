<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RefreshToken;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    /**
     * СТАРЫЙ /api/login оставляем как есть — возвращает только token (PAT).
     * (Твой текущий метод login() остаётся без изменений.)
     */

    /**
     * НОВЫЙ логин, возвращающий пару access+refresh
     * POST /api/auth/login
     */
    public function loginV2(Request $request)
    {
        $data = $request->validate([
            'email'    => ['required','email'],
            'password' => ['required','string'],
        ]);

        if (!Auth::attempt($data)) {
            return response()->json(['message' => 'Invalid credentials'], 401);
        }

        /** @var User $user */
        $user = $request->user();

        // TTL'ы: можно вынести в конфиг
        $accessTtlMinutes  = 30;
        $refreshTtlDays    = 30;

        // Создаём короткий access (Sanctum PAT с expires_at)
        $accessExpiresAt = now()->addMinutes($accessTtlMinutes);
        $accessToken = $user->createToken('mobile', ['*'], $accessExpiresAt)->plainTextToken;

        // Создаём refresh (raw -> sha256 в БД)
        $raw = bin2hex(random_bytes(32)); // 64 символа
        $refresh = RefreshToken::create([
            'user_id'   => $user->id,
            'token_hash'=> hash('sha256', $raw),
            'expires_at'=> now()->addDays($refreshTtlDays),
            'ip'        => $request->ip(),
            'ua'        => (string) $request->userAgent(),
        ]);

        return response()->json([
            'access_token'        => $accessToken,
            'access_expires_at'   => $accessExpiresAt->toIso8601String(),
            'refresh_token'       => $raw,
            'refresh_expires_at'  => $refresh->expires_at->toIso8601String(),
            'user'                => [
                'id'      => $user->id,
                'name'    => $user->name,
                'email'   => $user->email,
                'is_paid' => $user->is_paid,
            ],
        ]);
    }

    /**
     * Ротация refresh -> новая пара access+refresh
     * POST /api/auth/refresh
     * body: { "refresh_token": "..." }
     */
    public function refresh(Request $request)
    {
        $request->validate([
            'refresh_token' => ['required','string']
        ]);

        $now = CarbonImmutable::now();
        $raw = $request->string('refresh_token')->toString();
        $hash = hash('sha256', $raw);

        /** @var RefreshToken|null $row */
        $row = RefreshToken::query()
            ->where('token_hash', $hash)
            ->first();

        if (!$row || !$row->isActive()) {
            return response()->json(['message' => 'Invalid refresh token'], 401);
        }

        /** @var User $user */
        $user = User::query()->findOrFail($row->user_id);

        // Новая пара
        $accessTtlMinutes = 30;
        $refreshTtlDays   = 30;

        $accessExpiresAt = $now->addMinutes($accessTtlMinutes);
        $accessToken = $user->createToken('mobile', ['*'], $accessExpiresAt)->plainTextToken;

        $newRaw = bin2hex(random_bytes(32));
        $newRefresh = RefreshToken::create([
            'user_id'   => $user->id,
            'token_hash'=> hash('sha256', $newRaw),
            'expires_at'=> $now->addDays($refreshTtlDays),
            'ip'        => $request->ip(),
            'ua'        => (string) $request->userAgent(),
        ]);

        // Ревок старого refresh + ссылка на замену
        $row->update([
            'revoked_at'    => $now,
            'replaced_by_id'=> $newRefresh->id,
        ]);

        // (Опционально) подчистить очень старые refresh токены пользователя:
        // RefreshToken::where('user_id', $user->id)
        //    ->where(fn($q) => $q->whereNotNull('revoked_at')->orWhere('expires_at','<',now()))
        //    ->limit(200)->delete();

        return response()->json([
            'access_token'        => $accessToken,
            'access_expires_at'   => $accessExpiresAt->toIso8601String(),
            'refresh_token'       => $newRaw,
            'refresh_expires_at'  => $newRefresh->expires_at->toIso8601String(),
        ]);
    }

    /**
     * Логаут
     * POST /api/auth/logout
     * headers: Authorization: Bearer <access>
     * body (optional): { "refresh_token": "..." } — отозвать refresh
     */
    public function logout(Request $request)
    {
        // отзываем текущий access
        $request->user()?->currentAccessToken()?->delete();

        // опционально — отозвать переданный refresh
        $raw = $request->string('refresh_token')->toString();
        if ($raw !== '') {
            RefreshToken::query()
                ->where('token_hash', hash('sha256', $raw))
                ->update(['revoked_at' => now()]);
        }

        return response()->noContent();
    }

    /**
     * Профиль авторизованного пользователя (источник истины для статуса подписки)
     * GET /api/auth/me
     * headers: Authorization: Bearer <access>
     */
    public function me(Request $request)
    {
        /** @var \App\Models\User $u */
        $u = $request->user();

        return response()->json([
            'id'         => $u->id,
            'name'       => $u->name,
            'email'      => $u->email,
            'is_paid'    => (bool) $u->is_paid,
            'paid_until' => $u->paid_until, // ISO-строка при касте datetime в модели User
        ]);
    }
}
