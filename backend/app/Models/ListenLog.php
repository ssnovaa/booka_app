<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Модель ListenLog описує одиничний запис журналу прослуховувань користувачів.
 * Кожен запис означає, що у певний момент було зараховано певну кількість секунд
 * прослуховування конкретної глави конкретної аудіокниги певним користувачем.
 *
 * Поля:
 * - id: int
 * - user_id: int
 * - a_book_id: int
 * - a_chapter_id: int
 * - seconds: int
 * - created_at: \Illuminate\Support\Carbon
 */
class ListenLog extends Model
{
    /**
     * У цієї таблиці немає стовпця updated_at, тому вимикаємо автоматичні мітки часу.
     * Поле created_at заповнюється під час створення запису журналу.
     */
    public $timestamps = false;

    /**
     * Назва таблиці бази даних.
     */
    protected $table = 'listen_logs';

    /**
     * Перелік полів, дозволених для масового присвоєння.
     */
    protected $fillable = [
        'user_id',
        'a_book_id',
        'a_chapter_id',
        'seconds',
        'created_at',
    ];

    /**
     * Зв’язок: запис журналу належить користувачеві.
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Зв’язок: запис журналу належить аудіокнизі.
     */
    public function book(): BelongsTo
    {
        return $this->belongsTo(ABook::class, 'a_book_id');
    }

    /**
     * Зв’язок: запис журналу належить главі аудіокниги.
     */
    public function chapter(): BelongsTo
    {
        return $this->belongsTo(AChapter::class, 'a_chapter_id');
    }
}
