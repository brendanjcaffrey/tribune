# frozen_string_literal: true

require 'fileutils'
require 'que'
require_relative '../article_extractor'
require_relative '../epub'

# turns an uploaded page into the epub the readers download.
#
# this is a job rather than part of the upload request because both halves are
# slow: readability parses the whole dom in a node subprocess, and the epub
# build downloads every image the uploader didn't send with the page. the
# newsletter row already exists by the time this runs, titled with its url, and
# gets its real title & author here.
class ExtractArticleJob < Que::Job
  # extraction failures are almost always the page rather than the machine, so
  # there's little point grinding through que's default fifteen attempts
  self.maximum_retry_count = 3

  EXTRACTED_NEWSLETTER_QUERY = <<~SQL
    UPDATE newsletters
    SET
        title = $1,
        author = $2,
        updated_at = CURRENT_TIMESTAMP,
        epub_updated_at = CURRENT_TIMESTAMP,
        progress = '',
        read = FALSE,
        deleted = FALSE
    WHERE id = $3;
  SQL

  # paths is { source:, epub:, images_dir: }, all of them decided by the request
  # that queued this, so the job never has to know where newsletters are kept
  def run(newsletter_id:, url:, paths:, images: [])
    clean = ArticleExtractor.clean_html(File.read(paths[:source]), url)
    # the title column is not null, and a url beats a blank row in the list. set
    # before the epub is built so the file & the row agree on what it's called
    clean.title = url if clean.title.empty?

    build_epub(clean, paths[:epub], image_map(images))
    Que.execute(EXTRACTED_NEWSLETTER_QUERY, [clean.title, clean.author, newsletter_id])
    puts "extracted newsletter #{newsletter_id} from #{url}: #{clean.title.inspect} by #{clean.author.inspect}"

    # a job that fails every attempt leaves these behind, but re-pushing the
    # same url clears the directory out before it writes to it again
    FileUtils.rm_rf(paths[:images_dir]) if paths[:images_dir]
  end

  # built alongside the real epub & moved into place, so a job that dies part
  # way through can't leave a truncated epub where a reader will download it
  def build_epub(clean, epub_path, images)
    partial_path = "#{epub_path}.partial"
    FileUtils.rm_f(partial_path)
    Epub.generate(clean.title, clean.author, clean.content, partial_path, images)
    FileUtils.move(partial_path, epub_path)
  ensure
    FileUtils.rm_f(partial_path)
  end

  # the images arrive as an array because que round trips its arguments through
  # json, which has nowhere to put a src for a key
  def image_map(images)
    (images || []).to_h { |image| [image[:src], { path: image[:path], type: image[:type] }] }
  end
end
