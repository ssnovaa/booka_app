<?php

namespace App\Services;

use Google\Auth\Credentials\ServiceAccountCredentials;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\RequestException;
use GuzzleHttp\TransferStats;
use Psr\Log\LoggerInterface;
use Throwable;

/**
 * 🇺🇦 Сервіс відправлення push-сповіщень через FCM HTTP v1.
 * - Кешує access_token Google, щоб не дергати OAuth на кожне повідомлення
 * - Використовує cURL-хендлер Guzzle (рекомендовано мати увімкнений ext-curl)
 * - Таймаути, форс IPv4 (на випадок проблемних IPv6-маршрутів)
 * - Акуратна побудова payload: data → map<string,string>, без порожніх масивів
 */
class FcmService
{
    private string $projectId;
    private string $credentialsPath;
    private Client $http;
    private LoggerInterface $log;

    /** 🇺🇦 Кешований токен доступу Google OAuth2 */
    private ?string $cachedToken = null;
    /** 🇺🇦 Час закінчення дії токена (unix time) */
    private int $cachedTokenExp = 0;

    public function __construct(LoggerInterface $log)
    {
        $this->projectId       = (string) config('fcm.project_id');
        $this->credentialsPath = (string) config('fcm.credentials_json');

        // 🇺🇦 Загальні налаштування HTTP-клієнта
        $this->http = new Client([
            'timeout'         => 15.0,                 // загальний таймаут запиту (сек)
            'connect_timeout' => 5.0,                  // таймаут встановлення з’єднання (сек)
            'http_errors'     => false,                // не кидати виняток на 4xx/5xx — розберемо вручну
            'headers'         => ['Accept' => 'application/json'],
        ]);

        $this->log = $log;
    }

    /**
     * 🇺🇦 Надіслати повідомлення на один device token.
     * Повертає true для 2xx-відповідей.
     */
    public function sendToToken(string $token, string $title, string $body, array $data = []): bool
    {
        $accessToken = $this->getAccessToken();
        $url = sprintf('https://fcm.googleapis.com/v1/projects/%s/messages:send', $this->projectId);

        // 🇺🇦 Базове повідомлення
        $message = [
            'token'        => $token,
            'notification' => [
                'title' => $title,
                'body'  => $body,
            ],
            'android' => [
                'priority'     => 'HIGH',
                'notification' => [
                    'channel_id' => 'booka_default',
                    'sound'      => 'default',
                ],
            ],
            'apns' => [
                'headers' => ['apns-priority' => '10'],
                'payload' => ['aps' => ['sound' => 'default', 'content-available' => 1]],
            ],
        ];

        // 🇺🇦 FCM data має бути map<string,string>; прибираємо лише null і кастимо у рядки
        $cleanData = [];
        foreach ($data as $k => $v) {
            if ($v !== null) {
                $cleanData[(string) $k] = (string) $v;
            }
        }
        if ($cleanData) {
            $message['data'] = $cleanData;
        }

        $payload = ['message' => $message];

        $elapsed = null;
        try {
            $res = $this->http->post($url, [
                'headers' => [
                    'Authorization' => 'Bearer ' . $accessToken,
                    'Content-Type'  => 'application/json; charset=UTF-8',
                ],
                'json' => $payload,

                // 🇺🇦 Обхід проблем з IPv6-маршрутом провайдерів
                'force_ip_resolve' => 'v4',

                // 🇺🇦 Статистика запиту (час тощо) для логів
                'on_stats' => function (TransferStats $stats) use (&$elapsed) {
                    $elapsed = $stats->getTransferTime(); // секунди з дробом
                },
            ]);

            $code = $res->getStatusCode();
            if ($code >= 200 && $code < 300) {
                return true;
            }

            // 🇺🇦 Логуємо неуспішну відповідь сервера FCM
            $this->log->warning('FCM non-2xx response', [
                'status'  => $code,
                'elapsed' => $elapsed,
                'token'   => $token,
                'body'    => (string) $res->getBody(),
                'payload' => $payload,
            ]);
            return false;

        } catch (RequestException $e) {
            $body = $e->getResponse() ? (string) $e->getResponse()->getBody() : '';
            $this->log->error('FCM send error (RequestException)', [
                'msg'     => $e->getMessage(),
                'elapsed' => $elapsed,
                'token'   => $token,
                'body'    => $body,
                'payload' => $payload,
            ]);
            return false;

        } catch (Throwable $e) {
            $this->log->error('FCM send error (Throwable)', [
                'msg'     => $e->getMessage(),
                'elapsed' => $elapsed,
                'token'   => $token,
                'payload' => $payload,
            ]);
            return false;
        }
    }

    /**
     * 🇺🇦 Отримати (або взяти з кешу) access_token для FCM HTTP v1.
     * Тримаємо запас 60 сек до закінчення, щоб не “вистрілити” простроченим токеном.
     */
    private function getAccessToken(): string
    {
        $now = time();
        if ($this->cachedToken && $now < $this->cachedTokenExp - 60) {
            return $this->cachedToken;
        }

        $scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
        $creds  = new ServiceAccountCredentials($scopes, $this->credentialsPath);
        $auth   = $creds->fetchAuthToken();

        if (empty($auth['access_token'])) {
            throw new \RuntimeException('Failed to obtain Google access token');
        }

        $this->cachedToken = (string) $auth['access_token'];

        // 🇺🇦 Більшість реалізацій повертає expires_at (unix time). Якщо ні — ставимо ~55 хв.
        if (!empty($auth['expires_at'])) {
            $this->cachedTokenExp = (int) $auth['expires_at'];
        } else {
            $this->cachedTokenExp = $now + 3300; // 55 хвилин
        }

        return $this->cachedToken;
    }
}
