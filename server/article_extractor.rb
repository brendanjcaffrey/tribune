# frozen_string_literal: true

require 'readability'
require 'nokogiri'
require 'uri'

CleanedHTML = Struct.new(:title, :author, :content)

class ArticleExtractor
  # readability only whitelists div & p by default, which strips images & all structure
  CONTENT_TAGS = %w[div p img a br hr h1 h2 h3 h4 h5 h6 ul ol li blockquote pre code
                    em strong b i figure figcaption table thead tbody tr th td].freeze
  CONTENT_ATTRIBUTES = %w[src href alt title].freeze

  # remove_empty_nodes defaults to true, which drops <p> tags containing only an image
  READABILITY_OPTIONS = { tags: CONTENT_TAGS, attributes: CONTENT_ATTRIBUTES, remove_empty_nodes: false }.freeze

  # readability returns nil for a title or author it can't find, but both columns
  # are not null, so they're squashed to empty strings here
  def self.clean_html(raw_html, url)
    doc = Readability::Document.new(raw_html, READABILITY_OPTIONS)
    CleanedHTML.new(doc.title.to_s, doc.author.to_s, absolutize_images(doc.content, url))
  end

  # readability leaves img srcs relative, but epub.rb silently discards any src that isn't http(s)
  def self.absolutize_images(content, url)
    frag = Nokogiri::HTML::DocumentFragment.parse(content)
    frag.css('img').each do |img|
      absolute = absolute_src(img['src'], url)
      if absolute
        img['src'] = absolute
      else
        img.remove
      end
    end
    frag.to_html
  end
  private_class_method :absolutize_images

  # nil unless the src resolves to something epub.rb can fetch, so data: & mailto: are dropped here
  def self.absolute_src(src, url)
    return nil if src.nil? || src.empty?

    absolute = URI.join(url, src).to_s
    absolute.start_with?('http://', 'https://') ? absolute : nil
  rescue URI::Error
    nil
  end
  private_class_method :absolute_src
end
