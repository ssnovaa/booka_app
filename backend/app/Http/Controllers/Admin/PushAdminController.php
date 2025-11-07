<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use App\Models\DeviceToken;
use App\Services\FcmService;

class PushAdminController extends Controller
{
    public function create()
    {
        return view('admin.push.create');
    }

    public function store(Request $request, FcmService $fcm)
    {
        $data = $request->validate([
            'title'    => ['required', 'string', 'max:120'],
            'body'     => ['required', 'string', 'max:500'],
            'platform' => ['nullable', Rule::in(['all','android','ios'])],
            'route'    => ['nullable', 'string', 'max:120'],
            'book_id'  => ['nullable', 'string', 'max:64'],
            // 'dry_run' не валидируем как обязательный — чекбокс может не прийти вовсе
        ]);

        $dryRun   = $request->boolean('dry_run');            // ← ключевой фикс
        $platform = $data['platform'] ?? 'all';

        // Соберём data для диплинка только если поля заполнены
        $payloadData = [];
        if (!empty($data['route']))   { $payloadData['route']   = $data['route']; }
        if (!empty($data['book_id'])) { $payloadData['book_id'] = $data['book_id']; }

        // Базовый запрос по токенам
        $q = DeviceToken::query();
        if ($platform !== 'all') {
            $q->where('platform', $platform);
        }

        $sent = 0; $total = 0; $failed = 0;

        // Отправляем пакетами
        $q->orderBy('id')->chunkById(500, function ($tokens) use ($fcm, $data, $payloadData, $dryRun, &$sent, &$total, &$failed) {
            foreach ($tokens as $row) {
                $total++;
                if ($dryRun) {
                    continue; // пробный прогон — без отправки
                }
                $ok = $fcm->sendToToken(
                    token: $row->token,
                    title: $data['title'],
                    body:  $data['body'],
                    data:  $payloadData
                );
                $ok ? $sent++ : $failed++;
            }
        });

        $msg = $dryRun
            ? "Пробный прогон: потенциально охватили $total устройств (без отправки)."
            : "Отправлено: $sent из $total, ошибок: $failed.";

        return back()->with('status', $msg);
    }
}
