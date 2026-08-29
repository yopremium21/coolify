<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('server_settings', function (Blueprint $table) {
            $table->boolean('is_sentinel_enabled')->default(false)->change();
        });

        DB::table('server_settings')->update(['is_sentinel_enabled' => false]);
    }

    public function down(): void
    {
        Schema::table('server_settings', function (Blueprint $table) {
            $table->boolean('is_sentinel_enabled')->default(true)->change();
        });
    }
};
