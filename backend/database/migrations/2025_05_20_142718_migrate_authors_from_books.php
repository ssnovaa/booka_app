<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Получаем уникальные имена авторов из таблицы a_books (где author не null и не пусто)
        $authors = DB::table('a_books')
            ->select('author')
            ->distinct()
            ->whereNotNull('author')
            ->where('author', '!=', '')
            ->pluck('author');

        foreach ($authors as $authorName) {
            // Вставляем автора в таблицу authors
            $authorId = DB::table('authors')->insertGetId([
                'name' => $authorName,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Обновляем книги, ставим author_id у книг с таким author
            DB::table('a_books')->where('author', $authorName)->update([
                'author_id' => $authorId,
            ]);
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // Откат не реализован (можно добавить, если нужно)
    }
};
