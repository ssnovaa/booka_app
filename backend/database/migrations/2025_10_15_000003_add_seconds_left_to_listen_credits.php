<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('listen_credits', function (Blueprint $table) {
            // seconds_left: общий баланс секунд, атомарно списываем с него
            $table->unsignedBigInteger('seconds_left')->nullable()->after('minutes');
        });

        // Бэкап и миграция текущих минут -> секунды (идемпотентно)
        DB::table('listen_credits')
            ->whereNull('seconds_left')
            ->update([
                'seconds_left' => DB::raw('CASE WHEN minutes IS NULL THEN 0 ELSE (minutes * 60) END'),
            ]);
    }

    public function down(): void
    {
        // В даун-миграции оставим колонку, чтобы не терять точные секунды
        // Если очень нужно удалить, раскомментируйте:
        // Schema::table('listen_credits', function (Blueprint $table) {
        //     $table->dropColumn('seconds_left');
        // });
    }
};
