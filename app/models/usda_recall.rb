#encoding: utf-8

require 'simple-rss'

class UsdaRecall < Recall
  RSS_FEED = 'http://www.fsis.usda.gov/wps/wcm/connect/fsis-content/rss/recalls/'

  SANITIZE_SETTINGS = Sanitize::Config::RELAXED.merge(:remove_contents => ["script", "style"])

  def self.is_recall_url?(url)
    case url.to_s
    when /http:\/\/www\.fsis\.usda\.gov\/News_&_Events\/Recall_\d+_\d{4}_Release\/index\.asp/
      true
    when /http:\/\/www\.fsis\.usda\.gov\/FSIS_Recalls\/RNR_\d+-\d{4}\/index\.asp/
      true
    else
      false
    end
  end
  
  def self.canonical_url(url)
    url.gsub("&amp;", '&')
  end

  def self.create_from_link(url)
    puts "USDA release #{url.to_s}"
    find_or_create_by_url(canonical_url(url.to_s))
  end

  def self.already_in_db?(url)
    with_exclusive_scope do
      UsdaRecall.where(:url => canonical_url(url.to_s)).exists?
    end
  end
  
  def self.load_from_file(path)
    text = nil
    open(path) {|file| text = file.read }
    @recall = UsdaRecall.create
    @recall.load_release_html(text)
    @recall
  end

  def self.create_from_rss
    rss = SimpleRSS.parse(open(RSS_FEED))

    rss.items.each do |item|
      UsdaRecall.create_from_link(item.link)
    end
  end

  def page_encoding
    "UTF-8"
    #{}"ISO-8859-1"
  end

  def usda?
    true
  end

  def agency
    'usda'
  end

  index_name 'recalls'

  ########################
  ### Instance Methods ###
  ########################
  
  def yield_to_subclass_extractors
  end

  def extract_contacts
  end

  def extract_source_id
    if self.html_content =~ /(FSIS\-RC\-(\d)+\-(\d{4}))/m
      self.source_id = $1
    end
  end

  def extract_recall_date
    if self.html_content =~ /((January|Jan\.|February|Feb\.|March|Mar\.|April|Apr\.|May|June|Jun\.|July|Jul\.|August|Aug\.|September|Sept\.|October|Oct\.|November|Nov\.|December|Dec\.) \d+, \d{4})/m
      self.recall_date = Date.parse($1)
    end
  end
  
  def extract_title
    if title.blank?      
      title_element = parsed_html.xpath("//title")

      unless title_element.nil? || title_element.first.nil?
        self.title = title_element.inner_text.squish
        self.title.gsub! "FSIS Advertisement Rotator", ""
      end
#<h3 class=\"recall-title-header\">\n\n\n\n\n\n\tFlorida Firm Recalls Blue Cheese Chicken Dip Products Due To Misbranding And Undeclared Allergen\n\n\n\n</h3>
      title_element = parsed_html.css("h3.recall-title-header")
      unless title_element.nil? || title_element.first.nil?
        self.title = title_element.inner_text.squish
        self.title.gsub! "FSIS Advertisement Rotator", ""
      end
    end

    self.title = self.title[0, TITLE_LENGTH]
  end
  
  def extract_summary
    if summary.blank?
      meta = parsed_html.xpath("//meta[@name = 'description']")
      summary_text = meta.first.attributes["content"].to_s unless meta.nil? || meta.first.nil?

      unless summary_text.blank?
        summary_text.gsub!(/\s\s+/, ' ')
        summary_text.gsub!(/^\s+/, '')
        summary_text.gsub!(/\s+$/, '')

        self.summary = summary_text
      end
    end    
  end

  def extract_company
    if !summary.blank? && summary =~ /^(([A-Z0-9][0-9[:alpha:]'\.]+\s*)+)/
      company_name = $1
      unless company_name.blank?
        self.company = Company.find_or_create_by_name(company_name)
      end   
    end
  end
  
  def remove_boilerplate(text)
    #text = text.gsub(/Recall Release.+Congressional and Public Affairs/m, '')
    text = text.gsub(/Recommendations For People At Risk For Listeriosis.+check the temperature of your refrigerator\./mi, '')
    text = text.gsub(/Consumers with food safety questions can \"Ask Karen.+$/mi, '')
    text = text.gsub(/SAFE PREPARATION OF FRESH AND FROZEN GROUND BEEF.+Anyone with signs or symptoms of foodborne illness should consult a physician./mi, '')
    text = text.gsub(/PREPARING\s+GROUND\s+BEEF\s+FOR\s+SAFE\s+CONSUMPTION.+return\s+the\s+ground\s+beef\s+products\s+for\s+a\s+refund\./mi, '')  
    text
  end
  
  def text_from_html    
    text = self.html_content.dup
    text.gsub!(/.+\<\!\-\-\s+BEGIN PAGE CONTENTS UNDER BANNER IMAGE\s+\-\-\>/m, '')
    text.gsub!(/<!--\s*END OF CENTER COLUMN CONTENTS -->.+/m, '')
    
    htmlentities = HTMLEntities.new      
    doc = Nokogiri::HTML(Sanitize.clean(text, SANITIZE_SETTINGS))
    # text = doc.xpath("//text()").map(&:inner_text).join("\n")
    text = ReverseMarkdown.parse(text)
    text = htmlentities.decode(text)
    # that second gsub is replacing NBSPs with regular spaces
    text.gsub("\r\n", "\n").gsub(' ', ' ')
  end
  
  def extract_text
    text = text_from_html

    text = remove_boilerplate(text)
    text = text.gsub(/\n(?=[^\n])/m, ' ').gsub(/[ ]+(,|\.)/) {|m| m.strip}.gsub(/[ \t][ \t]+/, ' ').gsub(/^[ ]+/,'').gsub(/\n\n+/, "\n\n").strip
    text = text.gsub(/.+Congressional and Public Affairs ([A-Z][a-z]+\s)+\(\d{3}\) \d{3}\-\d{4}[\s\n]+/m, '')  # strip header from release

    self.text_content = text
  end
  
  def extract_labels
  end
end
