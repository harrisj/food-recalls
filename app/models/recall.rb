# encoding: UTF-8

require 'open-uri'
require 'htmlentities'

class Recall < ActiveRecord::Base
  attr_accessible :url, :title, :text_content, :summary, :contacts, :reason_id, :volume, :volume_unit, :food_category_id, :company_name, :nationwide, :state_ids, :recall_date, :parent_recall_id, :origin_country_id, :superseded_by, :supersedes, :supersedes_id, :state_codes_string
  before_save :truncate_summary

  TITLE_LENGTH = 255

  ####################
  ### Associations ###
  ####################
  has_and_belongs_to_many :states
  has_and_belongs_to_many :retailers
  belongs_to :reason
  belongs_to :company
  belongs_to :food_category
  belongs_to :origin_country, :class_name => 'Country'
  belongs_to :parent_recall, :class_name => 'Recall'
  belongs_to :superseded_by, :class_name => 'Recall'
  has_one :supersedes, :class_name => 'Recall', :foreign_key => 'superseded_by'
  has_many :product_labels

  default_scope where(["parse_state <> ?", 'rejected'])

  scope :status, lambda {|status|
    with_exclusive_scope do
      if status == 'public'
        where(:parse_state => ['published','verified'])
      else
        where(:parse_state => status)
      end
    end
  }

  scope :agency, lambda {|agency|
    case agency.downcase
    when 'fda'
      where(:type => 'FdaRecall')
    when 'usda'
      where(:type => 'UsdaRecall')
    else
      raise "Unknown agency filter #{agency}"
    end
  }

  scope :reason, lambda {|slug|
    reason = Reason.find_by_slug(slug)
    where(:reason_id => reason.id)
  }

  scope :origin_country, lambda {|slug|
    c = Country.find_by_slug(slug)
    where(:origin_country_id => c.id)
  }

  scope :food_category, lambda {|slug|
    cat = FoodCategory.find_by_slug(slug)
    where(:food_category_id => cat.id)
  }

  scope :year, lambda {|year|
    where(["YEAR(recall_date) = ?", year])
  }

  scope :final, where('superseded_by IS NULL')

  def possible_parent_recalls
    return [] if self.recall_date.nil?
    Recall.where(["id <> ? AND recall_date > ? AND recall_date < ?", self.id, self.recall_date - 3.months, self.recall_date + 3.days]).order("recall_date ASC")
  end

  def possible_earlier_recalls
    return [] if self.company.nil?
    Recall.includes(:company).where(["recalls.id = ? OR (recalls.id <> ? AND recall_date > ? AND companies.name LIKE ?)", self.supersedes, self.id, self.recall_date - 1.month, "#{self.company.name}%"]).order("recalls.recall_date DESC")
  end

  def supersedes_id=(recall_id)
    return if recall_id.blank?
    r = Recall.find(recall_id)
    r.superseded_by = self
    r.save!
  end

  def supersedes_id
    r = Recall.where(:superseded_by => self).first
    r.nil? ? nil : r.id
  end

  ## OVERRIDDEN BY CHILDREN ##
  def fda?
    false
  end

  def usda?
    false
  end

  ### TIRE STUFF ####
  include Tire::Model::Search
  include Tire::Model::Callbacks

  PER_PAGE  = 2000
  MIN_SCORE = 4
  PCT_MATCH = 0.5
  STOP_WORDS = ['inc', 'llc', 'company', 'corp', 'corporation', '&', 'co']

  # Normally, it would assign index names to be the class_name, but we want
  # FdaRecalls to be in the recalls index and not fda_recalls
  index_name 'recalls'

  # Similarly, we need to set the document_type for STI so that FdaRecall is stored
  # at recalls/recall and not recalls/fda_recall
  def document_type
    'recall'
  end

  # index field for the agency (overridden by FdaRecall and UsdaRecall)
  def agency
    nil
  end

  # for faster index retrieval of recalls from a specific year
  def year
    if recall_date.nil?
      nil
    else
      recall_date.year
    end
  end

  mapping do
    indexes :id
    indexes :text_content
    indexes :title
    indexes :recall_date, :type => 'date'
    indexes :year
    indexes :agency
    indexes :parse_state, :analyzer => 'keyword'
    
    indexes :company do
      indexes :id
      indexes :name
    end

    indexes :displayable

    indexes :origin_country do
      indexes :slug, :analyzer => 'keyword'
      indexes :name
    end

    indexes :food_category do
      indexes :slug, :analyzer => 'keyword'
    end

    indexes :retailers do
      indexes :slug, :analyzer => "keyword"
    end

    indexes :reason do
      indexes :slug, :analyzer => "keyword"
    end

    indexes :states do
      indexes :code, :analyzer => "keyword"
      indexes :name, :analyzer => "keyword"
    end

    indexes :retailers do
      indexes :slug, :analyzer => "keyword"
      indexes :name
    end
  end

  # The JSON we store in the ElasticSearch index. 
  def to_indexed_json
    to_json(:except => [:html_content, :calais_result, :food_category_id, :reason_id], :include => {:states => {:only => [:name, :code]}, :reason => {:only => [:slug, :title]}, :food_category => {:only => [:slug, :name]}, :retailers => {:only => [:name, :slug, :id]}, :company => {:only => [:name, :id]}, :origin_country => {:only => [:slug, :name]}}, :methods => [:agency, :year, :rendered_html])
  end

  def self.search_text(text)
    search :load => false, :per_page => PER_PAGE do
      # query do
      #   # string name, :default_operator => 'AND'
      #   more_like_this text, :min_term_freq => 1, :min_doc_freq => 1, :percent_terms_to_match => PCT_MATCH, :stop_words => STOP_WORDS
      # end
      # min_score MIN_SCORE
      query do
        string(text)
      end
    end
  end  

  # has_and_belongs_to_many :companies
  
  #accepts_nested_attributes_for :companies, :reject_if => proc { |a| a['name'].blank? }
    
  #################
  ### Constants ###
  #################
  #CALAIS_KEY = 'wxdfktmrzudm3qph2wd895c5'
  INDIVIDUAL_UNITS = %w(unit package packet can jar pint box)
  UNITS = %w(pound case lot carton crate) + INDIVIDUAL_UNITS
    
  MONTH_REGEX = /Jan\S*|Feb\S*|Mar\S*|Apr\S*|May|Jun\S*|Jul\S*|Aug\S*|Sept\S*|Oct\S*|Nov\S*|Dec\S*/
  DATE_REGEX = /#{MONTH_REGEX}\s\d{1,2},\s\d{4}/
  
  ADDRESS_NUMBER_REGEX = /\d+[\w]/
  STATE_NAME_REGEX = /Alabama|Alaska|Arizona|Arkansas|California|Colorado|Connecticut|Delaware|Florida|Georgia|Hawaii|Idaho|Illinois|Indiana|Iowa|Kansas|Kentucky|Louisiana|Maine|Maryland|Massachusetts|Michigan|Minnesota|Mississippi|Missouri|Montana|Nebraska|Nevada|New Hampshire|New Jersey|New Mexico|New York|North Carolina|North Dakota|Ohio|Oklahoma|Oregon|Pennsylvania|Puerto Rico|Rhode Island|South Carolina|South Dakota|Tennessee|Texas|Utah|Vermont|Virginia|Washington|West Virginia|Wisconsin|Wyoming/
  STATE_ABBREV_REGEX = /AK|AL|AR|AZ|CA|CO|CT|DC|DE|FL|GA|HI|IA|ID|IL|IN|KS|KY|LA|MA|MD|ME|MI|MN|MO|MS|MT|NC|ND|NE|NH|NJ|NM|NV|NY|OH|OK|OR|PA|PR|RI|SC|SD|TN|TX|UT|VA|VT|WA|WI|WV|WY/
  
  ZIP_REGEX = /\d{5}/

  ###################
  ### Validations ###
  ###################
  # validates_presence_of :url, :on => :create, :message => "can't be blank"
  # validates_uniqueness_of :url, :on => :create, :message => "must be unique"
  
  ####################
  ### Named Scopes ###
  ####################
  scope :with_volume, where('volume IS NOT NULL')

  UNITS.each do |unit|
    scope "in_#{unit.pluralize}", where(:volume_unit => unit)    
  end

  # named_scope :with_n_companies, lambda { |n|
  #     {:joins => :companies,
  #      :select => "recalls.*, COUNT(companies_recalls.recall_id) c_count", 
  #      :group => "recalls.id", :having => "c_count = #{n}" }
  # }
  # named_scope :with_n_states, lambda { |n|
  #     {:joins => :states,
  #      :conditions => ["recalls.nationwide = ?", false],
  #      :select => "recalls.*, COUNT(recalls_states.recall_id) c_count", 
  #      :group => "recalls.id", :having => "c_count = #{n}" }
  # }
  # named_scope :with_m_to_n_states, lambda { |m, n|
  #     {:joins => :states,
  #      :conditions => ["recalls.nationwide = ?", false],
  #      :select => "recalls.*, COUNT(recalls_states.recall_id) c_count", 
  #      :group => "recalls.id", :having => "c_count >= #{m} and c_count <= #{n}" }
  # }
  # named_scope :more_than_n_states, lambda { |n|
  #     {:joins => :states,
  #      :conditions => ["recalls.nationwide = ?", false],
  #      :select => "recalls.*, COUNT(recalls_states.recall_id) c_count", 
  #      :group => "recalls.id", :having => "c_count > #{n}" }
  # }
  
  scope :fda, where(:type => 'FdaRecall')
  scope :usda, where(:type => 'UsdaRecall')
  
  # Some named scope abstractions
  # scope_procedure :geo_range_missing, lambda { with_n_states(0) }
  # scope_procedure :single_state, lambda { with_n_states(1) }
  # scope_procedure :blank_text, lambda { title_blank_or_summary_blank }

  # scope_procedure :agency, lambda {|agency|
  #   case agency.to_s.downcase
  #   when 'fda'
  #     fda
  #   when 'usda'
  #     usda
  #   else
  #     all
  #   end
  # }
  
  # scope_procedure :geo_range, lambda {|range|
  #   case range.to_s
  #   when /^nationwide$/i
  #     nationwide
  #   when /^(\d+)$/
  #     with_n_states($1.to_i)
  #   when /^(\d+)_to_(\d+)/
  #     with_m_to_n_states($1.to_i, $2.to_i)
  #   when /^more_than_(\d+)$/
  #     more_than_n_states($1.to_i)
  #   when /^([A-Z]{2})$/
  #     states_code_is($1)
  #   else
  #     states_name_is($1)
  #   end
  # }
  
  # def self.form_options_for_geo_range
  #    [["Nationwide", "nationwide"], ["Single State", "1"], ["2 States", "2"], ["3-5 States", "3_to_5"], ["10 - 20 States", "10_to_20"], ["More than 20 States", "gt_20"]] + State.states_for_form.map{|s| [s.name, s.code]}
  # end
  
  #####################
  ### State Machine ###
  #####################
  include AASM
  
  aasm_column :parse_state
  aasm.initial_state :initial
  
  aasm.state :initial     # when all we have is the URL of the recall
  aasm.state :retrieved   # content of the recall has been downloaded from the URL
  #aasm_state :analyzed    # Calais has run over the contents
  aasm.state :parsed      # fields have been extracted from the analyzed RDF
  aasm.state :published   # the recall will show up on the site
  aasm.state :rejected    # the recall has been flagged as hidden
  aasm.state :verified    # the recall data has been checked by a person
  
  aasm.event :mark_retrieved do
    transitions :from => [:initial, :parsed, :analyzed, :retrieved], :to => :retrieved
  end
  
  # aasm_event :mark_analyzed do
  #   transitions :from => [:retrieved, :parsed], :to => :analyzed
  # end
  
  aasm.event :mark_parsed do
    transitions :from => :retrieved, :to => :parsed
  end
  
  aasm.event :mark_published do
    transitions :from => :parsed, :to => :published
  end

  aasm.event :mark_verified do
    transitions :from => [:verified, :published, :parsed], :to => :verified
  end

  aasm.event :reject do
    transitions :to => :rejected
  end

  scope :displayable, where(:parse_state => [:published, :verified])
  
  def self.rejected
    with_exclusive_scope { where(:parse_state => 'rejected') }
  end

  #####################
  ### Class Methods ###
  #####################
  def self.years
    connection.select_values("select distinct YEAR(recall_date) from recalls ORDER by YEAR(recall_date) DESC")
  end

  def self.find_releases_on_archive_page! (index_url)
    uri = URI.parse(index_url)
    doc = Nokogiri::HTML(open(uri))
    links = doc.css('a').map { |link| link['href'] }.compact.select {|link| link !~ /^javascript:/ }
    
    links.each do |link|
      absolute_link = uri.merge(link)
      
      #if Recall.exists?(:url => absolute_link.to_s)
      #  puts "#{absolute_link.to_s} ALREADY IN DB"
      if FdaRecall.is_recall_url?(absolute_link)
        if FdaRecall.already_in_db?(absolute_link)
          puts "FDA recall #{absolute_link.to_s} already in DB"
        else
          FdaRecall.create_from_link(absolute_link)
        end
      elsif UsdaRecall.is_recall_url?(absolute_link)
        if UsdaRecall.already_in_db?(absolute_link)
          puts "USDA recall #{absolute_link.to_s} already in DB"
        else
          UsdaRecall.create_from_link(absolute_link)
        end
      else
        #puts "NO MATCH: #{absolute_link.to_s}"
      end
      
      STDOUT.flush
    end
    
    true
  end
  
  def self.fetch_all_pending!
    self.initial.each do |release|
      begin
        release.fetch_release!      
        puts "FETCH #{release.url}"
      rescue Timeout::Error
        puts "#{release.url} TIMEOUT"
      rescue => ex
        puts "#{release.url} ERR"
        #raise ex
      end
    end
  end

  def self.parse_all_pending!
    self.retrieved.each do |release|
      begin
        release.parse!      
        puts "PARSE #{release.url}"
      rescue => ex
        puts "#{release.url} ERR"
        raise ex
      end
    end
  end
  
  # def self.analyze_all_pending!
  #   Recall.retrieved.each do |release|
  #     release.analyze!
  #   end
  # end
  
  # def self.reanalyze_all!
  #   Recall.all.each do |release|
  #     release.mark_retrieved!
  #     puts release.url
  #     release.analyze!
  #   end
  # end
  
  def self.volume_units_for_form
    UNITS.sort.map {|u| [u.pluralize, u]}
  end
  
  def state_codes_string
    self.states.map(&:code).sort.join(',')
  end

  def state_codes_string=(string)
    self.states.clear
    return if string.blank?

    string.split(/,/).uniq.each do |c|
      s = ::State.where(:code => c).first
      self.states << s unless s.nil?
    end
  end

  ########################
  ### Instance Methods ###
  ########################
  def selector_title
    "#{recall_date.strftime('%m/%d/%y')} #{title.first(60)}#{'…' if title.length > 60}"
  end

  def load_release_html(file)
    html = file.read
    self.html_content = html.ensure_encoding('UTF-8', :external_encoding  => page_encoding, :invalid_characters => :drop)

    mark_retrieved!
   #extract_source_id
    save!
  end

  def page_encoding
    "UTF-8"
  end

  def fetch_release!
    open(url) do |file|
      load_release_html(file)
    end
    # uri = URI.parse(url)
    # Net::HTTP.start(uri.host) do |http|
    #   puts uri.to_s
    #   req = Net::HTTP::Get.new(uri.path)
    #   response = http.request(req)
    #   self.html_content = response.body
    # end

  end
  
  # def analyze!
  #   extract_text
  #   text_content = self.text_content

  #   if text_content.length > Calais::MAX_CONTENT_SIZE
  #     text_content = text_content[0, Calais::MAX_CONTENT_SIZE]
  #   end
    
  #   self.calais_result = Calais.enlighten :content => text_content,
  #                               :content_type => :text,
  #                               :license_id => CALAIS_KEY,
  #                               :output_format => :simple,
  #                               :use_beta => true
  #   save!    
  #   mark_analyzed!
  # end
  
  def parse!
    extract_data
    mark_parsed!
    mark_published!  # no need for intermediate state yet
  end
  
  def reparse!
    self.parse_state = 'retrieved'
    parse!
  end
  
  # def industry_terms
  #   @calais = Nokogiri::XML(self.calais_result)
  #   @calais.xpath('//IndustryTerm').map {|x| x.inner_text}
  # end
  
  def raw_html
    self.html_content
  end

  def parsed_html
    if @html.nil?
      @html = Nokogiri::HTML(raw_html, nil, 'UTF-8')
    end

    @html
  end

  def rendered_html
    begin
      return '' if self.text_content.blank?
      Kramdown::Document.new(self.text_content).to_html
    rescue => ex
      puts "ERROR in encoding for RECALL #{self.id}"
      ''
    end
  end

  def extract_data
    begin
      return if verified?
  
      extract_text
      extract_contacts
      extract_recall_date
      extract_title
      extract_summary
      extract_reason
      extract_volume
      extract_from_recall_entity
      extract_source_id
      extract_geographic_scope
      extract_company
      extract_food_category
      extract_origin_country
      extract_retailers
      #extract_labels
      yield_to_subclass_extractors
      save!
    rescue Mysql2::Error
    end
  end

  def extract_food_category
    self.food_category = FoodCategory.extract_category(self)
  end

  def extract_origin_country
    if self.text_content =~ /([Pp]roduct of|imported from|[cC]ountry of origin is) (([A-Z][a-z]+\s?)+)/
      #/[Pp]roduct of (([A-Z][a-z]+\s?)+)/
      country_str = $2
      origin_country = Country.where(:name => country_str).first
      unless origin_country.nil?
        self.origin_country = origin_country
      end
    end
  end
  
  def yield_to_subclass_extractors
  end
  
  # def hash_lookup_from_rdf_type(rdf_type_string, node_name)
  #   @rdf.root.xpath("//rdf:Description/rdf:type[contains(@rdf:resource, '#{rdf_type_string}')]/../#{node_name}").map {|n| n.inner_text }
  # end
  
  def text_after_summary
    parts = text_content.split(self.summary, 2)
    parts.last
  end

  def extract_geographic_scope    
    #rdf_states = @calais.xpath('//ProvinceOrState').map {|x| x.inner_text}
    self.states.clear
    
    if text_content =~ /nationwide|nationally|throughout the (\w+\s)?United States/i
      self.nationwide = true
    else
      self.nationwide = false
      # rdf_states.each do |s|
      #   state = State.find_by_name(s)
      #   self.states << state unless state.nil?
      # end
    end
    
    abbrev_regex = /#{::State.all.map(&:code).join('|')}/
    name_regex = /#{::State.all.map{|x| "(#{x.name})"}.join('|')}/
    #body = text_content.gsub(/^.+#{self.summary}/, '')
    body = text_after_summary

    matched_states = []
    if body =~ /\b#{abbrev_regex}\b/
      str = $1
      body.scan(/\b#{abbrev_regex}\b/).each do |abbr|
        #puts "MATCH #{abbr}"
        state = ::State.where(:code => abbr).first
        matched_states << state
      end
    end
    if body =~ /\b#{name_regex}\b/
      str = $1
      body.scan(/\b#{name_regex}\b/).each do |name|
        #puts "MATCH #{name}"
        state = ::State.where(:name => name).first
        matched_states << state
      end
    end

    self.states.clear
    matched_states.uniq.each do |state|
      self.states << state
    end
  end
  
  # def extract_recall_date
  #   return unless recall_date.nil?
    
  #   # Calais is not entirely trustworthy here. :-/
  #   if text_content =~ /(#{DATE_REGEX})/
  #     self.recall_date = Date.parse($1)
  #   else
  #     puts "NO REGEX MATCH!"
  #     date = @calais.xpath('//docDate').first
  #     unless date.nil? || date.to_s.blank?
  #       self.recall_date = Date.parse(date.to_s)
  #     end
  #   end
  # end
  
  def extract_volume
    unit_regex = /#{UNITS.join('|')}/
    
    unless self.summary.blank?
      if self.summary =~ /([\d,\.]+)\smillion\s(#{unit_regex})s?/
        self.volume_unit = $2
        self.volume = $1.gsub(',','').to_f * 1_000_000
      elsif self.summary =~ /([\d,]+)\s(#{unit_regex})s?/
        self.volume_unit = $2
        self.volume = $1.gsub(',','').to_i
      end
    end
  end
  
  # def extract_companies
  #   # if summary =~ /#{DATE_REGEX}[\s\-]+(([A-Z][\w,\.]+\s)+)/
  #   #   puts "MATCH $2"
  #   # end
    
  #   return if self.companies.any?
    
  #   rdf_companies = @calais.xpath('//Company').map do |node|
  #     if node.attributes['normalized']
  #       node.attributes['normalized'].to_s
  #     else
  #       node.inner_text
  #     end
  #   end
    
  #   self.companies.clear
    
  #   rdf_companies.each do |c|
  #     company = Company.find_or_create_by_name(c)
  #     self.companies << company unless company.invalid_name?
  #   end
  # end
  
  def extract_reason
    self.reason = Reason.extract_reason(self.text_content)
  end
  
  def extract_from_recall_entity
  end

  def extract_retailers
    self.retailers.clear

    if nationwide?
      self.retailers = Retailer.all.select {|r| self.text_content =~ /\b#{r.regex}\b/ }
    else
      self.retailers = Retailer.for_states(self.states).select {|r| self.text_content =~ /\b#{r.regex}\b/ }
    end
  end

  def company_name
    if company.nil?
      nil
    else
      company.name
    end
  end

  def company_name=(name)
    old_company = self.company
    self.company = Company.find_or_create_by_name(name)
    save!

    #FIXME: May want to correct down the road
    unless old_company.nil? || old_company.recalls(true).any?
      old_company.destroy
    end
  end
  
private
  # SAD HACK. SORRY.
  def truncate_summary
    unless self.summary.blank? || self.summary.length < 512
      self.summary = self.summary[0,512]
    end
  end

end


