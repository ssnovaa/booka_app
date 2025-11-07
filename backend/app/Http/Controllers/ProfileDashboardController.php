<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Models\ABook;
use App\Models\Listen;

class ProfileDashboardController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();

        // --- ТЕКУЩЕЕ ПРОСЛУШИВАНИЕ (как в мобильном клиенте) ---
        // Берём ленту последних прослушиваний с привязкой к книге и главе
        $rows = DB::table('listens as l')
            ->join('a_chapters as ch', 'ch.id', '=', 'l.a_chapter_id')
            ->join('a_books as b', 'b.id', '=', 'l.a_book_id')
            ->where('l.user_id', $user->id)
            ->orderByDesc('l.updated_at')
            ->select([
                'l.a_book_id',
                'l.a_chapter_id',
                'l.position',
                'l.updated_at',

                'ch.id as chapter_id',
                'ch.title as chapter_title',
                'ch.duration as chapter_duration',

                'b.id as book_id',
                'b.title as book_title',
                'b.cover_url as book_cover',
            ])
            ->get();

        // Ищем первую НЕдослушанную; если все добиты — берём самую свежую
        $currentRow = $rows->first(function ($r) {
            $dur = max(1, (int) $r->chapter_duration);
            return (int) $r->position < ($dur - 5); // 5 секунд порог на «дослушано»
        }) ?? $rows->first();

        $currentListen = null;
        if ($currentRow) {
            $dur = max(1, (int) $currentRow->chapter_duration);
            $pct = (int) round(min(100, max(0, ($currentRow->position / $dur) * 100)));

            $currentListen = [
                'position' => (int) $currentRow->position,
                'percent'  => $pct,
                'book' => [
                    'id'        => (int) $currentRow->book_id,
                    'title'     => (string) $currentRow->book_title,
                    'cover_url' => $this->coverUrl($currentRow->book_cover),
                ],
                'chapter' => [
                    'id'       => (int) $currentRow->chapter_id,
                    'title'    => (string) $currentRow->chapter_title,
                    'duration' => $dur,
                ],
            ];
        }

        // --- ID избранного (для «сердец» на карточках) ---
        $favoriteIds = $user->favoriteBooks()->pluck('a_books.id')->all();

        // --- Обране: последние 12 ---
        $favorites = $user->favoriteBooks()
            ->latest('a_book_user.created_at')
            ->take(12)
            ->get(['a_books.id', 'a_books.title', 'a_books.cover_url'])
            ->map(fn ($b) => [
                'id'        => (int) $b->id,
                'title'     => (string) $b->title,
                'cover_url' => $this->coverUrl($b->cover_url),
            ]);

        // --- Прослухані: 12 уникальных книг по последней активности ---
        $listenedIds = Listen::where('user_id', $user->id)
            ->select('a_book_id', DB::raw('MAX(updated_at) as last_at'))
            ->groupBy('a_book_id')
            ->orderByDesc('last_at')
            ->limit(12)
            ->pluck('a_book_id');

        $listenedBooksMap = ABook::whereIn('id', $listenedIds)
            ->get(['id', 'title', 'cover_url'])
            ->keyBy('id');

        $listenedBooks = $listenedIds
            ->map(function ($bid) use ($listenedBooksMap) {
                $b = $listenedBooksMap[$bid] ?? null;
                if (!$b) return null;

                return [
                    'id'        => (int) $b->id,
                    'title'     => (string) $b->title,
                    'cover_url' => $this->coverUrl($b->cover_url),
                ];
            })
            ->filter()
            ->values();

        return view('cabinet.dashboard', [
            'user'           => $user,
            'is_paid'        => (bool) ($user->is_paid ?? false),
            'currentListen'  => $currentListen, // синхронно с мобильным виджетом
            'favorites'      => $favorites,
            'listenedBooks'  => $listenedBooks,
            'favoriteIds'    => $favoriteIds,
        ]);
    }

    public function favorites(Request $request)
    {
        $user = $request->user();

        $favoriteIds = $user->favoriteBooks()->pluck('a_books.id')->all();

        $page = $user->favoriteBooks()
            ->latest('a_book_user.created_at')
            ->paginate(24, ['a_books.id', 'a_books.title', 'a_books.cover_url']);

        $page->getCollection()->transform(function ($b) {
            return (object) [
                'id'        => (int) $b->id,
                'title'     => (string) $b->title,
                'cover_url' => $this->coverUrl($b->cover_url),
            ];
        });

        return view('cabinet.favorites', [
            'user'        => $user,
            'favorites'   => $page,
            'favoriteIds' => $favoriteIds,
        ]);
    }

    public function listened(Request $request)
    {
        $user = $request->user();

        $favoriteIds = $user->favoriteBooks()->pluck('a_books.id')->all();

        $idsPage = Listen::where('user_id', $user->id)
            ->select('a_book_id', DB::raw('MAX(updated_at) as last_at'))
            ->groupBy('a_book_id')
            ->orderByDesc('last_at')
            ->paginate(24);

        $bookIds = $idsPage->getCollection()->pluck('a_book_id')->filter()->unique()->values();
        $books   = ABook::whereIn('id', $bookIds)
            ->get(['id', 'title', 'cover_url'])
            ->keyBy('id');

        $idsPage->getCollection()->transform(function ($row) use ($books) {
            $b = $books[$row->a_book_id] ?? null;

            return (object) [
                'id'        => (int) ($b->id ?? 0),
                'title'     => (string) ($b->title ?? 'Без назви'),
                'cover_url' => $this->coverUrl($b->cover_url ?? null),
            ];
        });

        return view('cabinet.listened', [
            'user'        => $user,
            'listened'    => $idsPage,
            'favoriteIds' => $favoriteIds,
        ]);
    }

    private function coverUrl(?string $stored): string
    {
        if (!$stored) return asset('images/placeholder-book.png');
        if (preg_match('~^https?://~i', $stored)) return $stored;
        return url('/storage/' . ltrim($stored, '/'));
    }
}
