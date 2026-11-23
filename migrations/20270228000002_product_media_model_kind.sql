ALTER TABLE products.media
  DROP CONSTRAINT media_kind_check,
  ADD CONSTRAINT media_kind_check CHECK (kind IN ('image', 'video', 'model'));
