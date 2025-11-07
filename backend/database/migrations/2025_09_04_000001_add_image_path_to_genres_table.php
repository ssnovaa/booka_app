<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * 🇺🇦 Додає до таблиці genres стовпець image_path для збереження шляху до зображення жанру.
 * Зберігатимемо шлях відносно диска "public" (наприклад: "genres/uuid.jpg").
 */
return new class extends Migration
{
    /**
     * Запустити міграції.
     */
    public function up(): void
    {
        Schema::table('genres', function (Blueprint $table) {
            $table->string('image_path')->nullable()->after('slug');
        });
    }

    /**
     * Відкотити міграції.
     */
    public function down(): void
    {
        Schema::table('genres', function (Blueprint $table) {
            $table->dropColumn('image_path');
        });
    }
};
