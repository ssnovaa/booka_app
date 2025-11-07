<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Series;
use App\Models\ABook;
use Illuminate\Http\Request;

class SeriesApiController extends Controller
{
    /**
     * GET /api/series
     * Список серий для вкладки «Серії».
     * Возвращаем краткую инфу + обложку первой книги серии.
     */
    public function index(Request $request)
    {
        // По желанию: пагинация
        $perPage = (int) $request->input('per_page', 20);

        $series = Series::withCount('books')
            ->orderBy('title')
            ->paginate($perPage)
            ->withQueryString();

        $data = $series->getCollection()->map(function (Series $s) {
            // первая книга серии (по id) — чтобы достать обложку
            $first = $s->books()
                ->orderBy('id')
                ->select(['id','title','cover_url','thumb_url'])
                ->first();

            $firstCover = $first?->thumb_url ?? $first?->cover_url;
            $firstCoverAbs = $firstCover ? url('/storage/' . ltrim($firstCover, '/')) : null;

            return [
                'id'            => (int) $s->id,
                'title'         => $s->title,
                'description'   => $s->description,
                'books_count'   => (int) $s->books_count,
                'first_cover'   => $firstCoverAbs, // обложка для карточки серии
            ];
        });

        return response()->json([
            'current_page' => $series->currentPage(),
            'last_page'    => $series->lastPage(),
            'per_page'     => $series->perPage(),
            'total'        => $series->total(),
            'data'         => $data->values(),
        ], 200, [], JSON_UNESCAPED_UNICODE);
    }

    /**
     * GET /api/series/{id}/books
     * Книги в серии — формат, совместимый с Book.fromJson в приложении.
     */
    public function books($id, Request $request)
    {
        $s = Series::findOrFail($id);

        $query = ABook::with(['author','reader','genres'])
            ->where('series_id', $s->id)
            ->orderBy('id');

        // можно добавить пагинацию, но для простоты отдадим все
        $books = $query->get()->map(function (ABook $book) use ($s) {
            $coverAbs = $book->cover_url ? url('/storage/' . ltrim($book->cover_url, '/')) : null;
            $thumbAbs = $book->thumb_url ? url('/storage/' . ltrim($book->thumb_url, '/')) : null;

            return [
                'id'          => (int) $book->id,
                'title'       => $book->title,
                'author'      => $book->author?->name,
                'reader'      => $book->reader?->name,
                'description' => $book->description,
                'duration'    => (string) $book->duration, // фронт ждёт строку
                'cover_url'   => $coverAbs,
                'thumb_url'   => $thumbAbs,
                'genres'      => $book->genres->pluck('name')->values(),
                'series'      => $s->title,
            ];
        });

        return response()->json($books->values(), 200, [], JSON_UNESCAPED_UNICODE);
    }
}
