<?php

namespace App\Services\Subscriptions;

use App\Integrations\GooglePlayClient;
use App\Models\Subscription;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class GooglePlayVerifier
{
    public function __construct(
        protected GooglePlayClient $play
    ) {}

    /**
     * Верифицирует покупку, денормализует статусы и обновляет users.is_paid / paid_until
     */
    public function verifyAndUpsert(User $user, array $payload): Subscription
    {
        $purchaseToken = $payload['purchaseToken'];
        $productId     = $payload['productId'];
        $packageName   = $payload['packageName'] ?? env('GOOGLE_PLAY_PACKAGE', 'com.booka_app');

        $raw = $this->play->getSubscriptionV2($purchaseToken);
        $norm = $this->normalizeV2($raw);

        return DB::transaction(function () use ($user, $purchaseToken, $productId, $packageName, $norm, $raw) {
            $sub = Subscription::query()->where('purchase_token', $purchaseToken)->first();
            if (!$sub) {
                $sub = new Subscription();
                $sub->user_id        = $user->id;
                $sub->platform       = 'google';
                $sub->package_name   = $packageName;
                $sub->product_id     = $productId;
                $sub->purchase_token = $purchaseToken;
            }

            $sub->order_id         = $norm['order_id'] ?? null;
            $sub->status           = $norm['status'];
            $sub->started_at       = $norm['started_at'];
            $sub->renewed_at       = $norm['renewed_at'];
            $sub->expires_at       = $norm['expires_at'];
            $sub->acknowledged_at  = $norm['acknowledged_at'];
            $sub->canceled_at      = $norm['canceled_at'];
            $sub->raw_payload      = $raw;
            $sub->latest_rtdn_at   = now();
            $sub->save();

            // Обновляем пользователя (денормализация)
            $isPaid = false;
            $paidUntil = null;
            if (!empty($sub->expires_at)) {
                $paidUntil = Carbon::parse($sub->expires_at);
                $isPaid = in_array($sub->status, ['active','grace','paused','on_hold']) && $paidUntil->isFuture();
            }

            $user->is_paid = $isPaid ? 1 : 0;
            $user->paid_until = $paidUntil;
            $user->save();

            return $sub;
        });
    }

    /** Нормализация ответа Subscriptions V2 */
    private function normalizeV2(array $g): array
    {
        // Документация V2 возвращает вложенную структуру lineItems[], subscriptionState и т.д.
        // Ниже максимально безопасное извлечение ключевых полей.
        $orderId  = $g['latestOrderId'] ?? ($g['lineItems'][0]['offerDetails']['basePlanId'] ?? null);

        // Статус
        // Возможные значения: SUBSCRIPTION_STATE_ACTIVE, PAUSED, IN_GRACE_PERIOD, ON_HOLD, CANCELED, EXPIRED
        $state = $g['subscriptionState'] ?? null;
        $map = [
            'SUBSCRIPTION_STATE_ACTIVE'       => 'active',
            'SUBSCRIPTION_STATE_IN_GRACE'     => 'grace',
            'SUBSCRIPTION_STATE_ON_HOLD'      => 'on_hold',
            'SUBSCRIPTION_STATE_PAUSED'       => 'paused',
            'SUBSCRIPTION_STATE_CANCELED'     => 'canceled',
            'SUBSCRIPTION_STATE_EXPIRED'      => 'expired',
        ];
        $status = $map[$state] ?? 'expired';

        // Время
        $start  = $g['startTime']  ?? null;
        $renew  = $g['regionCode'] ?? null; // в V2 нет renewTime напрямую — оставим null
        $expire = $g['expiryTime'] ?? ($g['lineItems'][0]['expiryTime'] ?? null);

        // acknowledge
        $ack = ($g['acknowledgementState'] ?? null) === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED';

        // cancel
        $cancel = $g['canceledStateContext']['userInitiatedCancellation']['cancelTime'] ?? null;

        return [
            'order_id'        => $orderId,
            'status'          => $status,
            'started_at'      => $start ? Carbon::parse($start) : null,
            'renewed_at'      => $renew ? Carbon::parse($renew) : null,
            'expires_at'      => $expire ? Carbon::parse($expire) : null,
            'acknowledged_at' => $ack ? now() : null,
            'canceled_at'     => $cancel ? Carbon::parse($cancel) : null,
        ];
    }
}
