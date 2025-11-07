<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('ad_reward_events', function (Blueprint $t) {
            $t->id();
            $t->unsignedBigInteger('user_id')->default(0); // гость = 0
            $t->string('nonce')->unique();                 // одноразовый идентификатор
            $t->string('status')->default('pending');      // pending|granted|rejected
            $t->string('ad_unit_id')->nullable();          // опционально — какой блок
            $t->string('source')->nullable();              // admob/test/etc
            $t->ipAddress('ip')->nullable();
            $t->string('ua', 512)->nullable();
            $t->timestamps();

            $t->index(['user_id','status']);
        });
    }
    public function down(): void {
        Schema::dropIfExists('ad_reward_events');
    }
};
