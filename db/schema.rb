# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20150513104635) do

  create_table "recalls", force: :cascade do |t|
    t.string   "title",             limit: 255
    t.string   "url",               limit: 255
    t.text     "html_content",      limit: 4294967295
    t.text     "text_content",      limit: 4294967295
    t.string   "parse_state",       limit: 12
    t.string   "retail_list_url",   limit: 255
    t.datetime "created_at",                                           null: false
    t.datetime "updated_at",                                           null: false
    t.text     "calais_result",     limit: 4294967295
    t.string   "type",              limit: 16
    t.string   "source_id",         limit: 64
    t.integer  "reason_id",         limit: 4
    t.boolean  "nationwide",        limit: 1,          default: false
    t.date     "recall_date"
    t.integer  "volume",            limit: 4
    t.string   "volume_unit",       limit: 16
    t.string   "summary",           limit: 512
    t.string   "label_url",         limit: 255
    t.integer  "company_id",        limit: 4
    t.integer  "food_category_id",  limit: 4
    t.text     "contacts",          limit: 65535
    t.integer  "origin_country_id", limit: 4
    t.integer  "parent_recall_id",  limit: 4
    t.integer  "superseded_by",     limit: 4
  end

  add_index "recalls", ["company_id"], name: "index_recalls_on_company_id", using: :btree
  add_index "recalls", ["food_category_id"], name: "index_recalls_on_food_category_id", using: :btree
  add_index "recalls", ["origin_country_id"], name: "index_recalls_on_origin_country_id", using: :btree
  add_index "recalls", ["parent_recall_id"], name: "index_recalls_on_parent_recall_id", using: :btree
  add_index "recalls", ["superseded_by"], name: "index_recalls_on_superseded_by", using: :btree

end
