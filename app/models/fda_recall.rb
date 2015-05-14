require 'simple-rss'

class FdaRecall < Recall
  RSS_FEED = 'http://www.fda.gov/AboutFDA/ContactFDA/StayInformed/RSSFeeds/FoodSafety/rss.xml'

  def self.is_recall_url?(url)
    case url.to_s
    when /http:\/\/www\.fda\.gov\/Safety\/Recalls\/ucm\d+\.htm/
      true
    when /http:\/\/www\.fda\.gov\/Safety\/Recalls\/ArchiveRecalls\/\d{4}\/ucm\d+\.htm/
      true
    else
      false
    end
  end
  
  def self.canonical_url(url_str)
    if url_str =~ /http:\/\/www\.fda\.gov\/Safety\/Recalls\/ArchiveRecalls\/\d{4}\/ucm(\d+)\.htm/
      "http://www.fda.gov/Safety/Recalls/ucm#{$1}.htm"
    else
      url_str
    end
  end

  def self.already_in_db?(url)
    with_exclusive_scope do
      FdaRecall.where(:url => canonical_url(url.to_s)).exists?
    end
  end

  def self.create_from_link(url)
    puts "FDA Release #{url.to_s}"
    find_or_create_by_url(canonical_url(url.to_s))
  end
  
  def self.load_from_file(path)
    text = nil
    open(path) {|file| text = file.read }
    @recall = FdaRecall.create
    @recall.load_release_html(text)
    @recall
  end

  def self.create_from_rss
    rss = SimpleRSS.parse(open(RSS_FEED))

    rss.items.each do |item|
      FdaRecall.create_from_link(item.link)
    end
  end

  def page_encoding
    "UTF-8"
  end

  def fda?
    true
  end

  def agency
    'fda'
  end

  index_name 'recalls'
  
  ########################
  ### Instance Methods ###
  ########################
  
  def yield_to_subclass_extractors
    extract_upc_codes
  end
  
  def text_from_html
    html = Nokogiri::HTML(html_content)
    #text = html.css('div.middle-column p').map {|n| ReverseMarkdown.parse(n) }.join
    text = html.css('.middle-column').first.element_children.map {|n| ReverseMarkdown.parse(n)}.join("\n")
    #text = html.inner_text if text.blank?

    htmlentities = HTMLEntities.new
    text = htmlentities.decode(text)
    text.gsub!(/\u00A0/, ' ')  # nbsp!

    text.gsub!(/^###[^\n]+\n\n/, '')  # title
    text.gsub!(/^.+FDA does not endorse either the product or the company\./m, '') #header
    text.gsub!(/###\n\n.+$/m, '') #footer

    text.gsub!("\r\n", "\n")
    text.gsub!("\r", "")
    text.gsub!(/[ ]+\n/m, "\n")
    text.gsub!(/\n\n+/m, "\n\n")
    text.strip!

    text
  end
  
  def extract_text
    text = text_from_html
    self.text_content = text
  end

  def extract_contacts
    if text_content =~ /.*Contact:?\*\*\n+/m
      parts = text_content.gsub(/.*Contact:?\*\*\n+/m, '').split(/\n\n/m, 2)
      if parts.length == 2
        self.contacts = parts.first
        self.text_content = parts.last

        if self.text_content =~ /^Media/
          parts = self.text_content.split(/\n\n/m, 2)
          if parts.length == 2
            self.contacts += "\n\n#{parts.first}"
            self.text_content = parts.last
          end
        end
      end
    end
  end

  # def extract_recall_date
  #   meta = @html.xpath("//meta[@name = 'posted']")
  #   return if meta.nil? || meta.first.blank?
  #   date_str = meta.first.attributes["content"].to_s
  #   return if date_str.blank?
    
  #   begin
  #     self.recall_date = Date.parse(date_str)
  #   rescue
  #     raise "INVALID DATE STRING '#{date_str}'"
  #   end
  # end

  def extract_recall_date
    return if text_content.nil?
    if text_content =~ /((January|Jan\.|February|Feb\.|March|Mar\.|April|Apr\.|May|June|Jun\.|July|Jul\.|August|Aug\.|September|Sept\.|October|Oct\.|November|Nov\.|December|Dec\.) \d+, \d{4})/m
      date_str = $1
    end

    return if date_str.blank?
    
    begin
      self.recall_date = Date.parse(date_str)
    rescue
      raise "INVALID DATE STRING '#{date_str}'"
    end
  end


  def extract_title
    meta = parsed_html.xpath("//meta[@name = 'dc.title']")
    unless meta.nil? || meta.first.nil?
      title = meta.first.attributes["content"].to_s
      title.gsub!('Recalls, Market Withdrawals, & Safety Alerts - ','')
      self.title = title[0, TITLE_LENGTH]
    end
  end
  
  #OR IMMEDIATE RELEASE - September 28, 2009 - Nutricia North America, Inc. ("Nutricia") has contacted customers to undertake the voluntary recall and replacement of one (1) lot of the specialized infant formula product, Neocate®.
  def extract_summary
    meta = parsed_html.xpath("//meta[@name = 'description']")
    unless meta.nil? || meta.first.nil?
      self.summary = meta.first.attributes["content"].to_s
      self.summary = ReverseMarkdown.parse(self.summary)
    end
    @summary = self.summary
  end
  
  def extract_labels
    link_href = parsed_html.xpath("//a").detect {|a| a.inner_text == 'Photo: Product Labels' }
    return if link_href.nil?

    #puts link["href"]
    link = link_href["href"].gsub(/^\/FDAgov/, '')

    begin
      uri = URI.parse(self.url) + link

    #puts uri.inspect

      page_doc = Nokogiri::HTML(open(uri))

      page_doc.css("div.middle-column img").each do |img|
        puts img.inspect
        u = uri + img['src']
        i = product_labels.where(:original_url => u.to_s).first

        if i.nil?
          i = product_labels.create(:original_url => u.to_s)
        end

        i.update_attributes(:height => img["height"], :width => img["width"], :title => img["title"])
      end
    rescue => ex
      raise ex
    end
  end
  
  def extract_source_id
    meta = parsed_html.xpath("//meta[@name = 'ID']")
    self.source_id = meta.first.attributes["content"].to_s unless meta.nil? || meta.first.nil?
  end
  
  def extract_company
    meta = parsed_html.xpath("//meta[@name = 'company_name']")
    return if meta.first.nil?
    company_name = meta.first.attributes["content"].to_s
    unless company_name.blank?
      self.company = Company.find_or_create_by_name(company_name)
    end   
  end
  
  def extract_upc_codes
  end
end