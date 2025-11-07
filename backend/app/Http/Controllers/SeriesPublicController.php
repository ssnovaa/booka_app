<?php

namespace App\Http\Controllers;

use App\Models\Series;

class SeriesPublicController extends Controller
{
    public function show($id)
    {
        $series = Series::with(['books.author'])->findOrFail($id);
        return view('series.show', compact('series'));
    }
}
