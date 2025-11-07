<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Series extends Model
{
    use HasFactory;

    protected $fillable = [
        'title',
        'description',
        'cover_url',
    ];

    // Одна серия содержит много книг
    public function books()
    {
        return $this->hasMany(ABook::class, 'series_id');
    }
}
