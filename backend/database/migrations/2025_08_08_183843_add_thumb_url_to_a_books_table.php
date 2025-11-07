<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddThumbUrlToABooksTable extends Migration
{
    public function up()
    {
        Schema::table('a_books', function (Blueprint $table) {
            $table->string('thumb_url')->nullable()->after('cover_url');
        });
    }

    public function down()
    {
        Schema::table('a_books', function (Blueprint $table) {
            $table->dropColumn('thumb_url');
        });
    }
}
