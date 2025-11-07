<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use getID3;

class AChapter extends Model
{
    use HasFactory;

    protected $fillable = [
        'a_book_id',
        'title',
        'order',
        'audio_path',
        'duration',
    ];

    protected static function booted()
    {
        static::saving(function ($chapter) {
            // Если добавили/обновили путь к mp3
            if ($chapter->audio_path && file_exists(storage_path('app/private/' . $chapter->audio_path))) {
                $getID3 = new getID3;
                $info = $getID3->analyze(storage_path('app/private/' . $chapter->audio_path));
                if (isset($info['playtime_seconds'])) {
                    $chapter->duration = (int) round($info['playtime_seconds']);
                }
            }
        });
    }

    public function book()
    {
        return $this->belongsTo(\App\Models\ABook::class, 'a_book_id');
    }
}
