<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Support\Facades\Storage;

class Genre extends Model
{
    use HasFactory;

    /**
     * 🇺🇦 Дозволені для масового заповнення поля.
     * Зберігаємо шлях до зображення у image_path (відносно диска "public").
     */
    protected $fillable = [
        'name',
        'image_path',
    ];

    /**
     * 🇺🇦 Поля, які не слід віддавати клієнту у JSON-відповідях.
     */
    protected $hidden = [
        'image_path',
        'pivot',
        'created_at',
        'updated_at',
    ];

    /**
     * 🇺🇦 Віртуальні атрибути, що додаються автоматично.
     */
    protected $appends = [
        'image_url',
    ];

    /**
     * 🇺🇦 Повна URL до зображення жанру (або null, якщо зображення не задано).
     */
    public function getImageUrlAttribute(): ?string
    {
        if (!$this->image_path) {
            return null;
        }
        return Storage::disk('public')->url($this->image_path);
    }

    /**
     * 🇺🇦 Звʼязок: жанр належить багатьом книгам (багато-до-багатьох).
     */
    public function books()
    {
        // Pivot-таблиця 'a_book_genre', звʼязок з моделлю ABook
        return $this->belongsToMany(\App\Models\ABook::class, 'a_book_genre')->withTimestamps();
    }
}
