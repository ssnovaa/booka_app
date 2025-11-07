<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\View;
use App\Models\Genre;
use App\Models\Author;
use App\Models\Reader; // Добавлен импорт модели Reader

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        View::composer('layouts.app', function ($view) {
            // Жанры — все
            $view->with('allGenres', Genre::orderBy('name')->get());

            // Авторы только те, у которых есть книги
            $authorsWithBooks = Author::whereHas('books')->orderBy('name')->get();
            $view->with('allAuthors', $authorsWithBooks);

            // Исполнители (чтецы) только те, у которых есть книги
            $readersWithBooks = Reader::whereHas('books')->orderBy('name')->get();
            $view->with('allReaders', $readersWithBooks);
        });
    }
}
