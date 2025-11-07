<?php

namespace App\Providers;

use Illuminate\Foundation\Support\Providers\RouteServiceProvider as ServiceProvider;
use Illuminate\Support\Facades\Route;

class RouteServiceProvider extends ServiceProvider
{
    /**
     * The path to the "home" route for your application.
     *
     * Typically, users are redirected here after authentication.
     *
     * @var string
     */
    public const HOME = '/home';

    /**
     * Define your route model bindings, pattern filters, etc.
     */
    public function boot(): void
    {
        $this->routes(function () {
            // Подключение api-маршрутов с префиксом /api и middleware api
            Route::middleware('api')
                ->prefix('api')
                ->group(base_path('routes/api.php'));

            // Подключение web-маршрутов с middleware web
            Route::middleware('web')
                ->group(base_path('routes/web.php'));
        });
    }
}
