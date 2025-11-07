<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Google\Client as GoogleClient;
use Illuminate\Http\Request;

class AuthGoogleController extends Controller
{
    /**
     * POST /api/auth/google
     * Body: { id_token: string }
     * Возвращает Sanctum-токен и профиль пользователя,
     * создаёт/линкует пользователя по google_id или email.
     */
    public function login(Request $request)
    {
      $idToken = (string) $request->input('id_token');
      if (!$idToken) {
        return response()->json(['message' => 'id_token required'], 422);
      }

      // Проверяем подпись id_token
      $clientId = config('services.google.client_id');
      if (!$clientId) {
        return response()->json(['message' => 'Google client_id not configured'], 500);
      }

      $google = new GoogleClient(['client_id' => $clientId]);
      $payload = $google->verifyIdToken($idToken);
      if (!$payload) {
        return response()->json(['message' => 'invalid id_token'], 401);
      }

      $googleId = $payload['sub']    ?? null;
      $email    = $payload['email']  ?? null;
      $name     = $payload['name']   ?? 'User';
      $avatar   = $payload['picture'] ?? null;

      if (!$googleId || !$email) {
        return response()->json(['message' => 'token missing claims'], 401);
      }

      $user = User::where('google_id', $googleId)->first();
      if (!$user) {
        $user = User::where('email', $email)->first();
      }

      if (!$user) {
        $user = User::create([
          'name'              => $name,
          'email'             => $email,
          'email_verified_at' => now(),
          'google_id'         => $googleId,
          'avatar_url'        => $avatar,
          'password'          => bcrypt(str()->random(32)), // не используется, но поле обязательно
        ]);
      } else {
        // Линкуем Google, если ещё не
        $changed = false;
        if (!$user->google_id) {
          $user->google_id = $googleId;
          $changed = true;
        }
        if (!$user->email_verified_at) {
          $user->email_verified_at = now();
          $changed = true;
        }
        if ($avatar && !$user->avatar_url) {
          $user->avatar_url = $avatar;
          $changed = true;
        }
        if ($changed) $user->save();
      }

      $token = $user->createToken('mobile')->plainTextToken;

      return response()->json([
        'token' => $token,
        'user'  => [
          'id'         => $user->id,
          'name'       => $user->name,
          'email'      => $user->email,
          'avatar_url' => $user->avatar_url,
          'is_paid'    => method_exists($user, 'isPaid') ? (bool) $user->isPaid() : false,
        ],
      ], 200, [], JSON_UNESCAPED_UNICODE);
    }
}
