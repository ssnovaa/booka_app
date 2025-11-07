<?php

namespace App\Http\Controllers\Admin;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use App\Http\Controllers\Controller;

class ABookImportController extends Controller
{
    public function import()
    {
        Artisan::call('abooks:import-ftp');
        return redirect()->route('admin.abooks.index')->with('success', 'Импорт завершён! Проверьте новые книги.');
    }
}
