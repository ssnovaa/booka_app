<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * Додати булеве поле is_admin до таблиці користувачів та індекс.
     * Міграція є ідемпотентною: якщо колонка або індекс вже існують,
     * повторного створення не відбудеться.
     */
    public function up(): void
    {
        // Якщо колонки ще немає — додаємо колонку та індекс
        if (!Schema::hasColumn('users', 'is_admin')) {
            Schema::table('users', function (Blueprint $table) {
                $table->boolean('is_admin')
                    ->default(false)
                    ->after('password');

                // Імʼя індексу задаємо явно, щоб коректно видаляти у down()
                $table->index('is_admin', 'users_is_admin_index');
            });
        } else {
            // Колонка існує. Спробуємо створити індекс, якщо його немає.
            // Laravel не має універсального "hasIndex", тому обгортаємо у try-catch.
            try {
                Schema::table('users', function (Blueprint $table) {
                    $table->index('is_admin', 'users_is_admin_index');
                });
            } catch (\Throwable $e) {
                // Індекс, ймовірно, вже існує — пропускаємо.
            }
        }
    }

    /**
     * Видалити індекс та колонку is_admin, якщо вони існують.
     */
    public function down(): void
    {
        // Якщо колонки немає — робити нічого
        if (!Schema::hasColumn('users', 'is_admin')) {
            return;
        }

        Schema::table('users', function (Blueprint $table) {
            // Спочатку намагаємося видалити індекс з відомою назвою
            try {
                $table->dropIndex('users_is_admin_index');
            } catch (\Throwable $e) {
                // Можливо, індекс відсутній або має іншу назву — пропускаємо.
            }

            // Далі видаляємо саму колонку
            $table->dropColumn('is_admin');
        });
    }
};
