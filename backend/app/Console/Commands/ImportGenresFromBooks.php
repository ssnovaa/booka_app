<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use App\Models\ABook;
use App\Models\Genre;

class ImportGenresFromBooks extends Command
{
    protected $signature = 'genres:import-from-books';
    protected $description = 'Импорт уникальных жанров из JSON-поля a_books.genres в таблицу genres';

    public function handle()
    {
        $books = ABook::all();
        $imported = 0;

        foreach ($books as $book) {
            $genres = json_decode($book->genres, true); // 🛠️ ручной decode из строки

            if (is_array($genres)) {
                foreach ($genres as $genreName) {
                    $clean = trim($genreName);
                    if ($clean && !Genre::where('name', $clean)->exists()) {
                        Genre::create(['name' => $clean]);
                        $this->info("Добавлен жанр: $clean");
                        $imported++;
                    }
                }
            }
        }

        $this->info("✅ Импорт завершён. Добавлено: $imported жанров.");
        return 0;
    }
}
