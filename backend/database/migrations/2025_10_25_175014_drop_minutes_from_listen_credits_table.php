<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1) Удаляем легаси-колонку minutes (если есть)
        Schema::table('listen_credits', function (Blueprint $table) {
            if (Schema::hasColumn('listen_credits', 'minutes')) {
                $table->dropColumn('minutes');
            }
        });

        // 2) seconds_left: приводим NULL -> 0 для всех БД
        DB::table('listen_credits')->whereNull('seconds_left')->update(['seconds_left' => 0]);

        // 3) Усиливаем ограничения в зав-ти от драйвера
        $driver = Schema::getConnection()->getDriverName();

        if ($driver === 'mysql') {
            // MySQL/MariaDB
            DB::statement("ALTER TABLE listen_credits MODIFY seconds_left BIGINT UNSIGNED NOT NULL DEFAULT 0");
        } elseif ($driver === 'pgsql') {
            // PostgreSQL
            DB::statement("ALTER TABLE listen_credits ALTER COLUMN seconds_left SET NOT NULL");
            DB::statement("ALTER TABLE listen_credits ALTER COLUMN seconds_left SET DEFAULT 0");
        } else {
            // SQLite и прочие — MODIFY/ALTER COLUMN недоступны.
            // Мы уже заменили NULL на 0; схему трогать не будем.
            // (Если критично — делается «пересозданием таблицы», но это лишнее.)
        }
    }

    public function down(): void
    {
        // Возвращаем minutes (для отката), без пересчёта
        Schema::table('listen_credits', function (Blueprint $table) {
            $table->integer('minutes')->nullable()->after('user_id');
        });

        // На SQLite дополнительных действий не требуется.
        // На MySQL/PG можно (но не обязательно) убрать DEFAULT/NOT NULL обратно.
    }
};
