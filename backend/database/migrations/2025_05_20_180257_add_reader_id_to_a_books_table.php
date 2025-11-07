<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('a_books', function (Blueprint $table) {
            $table->foreignId('reader_id')->nullable()->constrained('readers')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('a_books', function (Blueprint $table) {
            $table->dropForeign(['reader_id']);
            $table->dropColumn('reader_id');
        });
    }
};
