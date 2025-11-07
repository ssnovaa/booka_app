<?php

namespace App\Integrations;

use Google\Client as GoogleClient;
use Google\Service\AndroidPublisher;
use RuntimeException;

class GooglePlayClient
{
    private AndroidPublisher $service;
    private string $package;

    public function __construct(?string $keyFile = null, ?string $packageName = null)
    {
        $keyFilePath = $keyFile ?? env('GOOGLE_PLAY_KEY_FILE');
        $this->package = $packageName ?? env('GOOGLE_PLAY_PACKAGE', 'com.booka_app');

        if (!$keyFilePath || !is_readable($keyFilePath)) {
            throw new RuntimeException("Google Play key file is not readable at: $keyFilePath");
        }

        $client = new GoogleClient();
        $client->setAuthConfig($keyFilePath);
        $client->setScopes(['https://www.googleapis.com/auth/androidpublisher']);

        $this->service = new AndroidPublisher($client);
    }

    /** Subscriptions V2 — получить данные по токену */
    public function getSubscriptionV2(string $purchaseToken): array
    {
        $resp = $this->service->purchases_subscriptionsv2->get(
            $this->package,
            $purchaseToken
        );
        return json_decode(json_encode($resp), true);
    }
}
