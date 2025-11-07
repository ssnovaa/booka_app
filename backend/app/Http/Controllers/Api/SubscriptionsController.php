<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Subscriptions\GooglePlayVerifier;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class SubscriptionsController extends Controller
{
    public function __construct(
        protected GooglePlayVerifier $verifier
    ) {}

    public function verifyGooglePlay(Request $request)
    {
        $data = $request->validate([
            'purchaseToken' => 'required|string',
            'productId'     => 'required|string',
            'packageName'   => 'nullable|string',
        ]);

        /** @var User $user */
        $user = $request->user();

        $sub = $this->verifier->verifyAndUpsert($user, $data);

        return response()->json([
            'ok' => true,
            'subscription' => [
                'status'      => $sub->status,
                'expires_at'  => $sub->expires_at,
            ],
            'user' => [
                'is_paid'    => (bool)$user->is_paid,
                'paid_until' => $user->paid_until,
            ]
        ]);
    }

    public function status(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'is_paid'    => (bool)$user->is_paid,
            'paid_until' => $user->paid_until,
        ]);
    }
}
