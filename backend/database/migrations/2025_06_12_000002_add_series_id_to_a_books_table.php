<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('a_books', function (Blueprint $table) {
            $table->unsignedBigInteger('series_id')->nullable()->after('id');
            $table->foreign('series_id')->references('id')->on('series')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('a_books', function (Blueprint $table) {
            $table->dropForeign(['series_id']);
            $table->dropColumn('series_id');
        });
    }
};
