require 'net/http'
require 'uri'
require 'json'

CleanedHTML = Struct.new(:title, :author, :content)

class FullTextRSS
  def self.clean_html(raw_html, url)
    params = {
      'url' => url,
      'inputhtml' => raw_html,
      'xss' => '0', # don't do xss protection
      'lang' => '0', # don't do language detection
      'content' => '1' # include cleaned html in return
    }

    headers = {
      'Content-Type' => 'application/x-www-form-urlencoded',
      'X-RapidAPI-Host' => 'full-text-rss.p.rapidapi.com',
      'X-RapidAPI-Key' => CONFIG.full_text_rss_api_key
    }

    uri = URI('https://full-text-rss.p.rapidapi.com/extract.php')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, headers)
    request.body = URI.encode_www_form(params)

    response = http.request(request)

    resp = JSON.parse(response.body)
    CleanedHTML.new(resp['title'], resp['author'], resp['content'])
  end
end
