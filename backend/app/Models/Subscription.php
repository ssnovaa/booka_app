<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Casts\Attribute;

class Subscription extends Model
{
    protected $fillable = [
        'user_id',
        'platform',
        'package_name',
        'product_id',
        'purchase_token',
        'order_id',
        'status',
        'started_at',
        'renewed_at',
        'expires_at',
        'acknowledged_at',
        'canceled_at',
        'raw_payload',
        'latest_rtdn_at',
    ];

    protected $casts = [
        'started_at'      => 'datetime',
        'renewed_at'      => 'datetime',
        'expires_at'      => 'datetime',
        'acknowledged_at' => 'datetime',
        'canceled_at'     => 'datetime',
        'latest_rtdn_at'  => 'datetime',
        'raw_payload'     => 'array',
    ];

    public function user() {
        return $this->belongsTo(User::class);
    }
}
