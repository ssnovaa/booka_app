<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\Log;

class RewardsController extends Controller
{
    /**
     * POST /api/rewards/prepare
     * Создаём pending-событие ТОЛЬКО для авторизованного юзера.
     * Возвращаем одноразовый nonce, привязанный к user_id.
     */
    public function prepare(Request $r)
    {
        $user = $r->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $nonce = (string) Str::uuid();

        DB::table('ad_reward_events')->insert([
            'user_id'    => $user->id,
            'nonce'      => $nonce,
            'status'     => 'pending',
            'source'     => 'admob',
            'ip'         => $r->ip(),
            'ua'         => substr((string) $r->userAgent(), 0, 512),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json([
            'nonce'          => $nonce,
            'user_id'        => $user->id,
            'reward_minutes' => 15,
        ]);
    }

    /**
     * GET /api/rewards/status?nonce=...
     * Статус по nonce — только для авторизованных. Ничего не начисляет.
     */
    public function status(Request $r)
    {
        $user = $r->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $nonce = (string) $r->query('nonce', '');
        if ($nonce === '') {
            return response()->json(['status' => 'unknown'], 400);
        }

        $row = DB::table('ad_reward_events')->where('nonce', $nonce)->first();
        if (!$row || (int) $row->user_id !== (int) $user->id) {
            return response()->json(['status' => 'unknown'], 404);
        }

        return response()->json(['status' => $row->status ?? 'unknown'], 200);
    }

    /**
     * GET|POST /api/admob/ssv
     * Публичный SSV-коллбек от AdMob.
     * ad_unit_id и reward_amount делаем опциональными (форма AdMob может их не слать).
     * custom_data может приходить строкой JSON либо URL-энкодом.
     */
    public function admobSsv(Request $r)
    {
        // Читаем как из query, так и из form/json body:
        $userId        = (int) $r->input('user_id', 0);
        $adUnitId      = (string) $r->input('ad_unit_id', '');
        $rewardAmount  = (int) $r->input('reward_amount', 0);
        $rewardType    = (string) $r->input('reward_type', '');       // опционально
        $transactionId = (string) $r->input('transaction_id', '');    // опционально

        // custom_data может быть:
        //  - массивом (если прислали JSON body),
        //  - строкой JSON,
        //  - URL-энкод строкой JSON.
        $customRaw = $r->input('custom_data', '');
        $custom    = [];

        if (is_array($customRaw)) {
            $custom = $customRaw;
        } elseif (is_string($customRaw) && $customRaw !== '') {
            $decoded = $customRaw;
            // Пытаемся убрать двойной URL-энкод, если он есть
            if (str_starts_with($decoded, '%7B') || str_contains($decoded, '%22')) {
                $decoded = urldecode($decoded);
            }
            try {
                $custom = json_decode($decoded, true, 512, JSON_THROW_ON_ERROR);
            } catch (\Throwable $e) {
                $custom = [];
            }
        }

        $nonce = $custom['nonce'] ?? null;

        // reward_amount может не прийти из формы — подставим дефолт
        $defaultMinutes = (int) (config('rewards.default_minutes', 15));
        $minutesToAdd   = $rewardAmount > 0 ? $rewardAmount : $defaultMinutes;

        // Требуем обязательно user_id и nonce; ad_unit_id и reward_amount — опциональны
        if ($userId < 1 || !$nonce) {
            Log::warning('admobSsv: invalid payload (need user_id & nonce)', ['in' => $r->all()]);
            // Возвращаем 200, чтобы AdMob не ретраил вечно
            return response('ok', 200);
        }

        return DB::transaction(function () use ($userId, $adUnitId, $minutesToAdd, $transactionId, $nonce, $r) {
            // Находим событие по nonce (если оно создавалось через /prepare)
            $event = DB::table('ad_reward_events')
                ->where('nonce', $nonce)
                ->lockForUpdate()
                ->first();

            // Если событие отсутствует, всё равно начислим (SSV — источник истины), но создадим запись
            if (!$event) {
                $this->addMinutes($userId, $minutesToAdd);

                DB::table('ad_reward_events')->insert([
                    'user_id'    => $userId,
                    'nonce'      => $nonce,
                    'status'     => 'granted',
                    'ad_unit_id' => $adUnitId ?: null,
                    'source'     => 'admob_ssv',
                    'ip'         => $r->ip(),
                    'ua'         => substr((string) $r->userAgent(), 0, 512),
                    // 'transaction_id' => $transactionId ?: null,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                return response('ok', 200);
            }

            // Если nonce найден, но принадлежит другому пользователю — ничего не делаем
            if ((int) $event->user_id !== $userId) {
                Log::notice('admobSsv: event user mismatch', ['event_user' => $event->user_id, 'user_id' => $userId, 'nonce' => $nonce]);
                return response('ok', 200);
            }

            // Идемпотентность
            if ($event->status === 'granted') {
                return response('ok', 200);
            }

            // Здесь можно включить строгую проверку подписи (SsvVerifier), если нужно.

            // Начисляем минуты (обновляет и seconds_left)
            $this->addMinutes($userId, $minutesToAdd);

            // Обновляем событие → granted
            DB::table('ad_reward_events')
                ->where('id', $event->id)
                ->update([
                    'status'      => 'granted',
                    'ad_unit_id'  => $adUnitId ?: $event->ad_unit_id,
                    'source'      => 'admob_ssv',
                    'ip'          => $r->ip(),
                    'ua'          => substr((string) $r->userAgent(), 0, 512),
                    // 'transaction_id' => $transactionId ?: null,
                    'updated_at'  => now(),
                ]);

            return response('ok', 200);
        });
    }

    /**
     * Начислить минуты пользователю и синхронно обновить seconds_left.
     * Требования к listen_credits:
     *  - UNIQUE индекс на (user_id)
     *  - колонки: user_id INT, minutes INT DEFAULT 0, seconds_left INT NULL|DEFAULT 0, created_at, updated_at
     * Поведение:
     *  - если записи нет — создаём и minutes, и seconds_left;
     *  - если seconds_left NULL — берём текущие секунды как minutes*60;
     *  - увеличиваем обе колонки атомарно.
     */
    private function addMinutes(int $userId, int $minutes): void
    {
        $addSec = max(0, (int) $minutes) * 60;

        DB::transaction(function () use ($userId, $minutes, $addSec) {
            $row = DB::table('listen_credits')
                ->where('user_id', $userId)
                ->lockForUpdate()
                ->first();

            if (!$row) {
                DB::table('listen_credits')->insert([
                    'user_id'      => $userId,
                    'minutes'      => (int) $minutes,
                    'seconds_left' => $addSec,
                    'created_at'   => now(),
                    'updated_at'   => now(),
                ]);
                return;
            }

            $currentMinutes = (int) ($row->minutes ?? 0);

            // seconds_left может быть NULL на старых базах — считаем от minutes
            $currentSeconds = ($row->seconds_left !== null)
                ? (int) $row->seconds_left
                : $currentMinutes * 60;

            $nextMinutes = $currentMinutes + (int) $minutes;
            $nextSeconds = $currentSeconds + $addSec;

            DB::table('listen_credits')
                ->where('id', $row->id)
                ->update([
                    'minutes'      => $nextMinutes,
                    'seconds_left' => $nextSeconds,
                    'updated_at'   => now(),
                ]);
        });
    }
}
