<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('reader_book', function (Blueprint $table) {
            $table->id();
            $table->foreignId('reader_id')->constrained()->cascadeOnDelete();
            $table->foreignId('book_id')->constrained('a_books')->cascadeOnDelete();
            $table->timestamps();
            
            $table->unique(['reader_id', 'book_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('reader_book');
    }
};
