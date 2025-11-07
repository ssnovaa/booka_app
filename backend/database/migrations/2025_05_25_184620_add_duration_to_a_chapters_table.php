<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('a_chapters', function (Blueprint $table) {
            // Добавляем поле duration после audio_path (или order)
            $table->integer('duration')->nullable()->after('audio_path');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('a_chapters', function (Blueprint $table) {
            // Удаляем поле duration при откате миграции
            $table->dropColumn('duration');
        });
    }
};
