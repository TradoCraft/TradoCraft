-- Export profiles may select a group of any depth (ADR 0069, amendment 2026-11-16): the print
-- selects the group and everything below it. The "top-level only" rule and the rule that a used
-- group cannot be moved below another group are gone. The composite foreign keys keep a profile's
-- groups inside the profile's own list, and a group a profile uses still cannot be deleted
-- (NO ACTION foreign key).
DROP TRIGGER IF EXISTS price_list_export_groups_top_level ON pricing.price_list_export_groups;
DROP TRIGGER IF EXISTS price_list_groups_used_stay_top_level ON pricing.price_list_groups;
DROP FUNCTION IF EXISTS pricing.check_export_group_top_level();
DROP FUNCTION IF EXISTS pricing.check_used_group_stays_top_level();

COMMENT ON TABLE pricing.price_list_export_groups IS
    'The groups (any depth) a profile prints, each with all its descendants, in profile order.';
