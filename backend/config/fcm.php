<?php

return [
    'project_id'      => env('FCM_PROJECT_ID', ''),
    'credentials_json'=> env('FCM_CREDENTIALS_JSON', storage_path('firebase-admin.json')),
];
