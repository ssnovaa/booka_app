<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\ListenLog;
use App\Models\ABook;
use App\Models\AChapter;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Контролер сторінок адміністрування статистики прослуховувань.
 * Містить:
 *  - узагальнену сторінку з фільтрами та списком книг за період,
 *  - звіт по авторам,
 *  - деталізацію по одній книзі (таймсерія та розбивка по главах),
 *  - експорти у форматі CSV.
 */
class ListeningStatsAdminController extends Controller
{
    /**
     * 🧭 Головна сторінка статистики прослуховувань (узагальнено).
     * Фільтри: діапазон дат, групування, ідентифікатор користувача (необов’язково), ідентифікатор книги (необов’язково),
     * пошук за назвою або автором, а також сортування.
     */
    public function index(Request $request)
    {
        // Значення за замовчуванням для фільтрів
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());
        $group = $request->query('group', 'day'); // day | week | month

        $request->validate([
            'from'      => ['required', 'date_format:Y-m-d'],
            'to'        => ['required', 'date_format:Y-m-d'],
            'group'     => ['required', 'in:day,week,month'],
            'user_id'   => ['nullable', 'integer', 'min:1'],
            'a_book_id' => ['nullable', 'integer', 'min:1'],
            'q'         => ['nullable', 'string', 'max:200'],
            'sort'      => ['nullable', 'in:seconds_desc,seconds_asc,title,author'],
        ]);

        $userId = $request->query('user_id');
        $bookId = $request->query('a_book_id');
        $search = (string) $request->query('q', '');
        $sort   = (string) $request->query('sort', 'seconds_desc');

        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        // Ключ кешу на п’ять хвилин
        $cacheKey = 'listen_stats_admin:' . sha1(json_encode([
            'from' => $from,
            'to'   => $to,
            'group' => $group,
            'user_id' => $userId,
            'book_id' => $bookId,
            'q' => $search,
            'sort' => $sort,
        ]));

        $data = Cache::remember($cacheKey, now()->addMinutes(5), function () use ($fromDt, $toDt, $group, $userId, $bookId, $search, $sort) {

            // Базовий запит по журналу
            $logs = ListenLog::query()
                ->whereBetween('created_at', [$fromDt, $toDt]);

            if (!empty($userId)) {
                $logs->where('user_id', (int) $userId);
            }
            if (!empty($bookId)) {
                $logs->where('a_book_id', (int) $bookId);
            }

            // Підсумок за період
            $totalSeconds = (int) $logs->clone()->sum('seconds');

            // База по днях для побудови таймсерії
            $byDay = $logs->clone()
                ->select([
                    DB::raw('DATE(created_at) as d'),
                    DB::raw('SUM(seconds) as s'),
                ])
                ->groupBy(DB::raw('DATE(created_at)'))
                ->orderBy('d')
                ->pluck('s', 'd') // ['YYYY-MM-DD' => seconds]
                ->all();

            // Агреговані рядки відповідно до групування
            $rows = $this->buildGroupedRows($fromDt, $toDt, $group, $byDay);

            // Агрегат за книгами
            $perBookRaw = $logs->clone()
                ->select(['a_book_id', DB::raw('SUM(seconds) as seconds')])
                ->groupBy('a_book_id')
                ->get();

            $books = ABook::whereIn('id', $perBookRaw->pluck('a_book_id')->all())
                ->with('author')
                ->get()
                ->keyBy('id');

            $perBook = $perBookRaw->map(function ($row) use ($books) {
                $book = $books[$row->a_book_id] ?? null;
                $cover = $book?->cover_url;
                if ($cover && !preg_match('~^https?://~i', $cover)) {
                    $cover = url('/storage/' . ltrim($cover, '/'));
                }
                return [
                    'a_book_id' => (int) $row->a_book_id,
                    'seconds'   => (int) $row->seconds,
                    'title'     => $book?->title ?? 'Без назви',
                    'author'    => $book?->author?->name ?? 'Невідомий',
                    'cover_url' => $cover ?: asset('images/placeholder-book.png'),
                ];
            })
            // Пошук за назвою або автором
            ->filter(function ($b) use ($search) {
                if ($search === '') return true;
                $q = Str::lower($search);
                return Str::contains(Str::lower($b['title']), $q) || Str::contains(Str::lower($b['author']), $q);
            })
            // Сортування
            ->sort(function ($a, $b) use ($sort) {
                return match ($sort) {
                    'seconds_asc' => $a['seconds'] <=> $b['seconds'],
                    'title'       => Str::lower($a['title']) <=> Str::lower($b['title']),
                    'author'      => Str::lower($a['author']) <=> Str::lower($b['author']),
                    default       => $b['seconds'] <=> $a['seconds'], // seconds_desc
                };
            })
            ->values()
            ->all();

            return [
                'from'         => $fromDt->toDateString(),
                'to'           => $toDt->toDateString(),
                'group'        => $group,
                'totalSeconds' => $totalSeconds,
                'rows'         => $rows,
                'perBook'      => $perBook,
            ];
        });

        return view('admin.listens.stats', [
            'from'         => $data['from'],
            'to'           => $data['to'],
            'group'        => $data['group'],
            'totalSeconds' => $data['totalSeconds'],
            'rows'         => $data['rows'],
            'perBook'      => $data['perBook'],
            'filters'      => [
                'from'      => $from,
                'to'        => $to,
                'group'     => $group,
                'user_id'   => $userId,
                'a_book_id' => $bookId,
                'q'         => $search,
                'sort'      => $sort,
            ],
        ]);
    }

    /**
     * 📥 Експорт агрегованих інтервалів у CSV для узагальненої сторінки.
     * Маршрут: GET /admin/listens/stats/export.csv
     */
    public function exportCsv(Request $request): StreamedResponse
    {
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());
        $group = $request->query('group', 'day');

        $request->validate([
            'from'      => ['required','date_format:Y-m-d'],
            'to'        => ['required','date_format:Y-m-d'],
            'group'     => ['required','in:day,week,month'],
            'user_id'   => ['nullable','integer','min:1'],
            'a_book_id' => ['nullable','integer','min:1'],
        ]);

        $userId = $request->query('user_id');
        $bookId = $request->query('a_book_id');

        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        $logs = ListenLog::query()->whereBetween('created_at', [$fromDt, $toDt]);
        if (!empty($userId)) { $logs->where('user_id', (int) $userId); }
        if (!empty($bookId)) { $logs->where('a_book_id', (int) $bookId); }

        $byDay = $logs->clone()
            ->select([DB::raw('DATE(created_at) as d'), DB::raw('SUM(seconds) as s')])
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy('d')
            ->pluck('s', 'd')
            ->all();

        $rows = $this->buildGroupedRows($fromDt, $toDt, $group, $byDay);

        $filename = "listening_stats_{$from}_{$to}_{$group}.csv";

        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['Початок', 'Кінець', 'Секунди', 'Зручне відображення часу']);
            foreach ($rows as $r) {
                fputcsv($out, [
                    $r['from'], $r['to'], $r['seconds'], $this->humanize($r['seconds'])
                ]);
            }
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /**
     * 📥 Експорт списку книг за період у CSV (з урахуванням пошуку та сортування).
     * Маршрут: GET /admin/listens/stats/export.books.csv
     */
    public function exportBooksCsv(Request $request): StreamedResponse
    {
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());
        $search= (string) $request->query('q', '');
        $sort  = (string) $request->query('sort', 'seconds_desc');

        $request->validate([
            'from'      => ['required','date_format:Y-m-d'],
            'to'        => ['required','date_format:Y-m-d'],
            'user_id'   => ['nullable','integer','min:1'],
            'a_book_id' => ['nullable','integer','min:1'],
            'q'         => ['nullable','string','max:200'],
            'sort'      => ['nullable','in:seconds_desc,seconds_asc,title,author'],
        ]);

        $userId = $request->query('user_id');
        $bookId = $request->query('a_book_id');

        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        $logs = ListenLog::query()->whereBetween('created_at', [$fromDt, $toDt]);
        if (!empty($userId)) { $logs->where('user_id', (int) $userId); }
        if (!empty($bookId)) { $logs->where('a_book_id', (int) $bookId); }

        $perBookRaw = $logs->clone()
            ->select(['a_book_id', DB::raw('SUM(seconds) as seconds')])
            ->groupBy('a_book_id')
            ->get();

        $books = ABook::whereIn('id', $perBookRaw->pluck('a_book_id')->all())
            ->with('author')
            ->get()
            ->keyBy('id');

        $rows = $perBookRaw->map(function ($row) use ($books) {
            $book = $books[$row->a_book_id] ?? null;
            return [
                'a_book_id' => (int) $row->a_book_id,
                'title'     => $book?->title ?? 'Без назви',
                'author'    => $book?->author?->name ?? 'Невідомий',
                'seconds'   => (int) $row->seconds,
            ];
        })
        ->filter(function ($r) use ($search) {
            if ($search === '') return true;
            $q = Str::lower($search);
            return Str::contains(Str::lower($r['title']), $q) || Str::contains(Str::lower($r['author']), $q);
        })
        ->sort(function ($a, $b) use ($sort) {
            return match ($sort) {
                'seconds_asc' => $a['seconds'] <=> $b['seconds'],
                'title'       => Str::lower($a['title']) <=> Str::lower($b['title']),
                'author'      => Str::lower($a['author']) <=> Str::lower($b['author']),
                default       => $b['seconds'] <=> $a['seconds'],
            };
        })
        ->values()
        ->all();

        $filename = "books_{$from}_{$to}.csv";

        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['Ідентифікатор книги', 'Назва', 'Автор', 'Секунди', 'Зручне відображення часу']);
            foreach ($rows as $r) {
                fputcsv($out, [
                    $r['a_book_id'],
                    $r['title'],
                    $r['author'],
                    $r['seconds'],
                    $this->humanize($r['seconds']),
                ]);
            }
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    // ---------------------------------------------------------------------
    // 📚 Деталізація по одній книзі
    // ---------------------------------------------------------------------

    /**
     * 🔎 Детальна сторінка книги: таймсерія за період та розбивка по главах.
     * Маршрут: GET /admin/listens/books/{a_book_id}
     * Фільтри: from, to, group, user_id (необов’язково)
     */
    public function book(Request $request, int $a_book_id)
    {
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());
        $group = $request->query('group', 'day');

        $request->validate([
            'from'    => ['required','date_format:Y-m-d'],
            'to'      => ['required','date_format:Y-m-d'],
            'group'   => ['required','in:day,week,month'],
            'user_id' => ['nullable','integer','min:1'],
        ]);

        $book = ABook::with('author')->findOrFail($a_book_id);

        $userId = $request->query('user_id');
        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        $cacheKey = 'listen_stats_admin_book:' . sha1(json_encode([
            'book' => $a_book_id,
            'from' => $from,
            'to'   => $to,
            'group'=> $group,
            'user_id' => $userId,
        ]));

        $data = Cache::remember($cacheKey, now()->addMinutes(5), function () use ($a_book_id, $fromDt, $toDt, $group, $userId) {

            $logs = ListenLog::query()
                ->where('a_book_id', $a_book_id)
                ->whereBetween('created_at', [$fromDt, $toDt]);

            if (!empty($userId)) {
                $logs->where('user_id', (int) $userId);
            }

            $totalSeconds = (int) $logs->clone()->sum('seconds');

            // База по днях
            $byDay = $logs->clone()
                ->select([DB::raw('DATE(created_at) as d'), DB::raw('SUM(seconds) as s')])
                ->groupBy(DB::raw('DATE(created_at)'))
                ->orderBy('d')
                ->pluck('s', 'd')
                ->all();

            $rows = $this->buildGroupedRows($fromDt, $toDt, $group, $byDay);

            // Глави книги
            $perChapterRaw = $logs->clone()
                ->select(['a_chapter_id', DB::raw('SUM(seconds) as seconds')])
                ->groupBy('a_chapter_id')
                ->orderBy('a_chapter_id')
                ->get();

            $chapters = AChapter::whereIn('id', $perChapterRaw->pluck('a_chapter_id')->all())
                ->get(['id', 'title', 'duration', 'order'])
                ->keyBy('id');

            $perChapter = $perChapterRaw->map(function ($row) use ($chapters) {
                $ch  = $chapters[$row->a_chapter_id] ?? null;
                $dur = (int) ($ch?->duration ?? 0);
                $sec = (int) $row->seconds;
                $pct = ($dur > 0) ? min(100, round($sec * 100 / $dur)) : null;

                return [
                    'a_chapter_id' => (int) $row->a_chapter_id,
                    'title'        => $ch?->title ?? ('Глава ' . $row->a_chapter_id),
                    'order'        => (int) ($ch?->order ?? 0),
                    'duration'     => $dur,
                    'seconds'      => $sec,
                    'percent'      => $pct,
                ];
            })->sortBy('order')->values()->all();

            return [
                'totalSeconds' => $totalSeconds,
                'rows'         => $rows,
                'perChapter'   => $perChapter,
            ];
        });

        // Обкладинка
        $cover = $book->cover_url;
        if ($cover && !preg_match('~^https?://~i', $cover)) {
            $cover = url('/storage/' . ltrim($cover, '/'));
        }
        $cover = $cover ?: asset('images/placeholder-book.png');

        return view('admin.listens.book', [
            'book'         => $book,
            'cover'        => $cover,
            'from'         => $from,
            'to'           => $to,
            'group'        => $group,
            'user_id'      => $userId,
            'totalSeconds' => $data['totalSeconds'],
            'rows'         => $data['rows'],
            'perChapter'   => $data['perChapter'],
        ]);
    }

    /**
     * ⬇️ Експорт таймсерії по книзі у CSV.
     * Маршрут: GET /admin/listens/books/{a_book_id}/export.series.csv
     */
    public function bookExportSeriesCsv(Request $request, int $a_book_id): StreamedResponse
    {
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());
        $group = $request->query('group', 'day');

        $request->validate([
            'from'    => ['required','date_format:Y-m-d'],
            'to'      => ['required','date_format:Y-m-d'],
            'group'   => ['required','in:day,week,month'],
            'user_id' => ['nullable','integer','min:1'],
        ]);

        $userId = $request->query('user_id');
        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        $logs = ListenLog::query()
            ->where('a_book_id', $a_book_id)
            ->whereBetween('created_at', [$fromDt, $toDt]);

        if (!empty($userId)) {
            $logs->where('user_id', (int) $userId);
        }

        $byDay = $logs->clone()
            ->select([DB::raw('DATE(created_at) as d'), DB::raw('SUM(seconds) as s')])
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy('d')
            ->pluck('s', 'd')
            ->all();

        $rows = $this->buildGroupedRows($fromDt, $toDt, $group, $byDay);
        $filename = "book_{$a_book_id}_series_{$from}_{$to}_{$group}.csv";

        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['Початок', 'Кінець', 'Секунди', 'Зручне відображення часу']);
            foreach ($rows as $r) {
                fputcsv($out, [$r['from'], $r['to'], $r['seconds'], $this->humanize($r['seconds'])]);
            }
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /**
     * ⬇️ Експорт розбивки по главах у CSV.
     * Маршрут: GET /admin/listens/books/{a_book_id}/export.chapters.csv
     */
    public function bookExportChaptersCsv(Request $request, int $a_book_id): StreamedResponse
    {
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());

        $request->validate([
            'from'    => ['required','date_format:Y-m-d'],
            'to'      => ['required','date_format:Y-m-d'],
            'user_id' => ['nullable','integer','min:1'],
        ]);

        $userId = $request->query('user_id');
        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        $logs = ListenLog::query()
            ->where('a_book_id', $a_book_id)
            ->whereBetween('created_at', [$fromDt, $toDt]);

        if (!empty($userId)) {
            $logs->where('user_id', (int) $userId);
        }

        $perChapterRaw = $logs->clone()
            ->select(['a_chapter_id', DB::raw('SUM(seconds) as seconds')])
            ->groupBy('a_chapter_id')
            ->orderBy('a_chapter_id')
            ->get();

        $chapters = AChapter::whereIn('id', $perChapterRaw->pluck('a_chapter_id')->all())
            ->get(['id', 'title', 'duration', 'order'])
            ->keyBy('id');

        $rows = $perChapterRaw->map(function ($row) use ($chapters) {
            $ch  = $chapters[$row->a_chapter_id] ?? null;
            $dur = (int) ($ch?->duration ?? 0);
            $sec = (int) $row->seconds;
            $pct = ($dur > 0) ? min(100, round($sec * 100 / $dur)) : null;

            return [
                'order'        => (int) ($ch?->order ?? 0),
                'a_chapter_id' => (int) $row->a_chapter_id,
                'title'        => $ch?->title ?? ('Глава ' . $row->a_chapter_id),
                'duration'     => $dur,
                'seconds'      => $sec,
                'percent'      => $pct,
            ];
        })->sortBy('order')->values()->all();

        $filename = "book_{$a_book_id}_chapters_{$from}_{$to}.csv";

        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['Порядок', 'Ідентифікатор глави', 'Назва', 'Тривалість, секунд', 'Зараховано, секунд', 'Прогрес, відсотків']);
            foreach ($rows as $r) {
                fputcsv($out, [
                    $r['order'],
                    $r['a_chapter_id'],
                    $r['title'],
                    $r['duration'],
                    $r['seconds'],
                    $r['percent'] !== null ? $r['percent'] : '',
                ]);
            }
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    // ---------------------------------------------------------------------
    // 👤 Звіт по авторам
    // ---------------------------------------------------------------------

    /**
     * 📑 Звіт по авторам: сумарні секунди за обраний період по кожному автору.
     * Маршрут: GET /admin/listens/authors
     * Фільтри: from, to, user_id (необов’язково), пошук q по імені автора, сортування.
     */
    public function authors(Request $request)
    {
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());

        $request->validate([
            'from'    => ['required','date_format:Y-m-d'],
            'to'      => ['required','date_format:Y-m-d'],
            'user_id' => ['nullable','integer','min:1'],
            'q'       => ['nullable','string','max:200'],
            'sort'    => ['nullable','in:seconds_desc,seconds_asc,name'],
        ]);

        $userId = $request->query('user_id');
        $search = (string) $request->query('q', '');
        $sort   = (string) $request->query('sort', 'seconds_desc');

        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        $cacheKey = 'listen_stats_admin_authors:' . sha1(json_encode([
            'from'=>$from,'to'=>$to,'user_id'=>$userId,'q'=>$search,'sort'=>$sort
        ]));

        $data = Cache::remember($cacheKey, now()->addMinutes(5), function () use ($fromDt, $toDt, $userId, $search, $sort) {

            $logs = ListenLog::query()
                ->whereBetween('created_at', [$fromDt, $toDt]);

            if (!empty($userId)) {
                $logs->where('user_id', (int) $userId);
            }

            // Підсумок за період
            $totalSeconds = (int) $logs->clone()->sum('seconds');

            // Спершу збираємо за книгами, а потім агрегуємо на авторів,
            // щоб уникнути залежності від конкретної схеми таблиці авторів.
            $perBookRaw = $logs->clone()
                ->select(['a_book_id', DB::raw('SUM(seconds) as seconds')])
                ->groupBy('a_book_id')
                ->get();

            $books = ABook::whereIn('id', $perBookRaw->pluck('a_book_id')->all())
                ->with('author')
                ->get()
                ->keyBy('id');

            // Агрегація по авторам
            $byAuthor = [];
            foreach ($perBookRaw as $row) {
                $book = $books[$row->a_book_id] ?? null;
                $author = $book?->author;
                $authorId   = (int) ($author?->id ?? 0);
                $authorName = (string) ($author?->name ?? 'Невідомий');

                if (!isset($byAuthor[$authorId])) {
                    $byAuthor[$authorId] = [
                        'author_id'   => $authorId,
                        'author_name' => $authorName,
                        'seconds'     => 0,
                        'books'       => 0,
                    ];
                }
                $byAuthor[$authorId]['seconds'] += (int) $row->seconds;
                // Рахуємо кількість різних книг автора, що мали слухання у періоді
                if ((int) $row->seconds > 0) {
                    $byAuthor[$authorId]['books'] += 1;
                }
            }

            // До масиву
            $rows = array_values($byAuthor);

            // Пошук по імені автора
            if ($search !== '') {
                $q = Str::lower($search);
                $rows = array_values(array_filter($rows, function ($r) use ($q) {
                    return Str::contains(Str::lower($r['author_name']), $q);
                }));
            }

            // Сортування
            usort($rows, function ($a, $b) use ($sort) {
                return match ($sort) {
                    'seconds_asc' => $a['seconds'] <=> $b['seconds'],
                    'name'        => Str::lower($a['author_name']) <=> Str::lower($b['author_name']),
                    default       => $b['seconds'] <=> $a['seconds'], // seconds_desc
                };
            });

            return [
                'totalSeconds' => $totalSeconds,
                'rows'         => $rows,
            ];
        });

        return view('admin.listens.authors', [
            'from'         => $from,
            'to'           => $to,
            'user_id'      => $userId,
            'totalSeconds' => $data['totalSeconds'],
            'rows'         => $data['rows'],
            'filters'      => [
                'from'  => $from,
                'to'    => $to,
                'user_id' => $userId,
                'q'     => $search,
                'sort'  => $sort,
            ],
        ]);
    }

    /**
     * ⬇️ Експорт звіту по авторам у CSV.
     * Маршрут: GET /admin/listens/authors/export.csv
     */
    public function exportAuthorsCsv(Request $request): StreamedResponse
    {
        $today = Carbon::today();
        $from  = $request->query('from', $today->copy()->subDays(29)->toDateString());
        $to    = $request->query('to', $today->toDateString());

        $request->validate([
            'from'    => ['required','date_format:Y-m-d'],
            'to'      => ['required','date_format:Y-m-d'],
            'user_id' => ['nullable','integer','min:1'],
            'q'       => ['nullable','string','max:200'],
            'sort'    => ['nullable','in:seconds_desc,seconds_asc,name'],
        ]);

        $userId = $request->query('user_id');
        $search = (string) $request->query('q', '');
        $sort   = (string) $request->query('sort', 'seconds_desc');

        $fromDt = Carbon::createFromFormat('Y-m-d', $from)->startOfDay();
        $toDt   = Carbon::createFromFormat('Y-m-d', $to)->endOfDay();

        $logs = ListenLog::query()
            ->whereBetween('created_at', [$fromDt, $toDt]);

        if (!empty($userId)) {
            $logs->where('user_id', (int) $userId);
        }

        $perBookRaw = $logs->clone()
            ->select(['a_book_id', DB::raw('SUM(seconds) as seconds')])
            ->groupBy('a_book_id')
            ->get();

        $books = ABook::whereIn('id', $perBookRaw->pluck('a_book_id')->all())
            ->with('author')
            ->get()
            ->keyBy('id');

        $rows = [];
        foreach ($perBookRaw as $row) {
            $book = $books[$row->a_book_id] ?? null;
            $author = $book?->author;
            $authorId   = (int) ($author?->id ?? 0);
            $authorName = (string) ($author?->name ?? 'Невідомий');

            if (!isset($rows[$authorId])) {
                $rows[$authorId] = [
                    'author_id'   => $authorId,
                    'author_name' => $authorName,
                    'seconds'     => 0,
                    'books'       => 0,
                ];
            }
            $rows[$authorId]['seconds'] += (int) $row->seconds;
            if ((int) $row->seconds > 0) {
                $rows[$authorId]['books'] += 1;
            }
        }
        $rows = array_values($rows);

        // Пошук та сортування як на сторінці
        if ($search !== '') {
            $q = Str::lower($search);
            $rows = array_values(array_filter($rows, function ($r) use ($q) {
                return Str::contains(Str::lower($r['author_name']), $q);
            }));
        }
        usort($rows, function ($a, $b) use ($sort) {
            return match ($sort) {
                'seconds_asc' => $a['seconds'] <=> $b['seconds'],
                'name'        => Str::lower($a['author_name']) <=> Str::lower($b['author_name']),
                default       => $b['seconds'] <=> $a['seconds'],
            };
        });

        $filename = "authors_{$from}_{$to}.csv";

        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['Ідентифікатор автора', 'Автор', 'Секунди', 'Зручне відображення часу', 'Кількість книг з прослуховуванням']);
            foreach ($rows as $r) {
                fputcsv($out, [
                    $r['author_id'],
                    $r['author_name'],
                    $r['seconds'],
                    $this->humanize($r['seconds']),
                    $r['books'],
                ]);
            }
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    // ---------------------------------------------------------------------
    // Допоміжні методи
    // ---------------------------------------------------------------------

    /**
     * 🧱 Зібрати рядки агрегату за групою (day | week | month).
     * $byDay має вигляд: ['YYYY-MM-DD' => seconds, ...]
     */
    private function buildGroupedRows(Carbon $from, Carbon $to, string $group, array $byDay): array
    {
        $rows = [];

        if ($group === 'day') {
            $cursor = $from->copy()->startOfDay();
            while ($cursor->lte($to)) {
                $key = $cursor->toDateString();
                $seconds = (int) ($byDay[$key] ?? 0);
                $rows[] = ['from' => $key, 'to' => $key, 'seconds' => $seconds];
                $cursor->addDay();
            }
            return $rows;
        }

        if ($group === 'week') {
            // Тиждень: понеділок — неділя
            $cursor = $from->copy()->startOfWeek(Carbon::MONDAY);
            while ($cursor->lte($to)) {
                $start = $cursor->copy()->startOfWeek(Carbon::MONDAY);
                $end   = $cursor->copy()->endOfWeek(Carbon::SUNDAY);
                if ($start->lt($from)) { $start = $from->copy()->startOfDay(); }
                if ($end->gt($to))     { $end   = $to->copy()->endOfDay(); }

                $seconds = 0;
                $d = $start->copy()->startOfDay();
                while ($d->lte($end)) {
                    $seconds += (int) ($byDay[$d->toDateString()] ?? 0);
                    $d->addDay();
                }

                $rows[] = [
                    'from'    => $start->toDateString(),
                    'to'      => $end->toDateString(),
                    'seconds' => $seconds,
                ];
                $cursor = $end->copy()->addDay();
            }
            return $rows;
        }

        // Місяць
        $cursor = $from->copy()->startOfMonth();
        while ($cursor->lte($to)) {
            $start = $cursor->copy()->startOfMonth();
            $end   = $cursor->copy()->endOfMonth();
            if ($start->lt($from)) { $start = $from->copy()->startOfDay(); }
            if ($end->gt($to))     { $end   = $to->copy()->endOfDay(); }

            $seconds = 0;
            $d = $start->copy()->startOfDay();
            while ($d->lte($end)) {
                $seconds += (int) ($byDay[$d->toDateString()] ?? 0);
                $d->addDay();
            }

            $rows[] = [
                'from'    => $start->toDateString(),
                'to'      => $end->toDateString(),
                'seconds' => $seconds,
            ];
            $cursor = $end->copy()->addDay();
        }
        return $rows;
    }

    /**
     * 🕒 Зручне відображення часу у форматі години, хвилини, секунди.
     */
    private function humanize(int $seconds): string
    {
        $h = intdiv($seconds, 3600);
        $m = intdiv($seconds % 3600, 60);
        $s = $seconds % 60;
        if ($h > 0) { return "{$h} годин {$m} хвилин"; }
        if ($m > 0) { return "{$m} хвилин {$s} секунд"; }
        return "{$s} секунд";
    }
}
