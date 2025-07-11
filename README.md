📋 Additional Setup Required:

Before running the app, you'll need to configure the Google Cloud Storage credentials in lib/data/datasource.dart:

```
const kAccessToken = 'your_actual_access_token_here';
const kBucket = 'your_actual_bucket_name_here';
```

Inside `/lib/ui/upload_view.dart` you can switch the Http Client you want to test in the initState method