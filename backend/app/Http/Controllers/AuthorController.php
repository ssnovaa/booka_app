<?php

namespace App\Http\Controllers;

use App\Models\Author;
use Illuminate\Http\Request;

class AuthorController extends Controller
{
    /**
     * API: Отдать список авторов в формате JSON для Flutter/внешнего клиента.
     * GET /api/authors
     */
    public function apiIndex()
    {
        $authors = Author::orderBy('name')->get(['id', 'name']);
        return response()->json($authors, 200, [], JSON_UNESCAPED_UNICODE);
    }
}
