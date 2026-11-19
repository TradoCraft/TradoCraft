-- Pricing flags (ADR 0084): the single pricing_type (list | net | indicative) becomes three
-- independent flags, so that a product can for example be non-discountable and price on request.
--
--   non_discountable    no customer rebate and no manual line discount (was 'net')
--   price_on_request    no list price: the agreed price is entered on each quotation line, and the
--                       quotation cannot be sent before it is (was 'indicative', which behaved so)
--   price_is_indicative the list price applies as usual but is printed as indicative; a marker only
--
-- The flags are copied onto quotation and order lines, so a document keeps the terms it was made
-- with when the product changes later.

ALTER TABLE products.products
    ADD COLUMN non_discountable    boolean NOT NULL DEFAULT false,
    ADD COLUMN price_on_request    boolean NOT NULL DEFAULT false,
    ADD COLUMN price_is_indicative boolean NOT NULL DEFAULT false;
UPDATE products.products
   SET non_discountable = (pricing_type = 'net'),
       price_on_request = (pricing_type = 'indicative');
ALTER TABLE products.products DROP COLUMN pricing_type;

ALTER TABLE sales.quotation_lines
    ADD COLUMN non_discountable    boolean NOT NULL DEFAULT false,
    ADD COLUMN price_on_request    boolean NOT NULL DEFAULT false,
    ADD COLUMN price_is_indicative boolean NOT NULL DEFAULT false;
UPDATE sales.quotation_lines
   SET non_discountable = (pricing_type = 'net'),
       price_on_request = (pricing_type = 'indicative');
ALTER TABLE sales.quotation_lines DROP COLUMN pricing_type;
COMMENT ON COLUMN sales.quotation_lines.price_confirmed IS
    'False for a price-on-request line whose price has not been entered yet.';

ALTER TABLE sales.order_lines
    ADD COLUMN non_discountable    boolean NOT NULL DEFAULT false,
    ADD COLUMN price_on_request    boolean NOT NULL DEFAULT false,
    ADD COLUMN price_is_indicative boolean NOT NULL DEFAULT false;
UPDATE sales.order_lines
   SET non_discountable = (pricing_type = 'net'),
       price_on_request = (pricing_type = 'indicative');
ALTER TABLE sales.order_lines DROP COLUMN pricing_type;
