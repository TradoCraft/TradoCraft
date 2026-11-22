-- Allow SVG product pictures in core.files.
ALTER TABLE core.files DROP CONSTRAINT files_content_type_check;
ALTER TABLE core.files ADD CONSTRAINT files_content_type_check
    CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/svg+xml',
                            'application/pdf', 'video/mp4', 'video/webm'));
