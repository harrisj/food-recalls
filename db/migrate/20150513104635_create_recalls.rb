class CreateRecalls < ActiveRecord::Migration
  def change
    create_table :recalls do |t|
    	t.string   "title"
    	t.string   "url"
    	t.text     "html_content", limit: 2147483647
    	t.text     "text_content", limit: 2147483647
    	t.string   "parse_state", limit: 12
    	t.string   "retail_list_url"
    	t.datetime "created_at"
    	t.datetime "updated_at"
    	t.text     "calais_result", limit: 2147483647
    	t.string   "type", limit: 16
    	t.string   "source_id", limit: 64
    	t.integer  "reason_id"
    	t.boolean  "nationwide", default: false
    	t.date     "recall_date"
    	t.integer  "volume"
    	t.string   "volume_unit", limit: 16
    	t.string   "summary", limit: 512
    	t.string   "label_url"
    	t.integer  "company_id"
    	t.integer  "food_category_id"
    	t.text     "contacts"
    	t.integer  "origin_country_id"
    	t.integer  "parent_recall_id"
    	t.integer  "superseded_by"
      t.timestamps null: false
    end

		add_index "recalls", ["company_id"], :name => "index_recalls_on_company_id"
  	add_index "recalls", ["food_category_id"], :name => "index_recalls_on_food_category_id"
  	add_index "recalls", ["origin_country_id"], :name => "index_recalls_on_origin_country_id"
  	add_index "recalls", ["parent_recall_id"], :name => "index_recalls_on_parent_recall_id"
  	add_index "recalls", ["superseded_by"], :name => "index_recalls_on_superseded_by"
  end
end


  