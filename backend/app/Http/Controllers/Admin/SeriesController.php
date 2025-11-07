<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Series;

class SeriesController extends Controller
{
    // Список всех серий
    public function index()
    {
        $series = Series::orderBy('title')->paginate(20);
        return view('admin.series.index', compact('series'));
    }

    // Форма создания
    public function create()
    {
        return view('admin.series.create');
    }

    // Сохранение новой серии
    public function store(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'cover_url' => 'nullable|string|max:255',
        ]);
        Series::create($validated);
        return redirect()->route('admin.series.index')->with('success', 'Серия добавлена!');
    }

    // Форма редактирования
    public function edit(Series $series)
    {
        return view('admin.series.edit', compact('series'));
    }

    // Сохранение изменений
    public function update(Request $request, Series $series)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'cover_url' => 'nullable|string|max:255',
        ]);
        $series->update($validated);
        return redirect()->route('admin.series.index')->with('success', 'Серия обновлена!');
    }

    // Удаление серии
    public function destroy(Series $series)
    {
        $series->delete();
        return redirect()->route('admin.series.index')->with('success', 'Серия удалена!');
    }
}
