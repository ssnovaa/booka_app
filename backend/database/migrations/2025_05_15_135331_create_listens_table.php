<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('listens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->foreignId('a_chapter_id')->constrained('a_chapters')->onDelete('cascade');
            $table->integer('position')->default(0); // позиция в секундах
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('listens');
    }
};
