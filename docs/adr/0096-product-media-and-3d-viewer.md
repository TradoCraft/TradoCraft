# 0096 — Product media and the 3D assembly viewer

**Status:** Accepted (retrospective; PM1 of the roadmap, built in PRs #132, #148 and #158; uses the
filesystem file storage of migration `20270220000001_filesystem_file_storage.sql`, PR #104)

**Context.** A product had no picture. Sales staff could not see what they were quoting, the
product list showed codes only, and quotations and order confirmations printed text where a
customer expects to see the item. Makers of assembled goods also wanted to show how a product is
built, which a flat picture does not do. Uploaded files already had one home: `core.files`
metadata rows with the bytes in `BlobStore` under `FILE_STORAGE_DIR`, checked by signature, used by
repairs, tickets and chatter.

**Decision.** Product media are ordinary `core.files` uploads linked to a product by a table
`products.media` (migrations `20270226000001_product_media.sql`,
`20270301000001_product_media_svg.sql`, `20270304000001_product_media_model_kind.sql`), served by
`crates/products/src/media.rs` and shown in the Flutter app.

1. **One table, one default.** `products.media` keys on `file_id` (a `core.files` id) and carries
   `company_id`, `product_id` (`ON DELETE CASCADE`), `kind` (`image`, `video` or `model`),
   `caption` and `is_default`. The partial unique index `product_media_one_default_idx` allows at
   most one default per product. The first upload becomes the default
   (`NOT EXISTS (... is_default)` in the insert); deleting the default promotes the oldest remaining
   item, so a product with media always has a default. `PATCH` with `is_default: true` moves the
   default; `is_default: false` is refused ("choose another item as the default instead"). The
   default is the item shown wherever a product has a single picture. `Product` exposes
   `default_media_id` and `default_media_kind` through a left join on the default row.
2. **Accepted formats.** The `files_content_type_check` constraint on `core.files` is widened to
   `image/jpeg`, `image/png`, `image/webp`, `image/svg+xml`, `video/mp4`, `video/webm` and
   `model/gltf-binary` (besides `application/pdf`). The type is decided by `sniff_media` from the
   first bytes, never from the file name or declared type: JPEG/PNG/WebP signatures, `ftyp` at
   offset 4 for MP4, the EBML magic for WebM, and `glTF` with version 2 for GLB. SVG has no binary
   signature; a body that starts like markup is read whole and accepted only if
   `logo::svg_problem` finds nothing wrong. `kind` is derived from the content type at upload.
3. **Size limits.** Images (SVG included) are limited to `MAX_FILE_BYTES` (12 MB); videos and GLB
   models to `MAX_VIDEO_BYTES` (64 MB). Only the upload route raises axum's body limit
   (`DefaultBodyLimit::max(MAX_VIDEO_BYTES + 64 * 1024)`).
4. **Streaming upload.** `POST /products/{id}/media` takes the raw file as the body
   (`application/octet-stream`, with `filename`, `caption` and `client_id` query parameters).
   `files::stage_media_stream` writes it to a `BlobStore` temporary file in 64 KB chunks, sniffs the
   type from the first 16 bytes, applies the limit for that type while receiving, and aborts the
   staged file on any refusal. No database lock is held while the bytes arrive. Only then does a
   transaction lock the product row (`FOR UPDATE`, so "the first one is the default" holds under
   concurrent uploads), record the file (`files::record_staged_media`), insert the `products.media`
   row and write a `media_added` audit entry; on any error the staged blob is deleted.
5. **Safe retries.** `client_id` is a client-chosen file id: uploading the same id again returns the
   first upload. `verify_client_id` refuses (409) an id that already belongs to another module's
   file or to another product's media.
6. **GLB check on the server.** `validate_glb_file` reads the 12-byte header (magic `glTF`,
   version 2, declared length equal to the uploaded size), walks the chunk headers with overflow
   and bounds checks, and requires a JSON chunk. It does not parse the JSON or the geometry.
7. **Endpoints and permissions.** `GET /products/{id}/media` (list, default first, then in upload
   order), `GET /products/{id}/media/{media_id}` and `GET /products/{id}/media/default` (the file
   itself) need `products.read`; `POST`, `PATCH` and `DELETE /products/{id}/media/{media_id}` need
   `products.write`. Changing the default and removing an item take the product row lock and are
   audited (`media_default_set`, `media_removed`). Files are served with `files::image_response`:
   the stored content type, `X-Content-Type-Options: nosniff` and `Cache-Control: private,
   max-age=86400`.
8. **Shared products, company-owned files.** Products are shared by all companies; a media item
   belongs to the company that uploaded it (it owns the `core.files` row) but is visible wherever
   the product is. Reads load the file with the owner's `company_id` from `products.media`.
9. **Pictures on documents.** `media::default_images` returns the default picture of each product
   on a quotation or order confirmation when it is JPEG, PNG or SVG (SVG re-checked with
   `svg_problem`); WebP, videos and models are left out. `quotation.typ` and
   `order_confirmation.typ` print it at 14 mm. A picture that cannot be loaded is skipped; if
   rendering fails, the routes in `crates/sales` retry without SVG pictures and then without
   pictures, so a bad picture never stops a document.
10. **App: media tab, form and thumbnails.** `ProductScreen` has a "Pictures & videos" tab
    (`MediaTab`): add, set default, remove; pictures and SVGs (`SvgPicture.memory`) open
    enlarged, GLB models open in the viewer dialog with download and retry, and videos are saved
    to disk (`saveExport`) rather than played. `ProductForm` stages media while a product is
    created: picked files are held in memory with a chosen default, uploaded after the product is
    saved with their `client_id`, and the chosen one is then patched to be the default.
    `ProductsPage` shows `ProductThumb`, which fetches the default item, keeps an in-memory cache
    of at most `maxProductThumbCacheBytes` (8 MB) keyed by session and media id (cleared on
    sign-out by `clearProductThumbCache`), renders GLB defaults with `GlbMiniPreview`, shows a
    placeholder for videos, and on mouse hover shows a 240 × 240 enlarged card in an
    `OverlayPortal` beside the thumbnail. `pickProductMedia` offers jpg, jpeg, png, webp, svg, mp4,
    webm and glb.
11. **The 3D viewer is drawn by the app itself.** `app/lib/shared/glb_viewer.dart` parses the GLB in
    Dart (`GlbAsset.parse`, throwing `FormatException` on a malformed file): the node hierarchy
    with names and world matrices (`GlbNode`), triangles of mode 4, 5 and 6 primitives from float
    `VEC3` `POSITION` accessors (sparse accessors included), and a flat colour per primitive from
    `pbrMetallicRoughness.baseColorFactor`. `GlbViewer` paints the triangles with a
    `CustomPainter` (depth-sorted, shaded by face normal), rotates on drag, zooms in steps (0.3 to
    5), and lists the named nodes: selecting a node highlights its subtree, and nodes can be hidden
    and shown again. Above 12 000 triangles the preview draws an evenly spaced subset.
12. **Tutorial models.** Fourteen standalone tutorial products have bundled models under
    `app/assets/models/` (`tutorialGlbAssets`, keyed by product code), plus the
    `CONV-BELT-1M_assembly.glb` shown in the conveyor steps of the tutorial overlay. In a tutorial
    environment, `ProductForm` stages the bundled model as soon as a new product's code matches
    one, unless the user has picked or removed media themselves. If the code then changes, the
    auto-staged items are dropped and their ids (uploaded or client id) go to `_pendingDeletions`;
    on save these are deleted first (404 tolerated), so a model staged for an earlier code does
    not survive. `ProductThumb` shows the bundled model for a product without media whose code
    matches.

**Consequences.**

- One storage path for all uploads: product media get the signature checks, atomic writes,
  storage-key validation of `BlobStore` and the `core.files` metadata without code of their own.
- SVG is the riskiest format, since it is served inline as `image/svg+xml`. Uploads are refused
  unless `svg_problem` passes: UTF-8, an `svg` root, well-formed XML with well-formed attributes,
  and no entity declarations, document type, `javascript:`, active elements, event handlers or
  external references. Served files rely on that check and on `nosniff`; there is no
  `Content-Security-Policy` on the media response.
- The GLB check on the server is structural only. The app's parser treats the file as untrusted
  (type checks on every JSON field, bounds checks on buffer views) and shows an error with retry
  instead of failing.
- The viewer is deliberately small: no textures, no lighting model beyond face shading, no
  animation, and Draco-compressed primitives (`KHR_draco_mesh_compression`) are skipped rather than
  decoded (a model with nothing else to draw shows a note and still lists its named parts).
  Large models are thinned for display, not simplified.
- Videos are stored and downloadable but not played in the app; there is no transcoding or poster
  frame, and a product whose default is a video shows a placeholder in lists and nothing on
  documents. WebP defaults are not printed.
- Removing a media item deletes only the `products.media` row. The `core.files` row and its blob
  stay, and the worker's `sweep_orphans` removes only blobs that no `core.files` row references, so
  removed media keep their storage.
- Media of a shared product uploaded by one company are visible to users of every company that
  can read products; there is no per-company media list.
- Captions can be set through the API (`caption` on upload, `PATCH`), and `MediaTab` shows them,
  but neither the tab nor the form edits them. Reordering beyond "default first, then upload
  order" is deferred.
- The thumbnail cache and the upload streaming keep memory bounded, but `files::load` reads a whole
  file into memory to serve it, including 64 MB videos and models; range requests are deferred.
- Tutorial models are bundled app assets and add to the app's size. The bundled-model fallback in
  `ProductThumb` is keyed on the product code only.
