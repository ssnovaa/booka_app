<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        // 1) Если таблицы нет — создаём с нужной схемой
        if (!Schema::hasTable('listen_credits')) {
            Schema::create('listen_credits', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('user_id');
                $table->integer('minutes')->default(0); // 🔹 ВАЖНО
                $table->timestamps();
                // уникальный индекс на user_id
                $table->unique('user_id', 'listen_credits_user_id_unique');
            });
            return;
        }

        // 2) Если таблица есть — добавляем недостающие колонки
        if (!Schema::hasColumn('listen_credits', 'minutes')) {
            Schema::table('listen_credits', function (Blueprint $table) {
                $table->integer('minutes')->default(0)->after('user_id');
            });
        }

        if (!Schema::hasColumn('listen_credits', 'created_at')) {
            Schema::table('listen_credits', function (Blueprint $table) {
                $table->timestamp('created_at')->nullable();
            });
        }
        if (!Schema::hasColumn('listen_credits', 'updated_at')) {
            Schema::table('listen_credits', function (Blueprint $table) {
                $table->timestamp('updated_at')->nullable();
            });
        }

        // 3) Гарантируем уникальность user_id
        // Для SQLite нельзя "ALTER TABLE ADD CONSTRAINT UNIQUE", поэтому создаём индекс напрямую.
        try {
            // MySQL/Postgres просто переживут этот IF NOT EXISTS; SQLite тоже поддерживает.
            DB::statement('CREATE UNIQUE INDEX IF NOT EXISTS listen_credits_user_id_unique ON listen_credits(user_id)');
        } catch (\Throwable $e) {
            // Если драйвер не поддерживает IF NOT EXISTS и индекс уже есть — просто игнорируем.
        }
    }

    public function down(): void
    {
        // В бою таблицу не дропаем — оставим пустым.
        // Schema::dropIfExists('listen_credits');
    }
};
