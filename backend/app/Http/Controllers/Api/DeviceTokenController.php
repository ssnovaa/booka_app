<?php
// app/Http/Controllers/Api/DeviceTokenController.php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Support\Facades\Validator;
use App\Models\DeviceToken;
use App\Services\FcmService;

class DeviceTokenController extends Controller
{
    /** Регистрация/обновление токена устройства (работает для гостей и залогиненных). */
    public function store(Request $request)
    {
        // Поддерживаем и JSON, и form-urlencoded
        $payload = $request->json()->all();
        if (empty($payload)) {
            $payload = $request->all();
        }

        // Валидация с явным JSON-ответом (без редиректов)
        $v = Validator::make($payload, [
            'token'       => ['required', 'string', 'max:512'],
            'platform'    => ['nullable', 'string', Rule::in(['android', 'ios', 'other'])],
            'app_version' => ['nullable', 'string', 'max:50'],
            'meta'        => ['nullable', 'array'],
        ]);

        if ($v->fails()) {
            return response()->json(['ok' => false, 'errors' => $v->errors()], 422);
        }

        $data   = $v->validated();
        $userId = optional($request->user())->id;

        $dt = DeviceToken::updateOrCreate(
            ['token' => $data['token']],
            [
                'user_id'      => $userId,
                'platform'     => $data['platform']    ?? null,
                'app_version'  => $data['app_version'] ?? null,
                'meta'         => $data['meta']        ?? null,
                'last_seen_at' => now(),
            ]
        );

        // Если токен был у другого юзера — перепривяжем к текущему залогиненному
        if ($userId && $dt->user_id !== $userId) {
            $dt->user_id = $userId;
            $dt->save();
        }

        return response()->json(['ok' => true]);
    }

    /** Удаление токена (опц.). Для авторизованного — ограничиваемся его токенами. */
    public function destroy(Request $request)
    {
        // Поддерживаем и JSON, и form-urlencoded
        $payload = $request->json()->all();
        if (empty($payload)) {
            $payload = $request->all();
        }

        $v = Validator::make($payload, [
            'token' => ['required', 'string'],
        ]);

        if ($v->fails()) {
            return response()->json(['ok' => false, 'errors' => $v->errors()], 422);
        }

        $token = $v->validated()['token'];

        $q = DeviceToken::where('token', $token);
        if ($request->user()) {
            $uid = $request->user()->id;
            $q->where(function ($w) use ($uid) {
                $w->whereNull('user_id')->orWhere('user_id', $uid);
            });
        }

        $deleted = $q->delete();

        return response()->json(['ok' => $deleted > 0]);
    }

    /** Быстрый тест: отправка пуша на все устройства текущего пользователя. */
    public function test(Request $request, FcmService $fcm)
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['ok' => false, 'error' => 'Auth required'], 401);
        }

        $tokens = DeviceToken::where('user_id', $user->id)->pluck('token')->all();
        if (empty($tokens)) {
            return response()->json(['ok' => false, 'error' => 'No tokens for user'], 404);
        }

        $sent = 0;
        foreach ($tokens as $t) {
            $ok = $fcm->sendToToken(
                token: $t,
                title: 'Booka: тестовое уведомление',
                body:  'Это push от вашего сервера. Всё работает!',
                data:  ['route' => '/profile']
            );
            if ($ok) $sent++;
        }

        return response()->json(['ok' => true, 'sent' => $sent, 'total' => count($tokens)]);
    }
}
