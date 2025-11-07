<?php

namespace App\Services\Admob;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

/**
 * Проверка подписи Server-Side Verification от AdMob (RSA-SHA256).
 * Ключи Google берём с https://www.gstatic.com/admob/reward/verifier-keys.json
 * Кэшируем на 10 минут.
 */
class SsvVerifier
{
    private const KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';

    /**
     * @param string $fullUrl   Полный URL запроса (включая query-string).
     * @param string $signature Подпись (base64) из query-параметра "signature".
     * @param string $keyId     Идентификатор ключа из query-параметра "key_id".
     */
    public function verify(string $fullUrl, string $signature, string $keyId): bool
    {
        if ($signature === '' || $keyId === '') {
            return false;
        }

        $pubKey = $this->fetchPublicKeyById($keyId);
        if (!$pubKey) {
            return false;
        }

        $payload = $this->buildPayload($fullUrl);

        $sig = base64_decode($signature, true);
        if ($sig === false) {
            return false;
        }

        $ok = openssl_verify($payload, $sig, $pubKey, OPENSSL_ALGO_SHA256);
        return $ok === 1;
    }

    private function fetchPublicKeyById(string $keyId): ?string
    {
        $keys = Cache::remember('admob_ssv_keys', 600, function () {
            $resp = Http::timeout(5)->get(self::KEYS_URL);
            if (!$resp->ok()) {
                return null;
            }
            return $resp->json();
        });

        if (!is_array($keys) || !isset($keys['keys']) || !is_array($keys['keys'])) {
            return null;
        }

        foreach ($keys['keys'] as $k) {
            if (!isset($k['key_id'], $k['pem'])) {
                continue;
            }
            if ((string)$k['key_id'] === $keyId) {
                return (string)$k['pem']; // PEM-ключ
            }
        }
        return null;
    }

    private function buildPayload(string $fullUrl): string
    {
        $parts  = parse_url($fullUrl);
        $scheme = $parts['scheme'] ?? 'https';
        $host   = $parts['host']   ?? '';
        $path   = $parts['path']   ?? '';
        $query  = isset($parts['query']) ? ('?' . $parts['query']) : '';

        // В сигнатуру включаем схему+хост+путь+query
        return $scheme . '://' . $host . $path . $query;
    }
}
