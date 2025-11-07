<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

use App\Models\AdRewardEvent;
use App\Models\ListenCredit;

use App\Services\Admob\SsvVerifier;

class RewardsController extends Controller
{
    /**
     * POST /api/rewards/prepare
     * Только для авторизованных (auth:sanctum).
     * Создаём pending-событие и возвращаем одноразовый nonce.
     */
    public function prepare(Request $request)
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $nonce = Str::uuid()->toString();

        AdRewardEvent::create([
            'user_id' => $user->id,
            'nonce'   => $nonce,
            'status'  => 'pending',
            'ip'      => $request->ip(),
            'ua'      => $request->userAgent(),
            // 'ad_unit_id' и прочее заполним позже
        ]);

        return response()->json(['nonce' => $nonce], 200);
    }

    /**
     * GET /api/rewards/status?nonce=...&ad_unit_id=...
     * Только для авторизованных (auth:sanctum).
     * Идемпотентно переводит pending → granted и начисляет минуты
     * (в случае, если вы хотите «пуллить» статус без реального SSV).
     *
     * Если у вас SSV приходит от AdMob и сам начисляет минуты, этот метод
     * может просто возвращать текущий статус события.
     */
    public function status(Request $request)
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $nonce    = (string) $request->query('nonce', '');
        $adUnitId = (string) $request->query('ad_unit_id', '');

        if ($nonce === '') {
            return response()->json(['message' => 'Missing nonce'], 422);
        }

        // Находим событие пользователя по nonce
        $event = AdRewardEvent::where('user_id', $user->id)
            ->where('nonce', $nonce)
            ->first();

        if (!$event) {
            // Ничего не знаем про этот nonce
            return response()->json(['status' => 'unknown'], 200);
        }

        if ($event->status === 'granted') {
            // Уже подтверждено ранее
            return response()->json(['status' => 'granted'], 200);
        }

        if ($event->status !== 'pending') {
            // Любой другой статус считаем неактивным
            return response()->json(['status' => $event->status], 200);
        }

        /**
         * Вариант А (быстрый): Начислять минуты прямо тут при первом запросе статуса.
         * Вариант Б (строгий прод): Статус меняется SSV-коллбеком, а тут только читаем.
         *
         * Для удобной отладки оставляю Вариант А по умолчанию (+15 минут).
         * Для продакшна можете закомментировать блок транзакции ниже.
         */
        try {
            DB::transaction(function () use ($user, $event, $adUnitId) {
                // upsert listen_credits
                $credits = ListenCredit::firstOrNew(['user_id' => $user->id]);
                $credits->minutes = (int) ($credits->minutes ?? 0) + 15;
                $credits->save();

                // обновляем событие
                $event->status     = 'granted';
                $event->ad_unit_id = $adUnitId ?: $event->ad_unit_id;
                $event->source     = $event->source ?: 'poll_status';
                $event->save();
            });
        } catch (\Throwable $e) {
            report($e);
            // Если транзакция не удалась — остаёмся в pending/poll
            return response()->json(['status' => 'pending'], 200);
        }

        return response()->json(['status' => 'granted'], 200);
    }

    /**
     * GET|POST /api/admob/ssv
     * Публичный коллбек от AdMob (НЕ под auth).
     * Валидируем подпись (если ADMOB_SSV_VERIFY=true), идемпотентно зачисляем минуты.
     *
     * Требуемые параметры (минимум): user_id, ad_unit_id, reward_amount.
     * Рекомендуется передавать custom_data = {"nonce":"..."} из клиента.
     */
    public function admobSsv(Request $request)
    {
        $userId       = (int)    $request->query('user_id', 0);
        $adUnitId     = (string) $request->query('ad_unit_id', '');
        $rewardAmount = (int)    $request->query('reward_amount', 0);
        $rewardType   = (string) $request->query('reward_type', '');
        $transactionId= (string) $request->query('transaction_id', '');
        $customData   = (string) $request->query('custom_data', '');

        $signature    = (string) $request->query('signature', '');
        $keyId        = (string) $request->query('key_id', '');

        if ($userId <= 0 || $adUnitId === '' || $rewardAmount <= 0) {
            return response('Bad Request: missing user_id/ad_unit_id/reward_amount', 400);
        }

        // Валидация подписи Google — включаем через .env: ADMOB_SSV_VERIFY=true|false
        $shouldVerify = (bool) env('ADMOB_SSV_VERIFY', true);
        if ($shouldVerify) {
            $verifier = new SsvVerifier();
            $ok = $verifier->verify($request->fullUrl(), $signature, $keyId);
            if (!$ok) {
                return response('Invalid signature', 400);
            }
        }

        // Извлечём nonce из custom_data (если клиент его передал)
        $nonce = null;
        if ($customData !== '') {
            try {
                $j = json_decode($customData, true, 512, JSON_THROW_ON_ERROR);
                if (is_array($j) && isset($j['nonce'])) {
                    $nonce = (string) $j['nonce'];
                }
            } catch (\Throwable $e) {
                // некорректный JSON — работаем без nonce
            }
        }

        // Идемпотентно зачислим минуты
        try {
            DB::transaction(function () use ($userId, $adUnitId, $rewardAmount, $transactionId, $request, $nonce) {
                $minutesToAdd = $rewardAmount; // чаще всего 15

                // Если есть pending-событие по nonce — переведём его в granted
                $event = null;
                if ($nonce) {
                    $event = AdRewardEvent::where('user_id', $userId)
                        ->where('nonce', $nonce)
                        ->lockForUpdate()
                        ->first();
                }

                if ($event) {
                    if ($event->status !== 'granted') {
                        $this->addMinutes($userId, $minutesToAdd);

                        $event->status     = 'granted';
                        $event->ad_unit_id = $adUnitId;
                        $event->source     = 'admob_ssv';
                        $event->ua         = $request->userAgent();
                        $event->ip         = $request->ip();
                        // Если в вашей схеме есть поле transaction_id — запишите его и сделайте UNIQUE
                        // $event->transaction_id = $transactionId ?: null;
                        $event->save();
                    }
                    return;
                }

                // Если события нет — всё равно начисляем минуты (SSV — источник истины) и пишем granted-событие
                $this->addMinutes($userId, $minutesToAdd);

                AdRewardEvent::create([
                    'user_id'    => $userId,
                    'nonce'      => $nonce ?: Str::uuid()->toString(),
                    'status'     => 'granted',
                    'ad_unit_id' => $adUnitId,
                    'source'     => 'admob_ssv',
                    'ua'         => $request->userAgent(),
                    'ip'         => $request->ip(),
                    // 'transaction_id' => $transactionId ?: null,
                ]);
            });
        } catch (\Throwable $e) {
            report($e);
            return response('Internal Server Error', 500);
        }

        return response('OK', 200);
    }

    /**
     * Утилита: начислить минуты пользователю (upsert listen_credits).
     */
    private function addMinutes(int $userId, int $minutes): void
    {
        $credits = ListenCredit::firstOrNew(['user_id' => $userId]);
        $credits->minutes = (int) ($credits->minutes ?? 0) + $minutes;
        $credits->save();
    }
}
