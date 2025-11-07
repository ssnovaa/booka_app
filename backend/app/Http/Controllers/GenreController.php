<?php
// app/Http/Controllers/GenreController.php

namespace App\Http\Controllers;

use App\Models\Genre;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Storage;
use Illuminate\View\View;

class GenreController extends Controller
{
    /**
     * Отобразить список жанров (админка).
     */
    public function index(): View
    {
        // Считаем книги и показываем (при желании в шаблоне можно вывести миниатюру по image_url)
        $genres = Genre::withCount('books')
            ->orderBy('name')
            ->get();

        return view('admin.genres.index', compact('genres'));
    }

    /**
     * API: список жанров для клиента (Flutter).
     * GET /api/genres
     *
     * ВАЖНО: модель Genre имеет $hidden = ['image_path', ...] и $appends = ['image_url'],
     * поэтому здесь просто возвращаем коллекцию — в JSON попадёт id, name, image_url.
     */
    public function apiIndex(): JsonResponse
    {
        // Если используете кеш — раскомментируйте 2 строки ниже и не забудьте инвалидацию в store/update/destroy
        // $genres = Cache::remember('api.genres', 300, fn () => Genre::orderBy('name')->get());
        // return response()->json($genres, 200, [], JSON_UNESCAPED_UNICODE);

        $genres = Genre::orderBy('name')->get(); // image_url попадёт как аксессор
        return response()->json($genres, 200, [], JSON_UNESCAPED_UNICODE);
    }

    /**
     * Показать форму создания нового жанра.
     */
    public function create(): View
    {
        // Передаём пустую модель, чтобы в шаблоне было удобно работать с image_url и т.п.
        $genre = new Genre();
        return view('admin.genres.create', compact('genre'));
    }

    /**
     * Сохранить новый жанр в базе данных.
     * Принимает поле файла "image" (jpeg/png/webp/avif, до 3 МБ), кладёт в storage/app/public/genres,
     * сохраняет относительный путь в image_path.
     */
    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'name'        => ['required', 'string', 'max:255', 'unique:genres,name'],
            'image'       => ['nullable', 'file', 'image', 'mimes:jpeg,png,webp,avif', 'max:3072'],
            'description' => ['nullable', 'string'], // если в БД есть поле description
            'slug'        => ['nullable', 'string', 'max:255', 'unique:genres,slug'], // если есть slug
        ]);

        $genre = new Genre();
        $genre->name = $validated['name'];
        if (array_key_exists('description', $validated)) {
            $genre->description = $validated['description'];
        }
        if (array_key_exists('slug', $validated)) {
            $genre->slug = $validated['slug'];
        }

        if ($request->hasFile('image')) {
            // сохранится что-то вроде "genres/abc123.jpg" на диске "public"
            $path = $request->file('image')->store('genres', 'public');
            $genre->image_path = $path;
        }

        $genre->save();

        // Если кешируете API-ответ:
        // Cache::forget('api.genres');

        return redirect()->route('admin.genres.index')->with('success', 'Жанр добавлен');
    }

    /**
     * Показать форму редактирования жанра.
     */
    public function edit(Genre $genre): View
    {
        return view('admin.genres.edit', compact('genre'));
    }

    /**
     * Обновить жанр в базе данных.
     * Поля: name, (опц.) image, (опц.) remove_image=1 для удаления текущей картинки,
     * а также при наличии в БД — description/slug.
     */
    public function update(Request $request, Genre $genre): RedirectResponse
    {
        $validated = $request->validate([
            'name'         => ['required', 'string', 'max:255', 'unique:genres,name,' . $genre->id],
            'image'        => ['nullable', 'file', 'image', 'mimes:jpeg,png,webp,avif', 'max:3072'],
            'remove_image' => ['nullable', 'boolean'],
            'description'  => ['nullable', 'string'],
            'slug'         => ['nullable', 'string', 'max:255', 'unique:genres,slug,' . $genre->id],
        ]);

        $genre->name = $validated['name'];
        if (array_key_exists('description', $validated)) {
            $genre->description = $validated['description'];
        }
        if (array_key_exists('slug', $validated)) {
            $genre->slug = $validated['slug'];
        }

        // Удаление существующей картинки
        if (!empty($validated['remove_image']) && $genre->image_path) {
            Storage::disk('public')->delete($genre->image_path);
            $genre->image_path = null;
        }

        // Загрузка новой картинки поверх старой
        if ($request->hasFile('image')) {
            if ($genre->image_path) {
                Storage::disk('public')->delete($genre->image_path);
            }
            $path = $request->file('image')->store('genres', 'public');
            $genre->image_path = $path;
        }

        $genre->save();

        // Если кешируете API-ответ:
        // Cache::forget('api.genres');

        return redirect()->route('admin.genres.index')->with('success', 'Жанр обновлён');
    }

    /**
     * Удалить жанр из базы данных (+ физически удалить файл изображения, если был).
     */
    public function destroy(Genre $genre): RedirectResponse
    {
        if ($genre->image_path) {
            Storage::disk('public')->delete($genre->image_path);
        }

        $genre->delete();

        // Если кешируете API-ответ:
        // Cache::forget('api.genres');

        return redirect()->route('admin.genres.index')->with('success', 'Жанр удалён');
    }
}
