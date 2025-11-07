<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\CreditsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class CreditsController extends Controller
{
    public function __construct(private CreditsService $credits) {}

    /**
     * POST /api/credits/consume
     * Тело: { "seconds": <int>, "context": "player|preview|..." }
     * Возвращает: { "ok": true, "spent": <int>, "remaining_seconds": <int>, "remaining_minutes": <int> }
     */
    public function consume(Request $r)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['ok' => false, 'error' => 'unauthorized'], 401);
        }

        // Платным ничего не списываем
        if (property_exists($user, 'is_paid') && $user->is_paid) {
            $remain = $this->credits->getSeconds($user->id);
            return response()->json([
                'ok' => true,
                'spent' => 0,
                'remaining_seconds' => $remain,
                'remaining_minutes' => intdiv($remain, 60),
                'note' => 'paid_user_no_consumption',
            ]);
        }

        $seconds = (int)$r->input('seconds', 0);
        // Доп. защита от экстремальных значений
        if ($seconds < 0) $seconds = 0;
        if ($seconds > 3600) $seconds = 3600; // не более часа за раз

        [$spent, $remain] = $this->credits->consumeSeconds($user->id, $seconds);

        return response()->json([
            'ok' => true,
            'spent' => $spent,
            'remaining_seconds' => $remain,
            'remaining_minutes' => intdiv($remain, 60),
        ]);
    }
}
