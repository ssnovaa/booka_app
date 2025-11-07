<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\ABook;

class FavoriteController extends Controller
{
    public function toggle($id)
    {
        $user = auth()->user();
        $book = ABook::findOrFail($id);

        if ($user->favoriteBooks()->where('a_book_id', $book->id)->exists()) {
            $user->favoriteBooks()->detach($book->id);
        } else {
            $user->favoriteBooks()->attach($book->id);
        }

        return back()->with('success', 'Избранное обновлено');
    }

    public function index()
    {
        $user = auth()->user();
        $books = $user->favoriteBooks()->paginate(12);

        return view('profile.favorites', compact('books'));
    }
}
