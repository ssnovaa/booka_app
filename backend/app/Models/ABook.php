<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ABook extends Model
{
    use HasFactory;

    protected $fillable = [
        'title',
        'author',      // Можно убрать, если используете только связь author_id
        'author_id',
        'reader_id',
        'description',
        'duration',
        'cover_url',
        'thumb_url',   // <-- новое поле для миниатюры!
        // 'series_id', // как раньше, не обязательно для fillable
    ];

    // Связь: одна книга может иметь много жанров
    public function genres()
    {
        return $this->belongsToMany(\App\Models\Genre::class, 'a_book_genre')->withTimestamps();
    }

    // Связь к автору
    public function author()
    {
        return $this->belongsTo(\App\Models\Author::class);
    }

    // Связь к чтецу (reader)
    public function reader()
    {
        return $this->belongsTo(\App\Models\Reader::class, 'reader_id');
    }

    // Связь к главам, упорядоченных по полю order
    public function chapters()
    {
        return $this->hasMany(\App\Models\AChapter::class)->orderBy('order');
    }

    // Связь к пользователям, которые добавили книгу в избранное
    public function favoritedBy()
    {
        return $this->belongsToMany(\App\Models\User::class, 'a_book_user', 'a_book_id', 'user_id')->withTimestamps();
    }

    /**
     * Серия, к которой принадлежит книга (опционально).
     */
    public function series()
    {
        return $this->belongsTo(\App\Models\Series::class, 'series_id');
    }

    // --- Аксессор: duration ВСЕГДА считает сумму по главам (секунды в минуты)
    public function getDurationAttribute($value)
    {
        // ВСЕГДА считать сумму всех duration глав (секунды)
        $seconds = $this->chapters()->sum('duration');
        return (int) round($seconds / 60);
    }

    // Красивое форматирование длительности (работает всегда)
    public function formattedDuration()
    {
        $minutes = $this->duration; // duration всегда актуально!
        if ($minutes === null || $minutes <= 0) {
            return '';
        }
        $hours = intdiv($minutes, 60);
        $mins = $minutes % 60;
        if ($hours > 0 && $mins > 0) {
            return "{$hours} ч {$mins} мин";
        } elseif ($hours > 0) {
            return "{$hours} ч";
        } else {
            return "{$mins} мин";
        }
    }
}
