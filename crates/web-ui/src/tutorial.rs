//! Interactive walkthrough curriculum and state for the TradoCraft web UI.

/// A single narrator step inside a [`TutorialChapter`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TutorialStep {
    pub id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub route: Option<&'static str>,
    pub target: Option<&'static str>,
}

/// One chapter in the 12-chapter TradoCraft walkthrough.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TutorialChapter {
    pub id: &'static str,
    pub number: usize,
    pub title: &'static str,
    pub goal: &'static str,
    pub steps: &'static [TutorialStep],
}

/// Mutable state for the tutorial narrator overlay and chapter map.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TutorialState {
    pub active: bool,
    pub chapter_idx: usize,
    pub step_idx: usize,
    pub completed_chapters: Vec<&'static str>,
    pub show_map: bool,
}

impl TutorialState {
    /// Creates a paused tutorial state positioned at Chapter 0, Step 0.
    pub fn new() -> Self {
        Self::default()
    }

    /// Creates an active tutorial state positioned at Chapter 0, Step 0.
    pub fn started() -> Self {
        Self {
            active: true,
            ..Self::default()
        }
    }

    /// Activates (resumes) the tutorial narrator card.
    pub fn start(&mut self) {
        self.active = true;
    }

    /// Pauses (collapses) the tutorial narrator card and closes the chapter map.
    pub fn pause(&mut self) {
        self.active = false;
        self.show_map = false;
    }

    /// Toggles visibility of the chapter map modal.
    pub fn toggle_map(&mut self) {
        self.show_map = !self.show_map;
    }

    /// Returns the currently selected chapter, if in bounds.
    pub fn current_chapter(&self) -> Option<&'static TutorialChapter> {
        all_chapters().get(self.chapter_idx)
    }

    /// Returns the currently selected step within the current chapter, if in bounds.
    pub fn current_step(&self) -> Option<&'static TutorialStep> {
        self.current_chapter()
            .and_then(|chapter| chapter.steps.get(self.step_idx))
    }

    /// Returns true if the given chapter ID has been marked completed.
    pub fn is_chapter_completed(&self, id: &str) -> bool {
        self.completed_chapters.contains(&id)
    }

    /// Marks `id` completed if it is not already recorded.
    pub fn mark_chapter_completed(&mut self, id: &'static str) {
        if !self.completed_chapters.contains(&id) {
            self.completed_chapters.push(id);
        }
    }

    /// Advances to the next step, or completes the chapter and moves to the next chapter.
    pub fn next_step(&mut self) {
        let chapters = all_chapters();
        let Some(chapter) = chapters.get(self.chapter_idx) else {
            return;
        };

        if self.step_idx + 1 < chapter.steps.len() {
            self.step_idx += 1;
            return;
        }

        self.mark_chapter_completed(chapter.id);
        if self.chapter_idx + 1 < chapters.len() {
            self.chapter_idx += 1;
            self.step_idx = 0;
        }
    }

    /// Moves to the previous step, or to the last step of the previous chapter.
    pub fn prev_step(&mut self) {
        if self.step_idx > 0 {
            self.step_idx -= 1;
            return;
        }

        if self.chapter_idx > 0 {
            self.chapter_idx -= 1;
            let step_count = all_chapters()[self.chapter_idx].steps.len();
            self.step_idx = step_count.saturating_sub(1);
        }
    }

    /// Marks the current chapter completed and advances to the next chapter (or pauses at end).
    pub fn skip_chapter(&mut self) {
        let chapters = all_chapters();
        let Some(chapter) = chapters.get(self.chapter_idx) else {
            return;
        };
        self.mark_chapter_completed(chapter.id);
        if self.chapter_idx + 1 < chapters.len() {
            self.chapter_idx += 1;
            self.step_idx = 0;
        } else {
            self.pause();
        }
    }

    /// Jumps directly to `idx`, resets `step_idx` to 0, activates the narrator, and closes the map.
    pub fn jump_to_chapter(&mut self, idx: usize) {
        if idx < all_chapters().len() {
            self.chapter_idx = idx;
            self.step_idx = 0;
            self.active = true;
            self.show_map = false;
        }
    }

    /// Jumps to a chapter by its string ID; returns `true` when found.
    pub fn jump_to_chapter_id(&mut self, id: &str) -> bool {
        if let Some(idx) = all_chapters().iter().position(|c| c.id == id) {
            self.jump_to_chapter(idx);
            true
        } else {
            false
        }
    }
}

static CHAPTERS: [TutorialChapter; 12] = [
    TutorialChapter {
        id: "welcome",
        number: 0,
        title: "Welcome to TradoCraft",
        goal: "Learn the workspace top bar, tabs, module sidebar, theme toggle, and tutorial controls.",
        steps: &[
            TutorialStep {
                id: "banner",
                title: "Active company and user",
                description: "The top bar displays the active company badge and signed-in user so you always know which tenant you are editing.",
                route: Some("/products"),
                target: Some("active-company"),
            },
            TutorialStep {
                id: "tabs",
                title: "Workspace tabs",
                description: "Open detail drawers and editors appear in the workspace tab bar, letting you switch back to Overview without losing state.",
                route: Some("/products"),
                target: Some("workspace-tabbar"),
            },
            TutorialStep {
                id: "sidebar",
                title: "Module navigation",
                description: "Use the left navigation rail to move across Master Data, Sales, Service & Operations, Back Office, and Customer Facing views.",
                route: Some("/products"),
                target: Some("module-nav"),
            },
            TutorialStep {
                id: "controls",
                title: "Theme and session controls",
                description: "Toggle between dark and light themes or sign out from the top-right toolbar.",
                route: Some("/products"),
                target: Some("theme-toggle"),
            },
            TutorialStep {
                id: "start",
                title: "Start in Products",
                description: "Open Products to inspect the live catalog and begin building the tutorial conveyor assembly.",
                route: Some("/products"),
                target: Some("products-page"),
            },
        ],
    },
    TutorialChapter {
        id: "product",
        number: 1,
        title: "Products & Bill of Materials",
        goal: "Create the motor, VFD, PLC, and conveyor assembly products and activate the conveyor BOM.",
        steps: &[
            TutorialStep {
                id: "open-products",
                title: "Open Products",
                description: "Navigate to the Products screen to view and filter existing catalog items.",
                route: Some("/products"),
                target: Some("products-page"),
            },
            TutorialStep {
                id: "create-motor",
                title: "Create MOT-3P-055",
                description: "Click New product and create the purchased 3-Phase AC Motor (MOT-3P-055).",
                route: Some("/products"),
                target: Some("products-create"),
            },
            TutorialStep {
                id: "create-vfd",
                title: "Create VFD-3P-055",
                description: "Create the purchased Variable Frequency Drive (VFD-3P-055) and save the form.",
                route: Some("/products"),
                target: Some("product-form-save"),
            },
            TutorialStep {
                id: "create-plc",
                title: "Create PLC-BASE",
                description: "Create the purchased Standard PLC controller (PLC-BASE) used in automation and attribute chapters.",
                route: Some("/products"),
                target: Some("product-form-save"),
            },
            TutorialStep {
                id: "create-conveyor",
                title: "Create CONV-BELT-1M & BOM",
                description: "Create the manufactured Conveyor Belt Assembly (CONV-BELT-1M), add MOT-3P-055 and VFD-3P-055 to its BOM, and activate the revision.",
                route: Some("/products"),
                target: Some("product-detail-drawer"),
            },
        ],
    },
    TutorialChapter {
        id: "suppliers",
        number: 2,
        title: "Suppliers & Component Pricing",
        goal: "Create suppliers TUT-SUP-A and TUT-SUP-B and record supplier component prices.",
        steps: &[
            TutorialStep {
                id: "open-purchasing",
                title: "Open Purchasing",
                description: "Switch to Purchasing from the Back Office section of the sidebar.",
                route: Some("/purchasing"),
                target: Some("nav-purchasing"),
            },
            TutorialStep {
                id: "create-sup-a",
                title: "Add supplier TUT-SUP-A",
                description: "Create supplier TUT-SUP-A (Voltaic Drives Ltd) as your primary component vendor.",
                route: Some("/purchasing"),
                target: Some("nav-purchasing"),
            },
            TutorialStep {
                id: "create-sup-b",
                title: "Add supplier TUT-SUP-B",
                description: "Create supplier TUT-SUP-B (Ironbridge Frames) to compare competing component quotes.",
                route: Some("/purchasing"),
                target: Some("nav-purchasing"),
            },
            TutorialStep {
                id: "supplier-prices",
                title: "Record component prices",
                description: "Add supplier prices for MOT-3P-055, VFD-3P-055, and PLC-BASE under TUT-SUP-A and a competing motor price on TUT-SUP-B.",
                route: Some("/purchasing"),
                target: Some("nav-purchasing"),
            },
        ],
    },
    TutorialChapter {
        id: "buying",
        number: 3,
        title: "Buying & Receiving",
        goal: "Approve and send a purchase order to TUT-SUP-A and receive stock into MAIN.",
        steps: &[
            TutorialStep {
                id: "create-po",
                title: "Create purchase order",
                description: "Create a draft purchase order to TUT-SUP-A for 30 units each of MOT-3P-055, VFD-3P-055, and PLC-BASE.",
                route: Some("/purchasing"),
                target: Some("nav-purchasing"),
            },
            TutorialStep {
                id: "approve-send",
                title: "Approve and send PO",
                description: "Approve the purchase order and mark it sent to the supplier.",
                route: Some("/purchasing"),
                target: Some("nav-purchasing"),
            },
            TutorialStep {
                id: "main-warehouse",
                title: "Ensure MAIN warehouse exists",
                description: "Open Inventory and verify that an active warehouse and location named MAIN are ready to receive goods.",
                route: Some("/stock"),
                target: Some("nav-stock"),
            },
            TutorialStep {
                id: "receive-goods",
                title: "Receive in two deliveries",
                description: "Record a partial receipt first, then receive the remaining quantities into MAIN and check on-hand stock.",
                route: Some("/purchasing"),
                target: Some("nav-purchasing"),
            },
        ],
    },
    TutorialChapter {
        id: "invoices",
        number: 4,
        title: "Supplier Invoices & Three-Way Match",
        goal: "Register supplier invoices against the PO, verify three-way matching, dispute a mismatch, and pay.",
        steps: &[
            TutorialStep {
                id: "open-finance",
                title: "Open Finance",
                description: "Navigate to Finance in the Back Office sidebar to manage supplier invoices.",
                route: Some("/finance"),
                target: Some("nav-finance"),
            },
            TutorialStep {
                id: "register-good-invoice",
                title: "Register matching invoice",
                description: "Register invoice TUT-INV-001 matching the received purchase order lines and quantities.",
                route: Some("/finance"),
                target: Some("nav-finance"),
            },
            TutorialStep {
                id: "match-approve",
                title: "Run three-way match & approve",
                description: "Verify PO, receipt, and invoice totals match within tolerance, then approve TUT-INV-001.",
                route: Some("/finance"),
                target: Some("nav-finance"),
            },
            TutorialStep {
                id: "dispute-and-pay",
                title: "Dispute mismatch & pay valid invoice",
                description: "Register TUT-INV-002 with an over-billed amount, dispute the failed match, and mark TUT-INV-001 paid.",
                route: Some("/finance"),
                target: Some("nav-finance"),
            },
        ],
    },
    TutorialChapter {
        id: "manufacturing",
        number: 5,
        title: "Manufacturing",
        goal: "Create production division TUT-ASM and complete a 5-unit build of CONV-BELT-1M.",
        steps: &[
            TutorialStep {
                id: "create-division",
                title: "Create division TUT-ASM",
                description: "Open Production, create the TUT-ASM (Tutorial assembly) division, and assign your user as a member.",
                route: Some("/production"),
                target: Some("nav-production"),
            },
            TutorialStep {
                id: "release-build",
                title: "Release a 5-unit build",
                description: "Release a production order for 5 units of CONV-BELT-1M and assign it to TUT-ASM.",
                route: Some("/production"),
                target: Some("nav-production"),
            },
            TutorialStep {
                id: "complete-build",
                title: "Start and complete production",
                description: "Start the production order and complete all 5 conveyors into the MAIN warehouse location.",
                route: Some("/production"),
                target: Some("nav-production"),
            },
            TutorialStep {
                id: "check-stock",
                title: "Verify finished stock",
                description: "Open Inventory to confirm 5 units of CONV-BELT-1M are on hand and BOM components decreased by 5.",
                route: Some("/stock"),
                target: Some("nav-stock"),
            },
        ],
    },
    TutorialChapter {
        id: "prices",
        number: 6,
        title: "Prices & Price Zones",
        goal: "Create price zone TUT-EXPORT and configure multi-zone pricing for CONV-BELT-1M.",
        steps: &[
            TutorialStep {
                id: "open-price-lists",
                title: "Review Price Lists",
                description: "Open Price Lists or Admin to inspect how regional price zones group customer pricing.",
                route: Some("/price-lists"),
                target: Some("nav-price-lists"),
            },
            TutorialStep {
                id: "create-zone",
                title: "Create TUT-EXPORT zone",
                description: "Under Admin, create price zone TUT-EXPORT (Export zone).",
                route: Some("/admin"),
                target: Some("nav-admin"),
            },
            TutorialStep {
                id: "price-export",
                title: "Price CONV-BELT-1M in TUT-EXPORT",
                description: "Open CONV-BELT-1M in Products and add a unit price of 1450 (excl. VAT) for TUT-EXPORT.",
                route: Some("/products"),
                target: Some("product-detail-drawer"),
            },
            TutorialStep {
                id: "price-home",
                title: "Add a second zone price",
                description: "Add a second price for CONV-BELT-1M in an existing zone (such as Z1 at 1200) to compare zone pricing.",
                route: Some("/products"),
                target: Some("product-detail-drawer"),
            },
        ],
    },
    TutorialChapter {
        id: "customer",
        number: 7,
        title: "Customer Enquiry & Onboarding",
        goal: "Reply to Maya Okafor's enquiry ticket, create Brightwheel Logistics BV, and link the ticket.",
        steps: &[
            TutorialStep {
                id: "open-helpdesk",
                title: "Inspect incoming ticket",
                description: "Open Helpdesk and select the incoming enquiry ticket from Maya Okafor.",
                route: Some("/helpdesk"),
                target: Some("helpdesk-page"),
            },
            TutorialStep {
                id: "reply-maya",
                title: "Ask for company details",
                description: "Use the Reply form to ask Maya for Brightwheel's company name, VAT number, and billing address.",
                route: Some("/helpdesk"),
                target: Some("ticket-reply-body"),
            },
            TutorialStep {
                id: "create-brightwheel",
                title: "Create Brightwheel Logistics BV",
                description: "Open Customers, click New customer, and create Brightwheel Logistics BV (TUT-CUST) assigned to price zone TUT-EXPORT.",
                route: Some("/customers"),
                target: Some("customers-create"),
            },
            TutorialStep {
                id: "link-ticket",
                title: "Link customer to ticket",
                description: "Back in Helpdesk, pick Brightwheel Logistics BV on the ticket properties and save changes.",
                route: Some("/helpdesk"),
                target: Some("ticket-save-properties"),
            },
        ],
    },
    TutorialChapter {
        id: "quotation",
        number: 8,
        title: "Quotation",
        goal: "Create an 8-unit quotation for Brightwheel using TUT-EXPORT pricing and mark it sent.",
        steps: &[
            TutorialStep {
                id: "open-quotations",
                title: "Open Quotations",
                description: "Navigate to Quotations under Sales to manage customer proposals.",
                route: Some("/quotations"),
                target: Some("quotations-page"),
            },
            TutorialStep {
                id: "create-quotation",
                title: "Start a draft quotation",
                description: "Click New quotation and select Brightwheel Logistics BV as the customer.",
                route: Some("/quotations"),
                target: Some("quotations-create"),
            },
            TutorialStep {
                id: "add-conveyor-line",
                title: "Add 8x CONV-BELT-1M",
                description: "Add CONV-BELT-1M with quantity 8 (priced automatically from TUT-EXPORT at 1450), add a production timing note, and save.",
                route: Some("/quotations"),
                target: Some("quotation-save"),
            },
            TutorialStep {
                id: "send-quotation",
                title: "Mark quotation as sent",
                description: "Freeze the draft by clicking Send quotation so it is ready for customer review.",
                route: Some("/quotations"),
                target: Some("quotation-send"),
            },
        ],
    },
    TutorialChapter {
        id: "change",
        number: 9,
        title: "Change, Order & Production",
        goal: "Revise the quotation to 10 units, convert to a confirmed order, produce for the order, and inspect the portal.",
        steps: &[
            TutorialStep {
                id: "revise-quotation",
                title: "Revise to 10 units",
                description: "Create a new revision of the sent quotation, update CONV-BELT-1M quantity to 10, resend, and mark accepted.",
                route: Some("/quotations"),
                target: Some("quotation-accept"),
            },
            TutorialStep {
                id: "convert-order",
                title: "Convert to sales order",
                description: "Click Convert to order on the accepted quotation to generate a draft sales order.",
                route: Some("/quotations"),
                target: Some("quotation-convert"),
            },
            TutorialStep {
                id: "confirm-order",
                title: "Send and confirm order",
                description: "Open Orders, send the order confirmation, and confirm on the customer's behalf.",
                route: Some("/orders"),
                target: Some("order-confirm"),
            },
            TutorialStep {
                id: "produce-order",
                title: "Produce for order & stock",
                description: "In Production, release and complete the 10-unit order build plus a 4-unit stock build into MAIN.",
                route: Some("/production"),
                target: Some("nav-production"),
            },
            TutorialStep {
                id: "portal-review",
                title: "Review in Customer Portal",
                description: "Open Customer Portal to see how confirmed orders and tickets appear to external contacts.",
                route: Some("/portal"),
                target: Some("portal-orders-list"),
            },
        ],
    },
    TutorialChapter {
        id: "helpdesk",
        number: 10,
        title: "Helpdesk Agent Workflow",
        goal: "Record an internal note, tag, 15-minute time entry, escalation, and browse prepared answers.",
        steps: &[
            TutorialStep {
                id: "internal-note",
                title: "Add an internal note",
                description: "Open Maya's ticket in Helpdesk, switch to Internal note, write context for colleagues, and submit.",
                route: Some("/helpdesk"),
                target: Some("ticket-note-submit"),
            },
            TutorialStep {
                id: "add-tag",
                title: "Tag the ticket",
                description: "Add the tag \"quotation\" in the ticket details panel so lists and reports can group it.",
                route: Some("/helpdesk"),
                target: Some("ticket-tag-input"),
            },
            TutorialStep {
                id: "log-time",
                title: "Log 15 minutes",
                description: "Enter 15 minutes in the time tracker with a short note and click Log time.",
                route: Some("/helpdesk"),
                target: Some("ticket-log-time"),
            },
            TutorialStep {
                id: "escalate",
                title: "Escalate the ticket",
                description: "Provide an escalation reason, choose a teammate or team, and click Escalate.",
                route: Some("/helpdesk"),
                target: Some("escalate-ticket"),
            },
            TutorialStep {
                id: "prepared-answers",
                title: "Prepared answers & KB",
                description: "Explore reusable Prepared answers inside the ticket drawer and browse the Knowledge Base.",
                route: Some("/kb"),
                target: Some("kb-page"),
            },
        ],
    },
    TutorialChapter {
        id: "attributes",
        number: 11,
        title: "Custom Product Attributes",
        goal: "Define 7 company-specific product attribute definitions in Admin and populate them on PLC-BASE.",
        steps: &[
            TutorialStep {
                id: "open-admin-attrs",
                title: "Open Admin Attributes",
                description: "Open Admin and switch to the Attributes section to manage tenant-specific fields.",
                route: Some("/admin"),
                target: Some("nav-admin"),
            },
            TutorialStep {
                id: "define-io-attrs",
                title: "Define I/O count attributes",
                description: "Create Product-scope Number definitions for relay_count, fet_count, digital_inputs, and analog_4_20ma_inputs.",
                route: Some("/admin"),
                target: Some("nav-admin"),
            },
            TutorialStep {
                id: "define-bus-attrs",
                title: "Define bus & license attributes",
                description: "Create Product-scope definitions for rs485_ports (Number), i2c_bus (Boolean), and licensed_outputs_tier (Number).",
                route: Some("/admin"),
                target: Some("nav-admin"),
            },
            TutorialStep {
                id: "fill-plc-attrs",
                title: "Populate attributes on PLC-BASE",
                description: "Open PLC-BASE in Products and save its typed values (4 relays, 6 FETs, 8 digital inputs, 2 analog, 2 RS-485, I2C true, tier 10).",
                route: Some("/products"),
                target: Some("product-form-save"),
            },
        ],
    },
];

/// Returns all 12 tutorial chapters in curriculum order (0–11).
pub fn all_chapters() -> &'static [TutorialChapter] {
    &CHAPTERS
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    #[test]
    fn chapter_count_is_twelve() {
        assert_eq!(all_chapters().len(), 12);
    }

    #[test]
    fn chapter_ids_are_unique_and_expected() {
        let chapters = all_chapters();
        let expected = [
            "welcome",
            "product",
            "suppliers",
            "buying",
            "invoices",
            "manufacturing",
            "prices",
            "customer",
            "quotation",
            "change",
            "helpdesk",
            "attributes",
        ];

        let ids: Vec<&str> = chapters.iter().map(|c| c.id).collect();
        assert_eq!(ids, expected);

        let unique: HashSet<&str> = ids.iter().copied().collect();
        assert_eq!(unique.len(), chapters.len());

        for (idx, chapter) in chapters.iter().enumerate() {
            assert_eq!(chapter.number, idx);
            assert!(!chapter.steps.is_empty());
            let step_ids: HashSet<&str> = chapter.steps.iter().map(|s| s.id).collect();
            assert_eq!(step_ids.len(), chapter.steps.len());
        }
    }

    #[test]
    fn next_step_navigates_within_and_across_chapters() {
        let mut state = TutorialState::started();
        assert_eq!(state.chapter_idx, 0);
        assert_eq!(state.step_idx, 0);
        assert_eq!(state.current_chapter().unwrap().id, "welcome");

        let welcome_len = all_chapters()[0].steps.len();
        for expected_step in 1..welcome_len {
            state.next_step();
            assert_eq!(state.chapter_idx, 0);
            assert_eq!(state.step_idx, expected_step);
        }

        // Advancing past the last step of chapter 0 completes it and moves to chapter 1 step 0.
        state.next_step();
        assert_eq!(state.chapter_idx, 1);
        assert_eq!(state.step_idx, 0);
        assert!(state.is_chapter_completed("welcome"));
        assert_eq!(state.current_chapter().unwrap().id, "product");
    }

    #[test]
    fn prev_step_navigates_backward_and_clamps_at_origin() {
        let mut state = TutorialState::started();
        // Clamps at (0, 0).
        state.prev_step();
        assert_eq!(state.chapter_idx, 0);
        assert_eq!(state.step_idx, 0);

        state.jump_to_chapter(1);
        assert_eq!(state.chapter_idx, 1);
        assert_eq!(state.step_idx, 0);

        // Moving back from (1, 0) lands on the last step of chapter 0.
        state.prev_step();
        assert_eq!(state.chapter_idx, 0);
        assert_eq!(state.step_idx, all_chapters()[0].steps.len() - 1);

        state.prev_step();
        assert_eq!(state.chapter_idx, 0);
        assert_eq!(state.step_idx, all_chapters()[0].steps.len() - 2);
    }

    #[test]
    fn jump_to_chapter_and_skip_chapter() {
        let mut state = TutorialState::new();
        assert!(!state.active);

        state.show_map = true;
        state.jump_to_chapter(8);
        assert!(state.active);
        assert!(!state.show_map);
        assert_eq!(state.chapter_idx, 8);
        assert_eq!(state.step_idx, 0);
        assert_eq!(state.current_chapter().unwrap().id, "quotation");

        state.skip_chapter();
        assert!(state.is_chapter_completed("quotation"));
        assert_eq!(state.chapter_idx, 9);
        assert_eq!(state.step_idx, 0);
        assert_eq!(state.current_chapter().unwrap().id, "change");

        // Out-of-bounds jump is ignored.
        state.jump_to_chapter(99);
        assert_eq!(state.chapter_idx, 9);

        assert!(state.jump_to_chapter_id("attributes"));
        assert_eq!(state.chapter_idx, 11);
        assert!(!state.jump_to_chapter_id("nonexistent"));
    }
}
