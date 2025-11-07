<?php

namespace Database\Seeders;

use App\Models\ABook;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class AbookSeeder extends Seeder
{
    public function run(): void
    {
        $genres = ['Фантастика', 'Роман', 'Детектив', 'Приключения', 'Фентезі', 'Ужасы'];
        $authors = ['И. Белов', 'Н. Рейн', 'С. Громов', 'А. Зорин', 'К. Ветров'];
        $readers = ['А. Чтецов', 'Е. Голосова', 'П. Актёров', 'В. Звучалов'];

        for ($i = 1; $i <= 20; $i++) {
            ABook::create([
                'title' => 'Книга №' . $i,
                'author' => $authors[array_rand($authors)],
                'reader' => $readers[array_rand($readers)],
                'genre' => $genres[array_rand($genres)],
                'description' => 'Это краткое описание книги №' . $i . ' — демонстрационная запись для разработки.',
                'duration' => rand(5, 14) . ' ч. ' . rand(0, 59) . ' мин.',
                'cover_url' => 'https://placehold.co/300x400?text=Книга+' . $i,
            ]);
        }
    }
}
