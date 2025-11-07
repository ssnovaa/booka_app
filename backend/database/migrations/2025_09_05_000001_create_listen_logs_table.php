<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * Створення таблиці журналу прослуховувань користувачів.
     * Кожен запис означає, що за певний момент часу було зараховано
     * конкретну кількість секунд прослуховування певної глави книги.
     */
    public function up(): void
    {
        Schema::create('listen_logs', function (Blueprint $table) {
            // Первинний унікальний ключ
            $table->id();

            // Посилання на користувача, книгу та главу
            $table->foreignId('user_id')
                ->constrained()
                ->onDelete('cascade');

            $table->foreignId('a_book_id')
                ->constrained('a_books')
                ->onDelete('cascade');

            $table->foreignId('a_chapter_id')
                ->constrained('a_chapters')
                ->onDelete('cascade');

            // Кількість секунд, які зараховано цим оновленням
            $table->unsignedInteger('seconds');

            // Час створення запису (використовується для групування за датою)
            $table->timestamp('created_at');

            // Індекси для швидкого агрегування
            $table->index(['user_id', 'created_at']);
            $table->index(['user_id', 'a_book_id', 'created_at']);
        });
    }

    /**
     * Видалення таблиці журналу прослуховувань.
     */
    public function down(): void
    {
        Schema::dropIfExists('listen_logs');
    }
};
