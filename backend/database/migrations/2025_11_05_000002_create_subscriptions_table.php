<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('subscriptions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('user_id')->index();
            $table->string('platform', 16); // "google" | "apple" | "web"
            $table->string('package_name')->nullable(); // com.booka_app
            $table->string('product_id');               // ID подписки в сторе
            $table->string('purchase_token')->unique(); // токен покупки Google Play
            $table->string('order_id')->nullable()->index();
            $table->enum('status', [
                'active','grace','on_hold','paused','canceled','expired','refunded','revoked'
            ])->index();

            $table->timestamp('started_at')->nullable();
            $table->timestamp('renewed_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamp('acknowledged_at')->nullable();
            $table->timestamp('canceled_at')->nullable();

            $table->json('raw_payload')->nullable();   // сырой ответ стора
            $table->timestamp('latest_rtdn_at')->nullable();
            $table->timestamps();

            $table->foreign('user_id')->references('id')->on('users')->cascadeOnDelete();
        });
    }

    public function down(): void {
        Schema::dropIfExists('subscriptions');
    }
};
