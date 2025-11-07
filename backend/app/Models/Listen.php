<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Listen extends Model
{
    protected $fillable = [
        'user_id',
        'a_book_id',
        'a_chapter_id',
        'position',
    ];

    // Гарантируем, что в JSON position и id-шники уходят числами
    protected $casts = [
        'user_id'      => 'integer',
        'a_book_id'    => 'integer',
        'a_chapter_id' => 'integer',
        'position'     => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function chapter()
    {
        return $this->belongsTo(AChapter::class, 'a_chapter_id');
    }

    public function book()
    {
        return $this->belongsTo(ABook::class, 'a_book_id');
    }
}
