<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('a_chapters', function (Blueprint $table) {
            $table->id();
            $table->foreignId('a_book_id')->constrained('a_books')->onDelete('cascade');
            $table->string('title');
            $table->integer('order')->default(1);
            $table->string('audio_path');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('a_chapters');
    }
};