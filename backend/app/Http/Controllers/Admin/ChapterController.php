<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AChapter;
use App\Models\ABook;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class ChapterController extends Controller
{
    // Форма создания главы
    public function create($bookId)
    {
        $book = ABook::findOrFail($bookId);
        return view('admin.chapters.create', compact('book'));
    }

    // Сохранение новой главы
    public function store(Request $request, $bookId)
    {
        $book = ABook::findOrFail($bookId);

        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'audio_file' => 'required|mimes:mp3,wav',
        ]);

        $order = $book->chapters()->max('order') + 1;

        $audioPath = $request->file('audio_file')->store('audio', 'private');

        AChapter::create([
            'a_book_id' => $book->id,
            'title' => $validated['title'],
            'order' => $order,
            'audio_path' => $audioPath,
        ]);

        return redirect()->route('abooks.show', $book->id)
            ->with('success', 'Глава добавлена!');
    }

    // Форма редактирования главы
    public function edit($bookId, $chapterId)
    {
        $book = ABook::findOrFail($bookId);
        $chapter = AChapter::where('a_book_id', $bookId)->findOrFail($chapterId);

        return view('admin.chapters.edit', compact('book', 'chapter'));
    }

    // Обновление главы
    public function update(Request $request, $bookId, $chapterId)
    {
        $book = ABook::findOrFail($bookId);
        $chapter = AChapter::where('a_book_id', $bookId)->findOrFail($chapterId);

        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'audio_file' => 'nullable|mimes:mp3,wav',
        ]);

        $chapter->title = $validated['title'];

        if ($request->hasFile('audio_file')) {
            Storage::disk('private')->delete($chapter->audio_path);
            $chapter->audio_path = $request->file('audio_file')->store('audio', 'private');
        }

        $chapter->save();

        return redirect()->route('abooks.show', $book->id)
            ->with('success', 'Глава обновлена!');
    }

    // Удаление главы
    public function destroy($bookId, $chapterId)
    {
        $book = ABook::findOrFail($bookId);
        $chapter = AChapter::where('a_book_id', $bookId)->findOrFail($chapterId);

        Storage::disk('private')->delete($chapter->audio_path);
        $chapter->delete();

        return redirect()->route('abooks.show', $book->id)
            ->with('success', 'Глава удалена!');
    }
}
