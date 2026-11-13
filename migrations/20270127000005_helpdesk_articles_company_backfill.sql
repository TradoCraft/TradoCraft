-- Fills articles.company_id for the existing articles from their ticket. One statement: it takes
-- row locks only, and a helpdesk's articles are counted in thousands to hundreds of thousands, not
-- in millions, so batching would add complexity without a benefit. New articles already get their
-- company from the trigger of the previous migration.
UPDATE helpdesk.articles a
   SET company_id = t.company_id
  FROM helpdesk.tickets t
 WHERE t.id = a.ticket_id AND a.company_id IS NULL;
