ALTER TABLE core.files
  DROP CONSTRAINT files_content_type_check,
  ADD CONSTRAINT files_content_type_check
    CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/svg+xml',
                            'application/pdf', 'video/mp4', 'video/webm',
                            'model/gltf-binary'));

ALTER TABLE products.media
  DROP CONSTRAINT media_kind_check,
  ADD CONSTRAINT media_kind_check CHECK (kind IN ('image', 'video', 'model'));
