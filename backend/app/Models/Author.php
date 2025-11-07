<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Author extends Model
{
    use HasFactory;

    protected $fillable = ['name']; // Разрешаем массовое присвоение поля name

    public function books()
    {
        return $this->hasMany(ABook::class);
    }
}
