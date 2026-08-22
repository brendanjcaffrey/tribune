# frozen_string_literal: true

require 'json'
require 'open3'

CleanedHTML = Struct.new(:title, :author, :content)

class ExtractionError < StandardError; end

# the extraction itself is @mozilla/readability driving jsdom, in
# server/extract/extract.js. it runs as a subprocess rather than in ruby because
# the ruby readability ports strip images & most of the structure out of a page,
# which is what the epubs kept coming out mangled from
class ArticleExtractor
  EXTRACT_SCRIPT = File.join(__dir__, 'extract', 'extract.js')
  NODE_BIN = ENV.fetch('NODE_BIN', 'node')

  # jsdom is slow on a heavy page, but not minutes slow: past this it's stuck
  # rather than working, and the job is better off retrying
  EXTRACT_TIMEOUT = 120

  # both columns are not null & readability comes up empty on plenty of real
  # pages, especially for the author, so neither is ever nil here
  def self.clean_html(raw_html, url)
    stdout = run_extractor(raw_html, url)
    begin
      article = JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise ExtractionError, "extractor returned invalid json for #{url}: #{e.message}"
    end

    CleanedHTML.new(article['title'].to_s, article['author'].to_s, article['content'].to_s)
  end

  # popen3 rather than capture3 because a jsdom parse that wedges has to be
  # killable: it would otherwise hold a que worker open for good
  def self.run_extractor(raw_html, url)
    Open3.popen3(NODE_BIN, EXTRACT_SCRIPT, url.to_s) do |stdin, stdout, stderr, wait_thr|
      out = Thread.new { stdout.read }
      err = Thread.new { stderr.read }

      begin
        stdin.write(raw_html.to_s)
      rescue Errno::EPIPE
        # the extractor gave up before it read the page, so its complaint is on stderr
      ensure
        stdin.close
      end

      unless wait_thr.join(EXTRACT_TIMEOUT)
        Process.kill('KILL', wait_thr.pid)
        wait_thr.join
        raise ExtractionError, "extracting #{url} timed out after #{EXTRACT_TIMEOUT}s"
      end

      raise ExtractionError, "extracting #{url} failed: #{err.value.strip}" unless wait_thr.value.success?

      out.value
    end
  rescue Errno::ENOENT
    raise ExtractionError, "#{NODE_BIN} is not on the path, run rake server:install"
  end
  private_class_method :run_extractor
end
