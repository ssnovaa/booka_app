<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use App\Models\ABook;
use Illuminate\Support\Facades\Storage;
// !!! ВАЖНО: новый namespace для фасада (Laravel 12 + Image v3)
use Intervention\Image\Laravel\Facades\Image;

class GenerateBookThumbnails extends Command
{
    protected $signature = 'booka:generate-thumbnails';
    protected $description = 'Генерирует миниатюры для всех обложек книг, у которых нет thumb_url';

    public function handle()
    {
        $books = ABook::whereNotNull('cover_url')
            ->where(function($q) {
                $q->whereNull('thumb_url')->orWhere('thumb_url', '');
            })
            ->get();

        $this->info("Книг для генерации: {$books->count()}");

        foreach ($books as $book) {
            $coverPath = $book->cover_url;
            $storagePath = storage_path('app/public/' . $coverPath);

            if (!file_exists($storagePath)) {
                $this->error("Обложка не найдена: {$storagePath}");
                continue;
            }

            // V3: вместо make используем read
            $image = Image::read($storagePath)
                ->cover(200, 300); // cover: обрезает и центрирует под размер (аналог fit)

            $thumbName = 'covers/thumb_' . basename($coverPath);
            Storage::disk('public')->put($thumbName, (string) $image->toJpeg(80)); // V3: toJpeg

            $book->thumb_url = $thumbName;
            $book->save();

            $this->info("Миниатюра создана для книги #{$book->id}");
        }

        $this->info("Готово! Миниатюры сгенерированы.");
        return 0;
    }
}
