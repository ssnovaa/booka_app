<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use App\Models\ABook;
use App\Models\AChapter;
use App\Models\Author; // Модель Author
use getID3;

class ImportFtpBooks extends Command
{
    protected $signature = 'abooks:import-ftp';
    protected $description = 'Импорт аудиокниг из storage/app/ftp_books (папка: Название книги_Автор, mp3 + любая картинка) с автоопределением длительности';

    public function handle()
    {
        $ftpPath = storage_path('app/ftp_books');
        if (!is_dir($ftpPath)) {
            $this->error("Папка $ftpPath не найдена.");
            return 1;
        }

        $bookDirs = array_filter(glob($ftpPath . '/*'), 'is_dir');
        $imported = 0;

        foreach ($bookDirs as $dir) {
            $folderName = basename($dir);

            // Проверяем имя папки
            if (!str_contains($folderName, '_')) {
                $this->warn("Папка $folderName не соответствует формату 'Название книги_Автор' — пропущено.");
                continue;
            }
            [$title, $author] = explode('_', $folderName, 2);
            $title = trim(str_replace('_', ' ', $title));
            $author = trim(str_replace('_', ' ', $author));
            $slug = Str::slug($title . '-' . $author);

            // Пропускаем, если уже есть такая книга
            if (ABook::where('slug', $slug)->exists()) {
                $this->info("Книга уже существует: $title ($author)");
                continue;
            }

            // Ищем первую подходящую картинку
            $coverFiles = glob($dir . '/*.{jpg,jpeg,png,webp,bmp,JPG,JPEG,PNG,WEBP,BMP}', GLOB_BRACE);
            if (empty($coverFiles)) {
                $this->warn("Не найдено изображение-обложки в $dir — пропущено.");
                continue;
            }
            $coverFile = $coverFiles[0];
            $coverExt = pathinfo($coverFile, PATHINFO_EXTENSION);
            $coverPath = 'covers/' . $slug . '.' . $coverExt;
            Storage::disk('public')->put($coverPath, file_get_contents($coverFile));

            // Ищем mp3-файлы
            $chapters = glob($dir . '/*.mp3');
            sort($chapters, SORT_NATURAL);

            if (empty($chapters)) {
                $this->warn("Нет mp3-файлов в $dir — пропущено.");
                continue;
            }

            // Считаем длительность
            $bookDuration = 0;
            $chapterDurations = [];
            $getID3 = new getID3;

            foreach ($chapters as $idx => $file) {
                $info = $getID3->analyze($file);
                $duration = isset($info['playtime_seconds']) ? (int)round($info['playtime_seconds']) : null;
                $chapterDurations[] = $duration ?? 0;
                $bookDuration += $duration ?? 0;
            }

            // Находим или создаём автора
            $authorModel = Author::firstOrCreate(['name' => $author]);
            $authorId = $authorModel->id;

            // Создаём книгу (длительность — в минутах!)
            $book = ABook::create([
                'title' => $title,
                'slug' => $slug,
                'description' => null,
                'author_id' => $authorId,
                'reader_id' => null,
                'cover_url' => $coverPath,
                'duration' => (int)round($bookDuration / 60), // <--- теперь минуты!
            ]);

            // Создаём главы
            foreach ($chapters as $idx => $file) {
                $chapterNum = $idx + 1;
                $chapterPath = "audio/{$book->id}_{$chapterNum}.mp3";
                Storage::disk('local')->put('private/' . $chapterPath, file_get_contents($file));

                AChapter::create([
                    'a_book_id' => $book->id,
                    'title' => "Глава $chapterNum",
                    'order' => $chapterNum,
                    'audio_path' => $chapterPath, // Пример: audio/28_1.mp3
                    'duration' => $chapterDurations[$idx] ?? null,
                ]);
            }

            $this->info("Импортирована книга: $title ($author) (" . count($chapters) . " глав, {$bookDuration} сек)");
            $imported++;
        }

        $this->info("Готово! Импортировано книг: $imported");
        return 0;
    }
}
