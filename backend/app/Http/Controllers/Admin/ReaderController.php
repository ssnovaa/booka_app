<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Reader;
use Illuminate\Http\Request;

class ReaderController extends Controller
{
    // Список чтецов с пагинацией
    public function index()
    {
        $readers = Reader::paginate(15);
        return view('admin.readers.index', compact('readers'));
    }

    // Форма создания нового чтеца
    public function create()
    {
        return view('admin.readers.create');
    }

    // Сохранение нового чтеца
    public function store(Request $request)
    {
        $request->validate([
            'name' => 'required|string|max:255',
        ]);

        Reader::create($request->only('name'));

        return redirect()->route('admin.readers.index')->with('success', 'Чтец успешно добавлен');
    }

    // Форма редактирования чтеца
    public function edit($id)
    {
        $reader = Reader::findOrFail($id);
        return view('admin.readers.edit', compact('reader'));
    }

    // Обновление чтеца
    public function update(Request $request, $id)
    {
        $reader = Reader::findOrFail($id);

        $request->validate([
            'name' => 'required|string|max:255',
        ]);

        $reader->update($request->only('name'));

        return redirect()->route('admin.readers.index')->with('success', 'Чтец успешно обновлен');
    }

    // Удаление чтеца
    public function destroy($id)
    {
        $reader = Reader::findOrFail($id);
        $reader->delete();

        return redirect()->route('admin.readers.index')->with('success', 'Чтец успешно удален');
    }
}
