<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('listens', function (Blueprint $table) {
            $table->foreignId('a_book_id')->after('user_id')->nullable()->constrained('a_books')->onDelete('cascade');
        });
    }

    public function down(): void
    {
        Schema::table('listens', function (Blueprint $table) {
            $table->dropForeign(['a_book_id']);
            $table->dropColumn('a_book_id');
        });
    }
};
