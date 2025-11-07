<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Models\ABook;

class Reader extends Model
{
    // Разрешаем массовое присвоение для поля name
    protected $fillable = ['name'];

    // Связь "многие ко многим" с книгами (ABook)
    public function books()
    {
        // 'reader_book' — имя pivot таблицы, 'reader_id' и 'book_id' — внешние ключи
        return $this->belongsToMany(ABook::class, 'reader_book', 'reader_id', 'book_id');
    }
}
