<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('listen_credits', function (Blueprint $t) {
            $t->id();
            $t->unsignedBigInteger('user_id')->unique(); // 1 пользователь = 1 баланс
            $t->integer('minutes')->default(0);
            $t->timestamps();
        });
    }
    public function down(): void {
        Schema::dropIfExists('listen_credits');
    }
};
