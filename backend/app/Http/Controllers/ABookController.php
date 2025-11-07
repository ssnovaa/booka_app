<?php

namespace App\Http\Controllers;

use App\Models\ABook;
use App\Models\AChapter;
use App\Models\Genre;
use App\Models\Author;
use App\Models\Reader;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Intervention\Image\Laravel\Facades\Image; // v3 фасад

class ABookController extends Controller
{
    // Список книг с фильтрами по поиску, жанру, автору, исполнителю и сортировкой
    public function index(Request $request)
    {
        $query = ABook::with(['author', 'reader']);

        if ($search = $request->input('search')) {
            $query->where(function ($q) use ($search) {
                $q->where('title', 'like', "%{$search}%")
                  ->orWhereHas('author', function ($q2) use ($search) {
                      $q2->where('name', 'like', "%{$search}%");
                  })
                  ->orWhere('description', 'like', "%{$search}%");
            });
        }

        if ($genreId = $request->input('genre')) {
            $query->whereHas('genres', function ($q) use ($genreId) {
                $q->where('genres.id', $genreId);
            });
        }

        if ($authorId = $request->input('author')) {
            $query->where('author_id', $authorId);
        }

        if ($readerId = $request->input('reader')) {
            $query->where('reader_id', $readerId);
        }

        if ($sort = $request->input('sort')) {
            if ($sort === 'new') {
                $query->orderBy('created_at', 'desc');
            } elseif ($sort === 'title') {
                $query->orderBy('title');
            } elseif ($sort === 'duration') {
                $query->orderBy('duration', 'desc');
            }
        }

        $books = $query->paginate(12)->withQueryString();

        $allGenres = Genre::orderBy('name')->get();
        $allAuthors = Author::whereHas('books')->orderBy('name')->get();
        $allReaders = Reader::whereHas('books')->orderBy('name')->get();

        return view('abooks.index', compact('books', 'allGenres', 'allAuthors', 'allReaders'));
    }

    // Форма создания книги
    public function create()
    {
        $genres = Genre::orderBy('name')->get();
        $readers = Reader::orderBy('name')->get();
        return view('admin.abooks.create', compact('genres', 'readers'));
    }

    // Сохранение новой книги
    public function store(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'author' => 'required|string|max:255',
            'reader_id' => 'nullable|exists:readers,id',
            'series_id' => 'nullable|exists:series,id',
            'description' => 'nullable|string',
            'genres' => 'required|array',
            'genres.*' => 'integer|exists:genres,id',
            'duration' => 'nullable|integer',
            'cover_file' => 'required|image|mimes:jpg,jpeg,png',
            'audio_files' => 'required|array',
            'audio_files.*' => 'required|mimes:mp3,wav',
        ]);

        $coverPath = $request->file('cover_file')->store('covers', 'public');

        // --- Генерация миниатюры через Intervention Image v3 ---
        $image = Image::read($request->file('cover_file')->getRealPath())->cover(200, 300);
        $thumbName = 'covers/thumb_' . basename($coverPath);
        Storage::disk('public')->put($thumbName, (string) $image->toJpeg(80));
        // --- /Блок миниатюры ---

        $author = Author::firstOrCreate(['name' => $validated['author']]);

        $book = ABook::create([
            'title' => $validated['title'],
            'author_id' => $author->id,
            'reader_id' => $validated['reader_id'] ?? null,
            'series_id' => $validated['series_id'] ?? null,
            'description' => $validated['description'] ?? null,
            'duration' => $validated['duration'] ?? null,
            'cover_url' => $coverPath,
            'thumb_url' => $thumbName, // сохраняем миниатюру
        ]);

        $book->genres()->sync($validated['genres']);

        foreach ($request->file('audio_files') as $index => $audioFile) {
            $path = $audioFile->store('audio', 'private');
            AChapter::create([
                'a_book_id' => $book->id,
                'title' => 'Глава ' . ($index + 1),
                'order' => $index + 1,
                'audio_path' => $path,
            ]);
        }

        return redirect('/abooks')->with('success', 'Книга успешно добавлена!');
    }

    // Форма редактирования книги
    public function edit($id)
    {
        $book = ABook::with(['genres', 'author', 'reader'])->findOrFail($id);
        $genres = Genre::orderBy('name')->get();
        $readers = Reader::orderBy('name')->get();
        return view('admin.abooks.edit', compact('book', 'genres', 'readers'));
    }

    // Обновление книги
    public function update(Request $request, $id)
    {
        $book = ABook::findOrFail($id);

        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'author' => 'required|string|max:255',
            'reader_id' => 'nullable|exists:readers,id',
            'series_id' => 'nullable|exists:series,id',
            'description' => 'nullable|string',
            'genres' => 'required|array',
            'genres.*' => 'integer|exists:genres,id',
            'duration' => 'nullable|integer',
            'cover_file' => 'nullable|image|mimes:jpg,jpeg,png|max:2048',
        ]);

        if ($request->hasFile('cover_file')) {
            if ($book->cover_url) {
                $oldCoverPath = str_replace('storage/', '', $book->cover_url);
                Storage::disk('public')->delete($oldCoverPath);
            }
            if ($book->thumb_url) {
                Storage::disk('public')->delete($book->thumb_url);
            }

            $newCoverPath = $request->file('cover_file')->store('covers', 'public');

            // --- Генерация миниатюры через Intervention Image v3 ---
            $image = Image::read($request->file('cover_file')->getRealPath())->cover(200, 300);
            $thumbName = 'covers/thumb_' . basename($newCoverPath);
            Storage::disk('public')->put($thumbName, (string) $image->toJpeg(80));
            // --- /Блок миниатюры ---

            $book->cover_url = $newCoverPath;
            $book->thumb_url = $thumbName;
        }

        $author = Author::firstOrCreate(['name' => $validated['author']]);
        $book->author_id = $author->id;
        $book->reader_id = $validated['reader_id'] ?? null;
        $book->series_id = $validated['series_id'] ?? null;
        $book->title = $validated['title'];
        $book->description = $validated['description'] ?? null;
        $book->duration = $validated['duration'] ?? null;
        $book->save();

        $book->genres()->sync($validated['genres']);

        return redirect()->route('admin.abooks.index')->with('success', 'Книга обновлена');
    }

    // Удаление книги с файлами и связями
    public function destroy($id)
    {
        $book = ABook::findOrFail($id);

        if ($book->cover_url) {
            $coverPath = str_replace('storage/', '', $book->cover_url);
            Storage::disk('public')->delete($coverPath);
        }
        if ($book->thumb_url) {
            Storage::disk('public')->delete($book->thumb_url); // удаляем миниатюру
        }

        $book->chapters()->each(function ($chapter) {
            Storage::disk('private')->delete($chapter->audio_path);
            $chapter->delete();
        });

        $book->genres()->detach();
        $book->delete();

        return redirect('/admin/abooks')->with('success', 'Книга удалена');
    }

    // Отображение книги с главами
    public function show($id)
    {
        $book = ABook::with('chapters')->findOrFail($id);
        return view('abooks.show', compact('book'));
    }

    // ======================= [API: Каталог аудиокниг (JSON)] =======================
    public function apiIndex(Request $request)
    {
        // Подгружаем series чтобы: 1) избежать N+1, 2) вернуть название серии и её id
        $query = ABook::with(['author', 'reader', 'genres', 'series']);

        // Поиск
        if ($search = $request->input('search')) {
            $query->where(function ($q) use ($search) {
                $q->where('title', 'like', "%{$search}%")
                    ->orWhereHas('author', function ($q2) use ($search) {
                        $q2->where('name', 'like', "%{$search}%");
                    })
                    ->orWhere('description', 'like', "%{$search}%");
            });
        }

        // Фильтр по жанрам (id или name; можно через запятую)
        if ($genre = $request->input('genre')) {
            $genres = is_array($genre) ? $genre : explode(',', $genre);
            $genres = array_filter(array_map('trim', $genres), fn($v) => $v !== '');
            if (!empty($genres)) {
                $query->whereHas('genres', function ($q) use ($genres) {
                    $q->where(function ($w) use ($genres) {
                        foreach ($genres as $g) {
                            if (is_numeric($g)) {
                                $w->orWhere('genres.id', $g);
                            } else {
                                $w->orWhere('genres.name', 'like', "%{$g}%");
                            }
                        }
                    });
                });
            }
        }

        // Фильтр по автору (id или name)
        if ($author = $request->input('author')) {
            $query->whereHas('author', function ($q) use ($author) {
                if (is_numeric($author)) {
                    $q->where('id', $author);
                } else {
                    $q->where('name', 'like', "%{$author}%");
                }
            });
        }

        // Фильтр по чтецу (id или name)
        if ($reader = $request->input('reader')) {
            $query->whereHas('reader', function ($q) use ($reader) {
                if (is_numeric($reader)) {
                    $q->where('id', $reader);
                } else {
                    $q->where('name', 'like', "%{$reader}%");
                }
            });
        }

        // ✅ Фильтр по серии: поддерживаем и series_id, и series (название)
        if ($seriesId = $request->input('series_id')) {
            $ids = is_array($seriesId) ? $seriesId : explode(',', $seriesId);
            $ids = array_filter(array_map('trim', $ids), fn($v) => $v !== '');
            if (!empty($ids)) {
                $query->whereIn('series_id', $ids);
            }
        }
        if ($series = $request->input('series')) {
            $names = is_array($series) ? $series : explode(',', $series);
            $names = array_filter(array_map('trim', $names), fn($v) => $v !== '');
            if (!empty($names)) {
                $query->whereHas('series', function ($q) use ($names) {
                    $q->where(function ($w) use ($names) {
                        foreach ($names as $n) {
                            if (is_numeric($n)) {
                                $w->orWhere('id', $n);
                            } else {
                                // срезаем типографические/обычные кавычки по краям
                                $clean = trim($n, " \t\n\r\0\x0B\"'«»„“”");
                                $w->orWhere('title', 'like', "%{$clean}%");
                            }
                        }
                    });
                });
            }
        }

        // Сортировка
        if ($sort = $request->input('sort')) {
            if ($sort === 'new') {
                $query->orderBy('created_at', 'desc');
            } elseif ($sort === 'title') {
                $query->orderBy('title');
            } elseif ($sort === 'duration') {
                $query->orderBy('duration', 'desc');
            }
            // при необходимости добавьте ветку popular/rating и т.п.
        } else {
            $query->orderBy('created_at', 'desc');
        }

        // Пагинация
        $perPage = intval($request->input('per_page', 20));
        $books = $query->paginate($perPage)->withQueryString();

        // Ответ
        $result = [
            'current_page' => $books->currentPage(),
            'last_page'    => $books->lastPage(),
            'per_page'     => $books->perPage(),
            'total'        => $books->total(),
            'data'         => $books->map(function ($book) {
                return [
                    'id'          => $book->id,
                    'title'       => $book->title,
                    'author'      => $book->author?->name,
                    'reader'      => $book->reader?->name,
                    'description' => $book->description,
                    'duration'    => $book->duration,
                    // Корректная ссылка для эмулятора Android
                    'cover_url'   => $book->cover_url
                        ? str_replace(['127.0.0.1', 'localhost'], '10.0.2.2', url('/storage/' . $book->cover_url))
                        : null,
                    'thumb_url'   => $book->thumb_url
                        ? str_replace(['127.0.0.1', 'localhost'], '10.0.2.2', url('/storage/' . $book->thumb_url))
                        : null,
                    'genres'      => $book->genres->map(function ($genre) {
                        return [
                            'id'   => $genre->id,
                            'name' => $genre->name,
                        ];
                    })->values(),
                    // ✅ Возвращаем ОБА поля — строковое название серии и её id
                    'series'      => $book->series?->title,
                    'series_id'   => $book->series_id,
                ];
            }),
        ];

        return response()->json($result, 200, [], JSON_UNESCAPED_UNICODE);
    }

    // ======================= [API: ОДНА КНИГА] =======================
    /**
     * GET /api/abooks/{id}
     * Вернуть подробную информацию о книге по id (для Flutter)
     */
    public function apiShow($id)
    {
        $book = ABook::with(['author', 'reader', 'genres', 'series'])->findOrFail($id);

        $result = [
            'id'          => $book->id,
            'title'       => $book->title,
            'author'      => $book->author?->name,
            'reader'      => $book->reader?->name,
            'description' => $book->description,
            'duration'    => $book->duration,
            // Корректная ссылка для эмулятора Android
            'cover_url'   => $book->cover_url
                ? str_replace(['127.0.0.1', 'localhost'], '10.0.2.2', url('/storage/' . $book->cover_url))
                : null,
            'thumb_url'   => $book->thumb_url
                ? str_replace(['127.0.0.1', 'localhost'], '10.0.2.2', url('/storage/' . $book->thumb_url))
                : null,
            'genres'      => $book->genres->map(function ($genre) {
                return [
                    'id'   => $genre->id,
                    'name' => $genre->name,
                ];
            })->values(),
            // ✅ Возвращаем корректные поля серии
            'series'      => $book->series?->title,
            'series_id'   => $book->series_id,
        ];

        return response()->json($result, 200, [], JSON_UNESCAPED_UNICODE);
    }

    // ======================= [API: ГЛАВЫ КНИГИ] =======================
    /**
     * GET /api/abooks/{id}/chapters
     * Вернуть список глав книги по id (для Flutter)
     */
    public function apiChapters($id)
    {
        $book = ABook::findOrFail($id);

        $chapters = AChapter::where('a_book_id', $book->id)
            ->orderBy('order')
            ->get()
            ->map(function ($chapter) {
                return [
                    'id'        => $chapter->id,
                    'duration'  => $chapter->duration,
                    'title'     => $chapter->title,
                    'order'     => $chapter->order,
                    'audio_url' => $chapter->audio_path ? url('/audio/' . $chapter->id) : null,
                ];
            })->values();

        return response()->json($chapters, 200, [], JSON_UNESCAPED_UNICODE);
    }
}
