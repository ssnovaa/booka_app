<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\ABook;

class FavoriteApiController extends Controller
{
    // Список избранных книг
    public function index(Request $request)
    {
        $user = $request->user();
        // Подгружаем автора (если есть связь author())
        $books = $user->favoriteBooks()->with('author')->get();

        return response()->json([
            'favorites' => $books,
        ]);
    }

    // Добавить книгу в избранное
    public function store(Request $request, $id)
    {
        $user = $request->user();
        $book = ABook::findOrFail($id);

        if (!$user->favoriteBooks()->where('a_book_id', $book->id)->exists()) {
            $user->favoriteBooks()->attach($book->id);
        }

        return response()->json(['message' => 'Книга добавлена в избранное']);
    }

    // Удалить книгу из избранного
    public function destroy(Request $request, $id)
    {
        $user = $request->user();
        $book = ABook::findOrFail($id);

        $user->favoriteBooks()->detach($book->id);

        return response()->json(['message' => 'Книга удалена из избранного']);
    }
}
