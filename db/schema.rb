# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_11_11_061826) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "vector"

  create_table "grants", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.text "purpose_text"
    t.decimal "amount"
    t.string "recipient_person_nm"
    t.string "recipient_business_name"
    t.text "recipient_us_address"
    t.text "recipient_foreign_address"
    t.string "recipient_relationship_txt"
    t.string "recipient_foundation_status_txt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_grants_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "ein"
    t.string "name"
    t.string "pf_filing_req_cd"
    t.string "grnt_indiv_cd"
    t.string "ntee_code"
    t.text "activity_or_mission_desc"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "grnt_apprv_fut"
    t.vector "mission_vector"
    t.string "website_address_txt"
    t.text "primary_exempt_purpose_txt"
    t.decimal "cy_contributions_grants_amt", precision: 18, scale: 2
    t.decimal "cy_program_service_revenue_amt", precision: 18, scale: 2
    t.decimal "cy_total_revenue_amt", precision: 18, scale: 2
    t.decimal "cy_grants_and_similar_paid_amt", precision: 18, scale: 2
    t.decimal "total_program_service_expenses_amt", precision: 18, scale: 2
    t.date "tax_period_end_dt"
    t.string "formation_yr"
    t.string "principal_officer_nm"
    t.string "phone_num"
    t.text "us_address"
    t.decimal "total_assets_eoy_amt", precision: 18, scale: 2
    t.decimal "total_liabilities_eoy_amt", precision: 18, scale: 2
    t.decimal "total_grants_paid_xml_amt", precision: 18, scale: 2
    t.decimal "approved_future_grants_xml_amt", precision: 18, scale: 2
    t.text "approved_future_grants_purpose"
    t.string "approved_future_grants_recipient_nm"
    t.string "grants_to_individuals_ind", comment: "Part IV Line 22, Schedule I confirmation"
    t.text "restrictions_on_awards_txt", comment: "Part XIV Line 2d"
    t.string "submission_deadlines_txt", comment: "Part XIV Line 2c"
    t.decimal "fmv_assets_eoy_amt", precision: 18, scale: 2, comment: "FMVAssetsEOYAmt (990PF Index I)"
    t.decimal "qualifying_distributions_amt", precision: 18, scale: 2, comment: "Part XI Line 4"
    t.string "application_materials_txt", comment: "Part XIV Line 2b"
    t.string "only_contri_preselected_ind", comment: "Part XIV Line 2, X if foundation only makes contributions to preselected charities."
    t.string "contributing_manager_nm"
    t.string "shareholder_manager_nm"
    t.string "recipient_email_address_txt"
    t.decimal "total_grant_or_contri_apprv_fut_amt", precision: 18, scale: 2
    t.decimal "charitable_contribution_ded_amt", precision: 15, scale: 2
    t.boolean "is_scholarship_funder", default: false
    t.index ["ein"], name: "index_organizations_on_ein", unique: true
    t.index ["is_scholarship_funder"], name: "index_organizations_on_is_scholarship_funder"
    t.index ["name"], name: "index_organizations_on_name"
    t.index ["only_contri_preselected_ind"], name: "index_organizations_on_only_contri_preselected_ind"
  end

  create_table "outreach_contacts", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "status", default: "needs_response", null: false
    t.datetime "last_contact_at"
    t.string "contact_email", comment: "The email address actually used for outreach"
    t.text "draft_purpose_vector", comment: "Embedding of the specific profile or draft prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_outreach_contacts_on_organization_id", unique: true
  end

  create_table "outreach_logs", force: :cascade do |t|
    t.bigint "outreach_contact_id", null: false
    t.string "log_type", null: false
    t.text "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_outreach_logs_on_created_at"
    t.index ["outreach_contact_id"], name: "index_outreach_logs_on_outreach_contact_id"
  end

  create_table "program_services", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.text "description_txt", comment: "DescriptionProgramSrvcAccomTxt"
    t.string "activity_code", comment: "ActivityCd"
    t.decimal "expense_amt", precision: 18, scale: 2, comment: "ExpenseAmt"
    t.decimal "grant_amt", precision: 18, scale: 2, comment: "GrantAmt"
    t.decimal "revenue_amt", precision: 18, scale: 2, comment: "RevenueAmt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_program_services_on_organization_id"
  end

  create_table "supplemental_infos", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "part_num"
    t.string "line_num"
    t.text "explanation_txt"
    t.decimal "explanation_amt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_supplemental_infos_on_organization_id"
  end

  add_foreign_key "grants", "organizations"
  add_foreign_key "outreach_contacts", "organizations"
  add_foreign_key "outreach_logs", "outreach_contacts"
  add_foreign_key "program_services", "organizations"
  add_foreign_key "supplemental_infos", "organizations"
end
