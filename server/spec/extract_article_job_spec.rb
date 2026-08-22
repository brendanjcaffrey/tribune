# frozen_string_literal: true

require 'rspec'
require 'rspec/temp_dir'

ENV['RACK_ENV'] = 'test'

# server.rb is what points que & the config at the test database
require_relative '../server'

NEWSLETTER_QUERY = 'SELECT title, author, read, deleted, progress FROM newsletters WHERE id = $1;'
INSERT_NEWSLETTER_QUERY = <<~SQL
  INSERT INTO newsletters (id, title, author, source_id, source_mime_type, read, deleted, progress)
  VALUES ($1, $2, '', $2, 'text/html', TRUE, TRUE, 'somewhere in chapter two');
SQL

RSpec.describe ExtractArticleJob do
  include_context 'uses temp dir'

  let(:url) { 'https://example.com/blog/posts/an-article' }
  let(:newsletter_id) { 1 }

  let(:source_path) { File.join(temp_dir, '1.html') }
  let(:epub_path) { File.join(temp_dir, '1.epub') }
  let(:images_dir) { File.join(temp_dir, 'images', '1') }

  let(:page) do
    <<~HTML
      <html>
        <head><title>An Article Title</title><meta name="dc.creator" content="Jane Author" /></head>
        <body>
          <nav><a href="/">Home</a></nav>
          <div class="article">
            <p>The first paragraph of the article carries enough prose that readability scores it as
            the best candidate on the page, rather than falling back to the boilerplate around it.</p>
            <p>A second substantial paragraph, because the extractor needs more than a couple of
            sentences before it is willing to treat this subtree as the real content of the page.</p>
          </div>
          <footer><p>Copyright 2026 Example Inc</p></footer>
        </body>
      </html>
    HTML
  end

  def run_job(images: [])
    described_class.run(newsletter_id: newsletter_id, url: url, images: images,
                        paths: { source: source_path, epub: epub_path, images_dir: images_dir })
  end

  def newsletter
    DB_POOL.with { |conn| conn.exec_params(NEWSLETTER_QUERY, [newsletter_id]) }.first
  end

  before do
    # the extraction itself has its own specs, & whether this machine has an ftr
    # site config clone is nothing to do with what the job does with the result
    stub_const('ArticleExtractor::SITE_CONFIG_DIR', nil)
    DB_POOL.with { |conn| conn.exec('BEGIN') }
    DB_POOL.with { |conn| conn.exec_params(INSERT_NEWSLETTER_QUERY, [newsletter_id, url]) }
    File.write(source_path, page)
  end

  after do
    DB_POOL.with { |conn| conn.exec('ROLLBACK') }
  end

  it 'turns the stored page into an epub' do
    run_job

    expect(File).to exist(epub_path)
    Zip::File.open(epub_path) do |zip|
      article = zip.read('OEBPS/article.html')
      expect(article).to include('<title>An Article Title</title>')
      expect(article).to include('the best candidate on the page')
      expect(article).not_to include('Copyright 2026 Example Inc')
    end
  end

  it 'fills in the title & author it extracted' do
    run_job

    expect(newsletter['title']).to eq('An Article Title')
    expect(newsletter['author']).to eq('Jane Author')
  end

  # the upload has just replaced the epub, so whatever the reader was doing with
  # the old one no longer applies
  it 'marks the newsletter unread, undeleted & unread from the start' do
    run_job

    expect(newsletter['read']).to eq('f')
    expect(newsletter['deleted']).to eq('f')
    expect(newsletter['progress']).to eq('')
  end

  # the title column is not null, so a page readability found no title on still
  # needs something in the list to click on
  it 'falls back to the url when the page has no title' do
    allow(ArticleExtractor).to receive(:clean_html)
      .and_return(CleanedHTML.new('', '', '<p>interesting content</p>'))

    run_job
    expect(newsletter['title']).to eq(url)
    Zip::File.open(epub_path) { |zip| expect(zip.read('OEBPS/Content.opf')).to include("<dc:title>#{url}</dc:title>") }
  end

  it 'packs the images the uploader sent instead of downloading them' do
    FileUtils.mkdir_p(images_dir)
    image_path = File.join(images_dir, '0')
    File.write(image_path, 'this is a png')
    allow(ArticleExtractor).to receive(:clean_html)
      .and_return(CleanedHTML.new('t', 'a', '<p><img src="https://example.com/img.png" /></p>'))

    run_job(images: [{ src: 'https://example.com/img.png', path: image_path, type: 'image/png' }])

    Zip::File.open(epub_path) { |zip| expect(zip.read('OEBPS/0.png')).to eq('this is a png') }
  end

  it 'clears the uploaded images away once the epub has them' do
    FileUtils.mkdir_p(images_dir)
    File.write(File.join(images_dir, '0'), 'this is a png')

    run_job
    expect(Dir).not_to exist(images_dir)
  end

  # a reader that downloads while the job is running must not get half an epub
  it 'leaves no epub behind when the build fails' do
    allow(Epub).to receive(:generate).and_raise('no disk space left')

    expect { run_job }.to raise_error('no disk space left')
    expect(File).not_to exist(epub_path)
    expect(Dir.glob("#{epub_path}*")).to be_empty
  end

  it 'leaves the old epub in place when the build fails' do
    File.write(epub_path, 'the epub from last time')
    allow(Epub).to receive(:generate).and_raise('no disk space left')

    expect { run_job }.to raise_error('no disk space left')
    expect(File.read(epub_path)).to eq('the epub from last time')
  end

  it 'raises when the page has nothing extractable in it' do
    File.write(source_path, '<html><body></body></html>')

    expect { run_job }.to raise_error(ExtractionError, /no article content found/)
    expect(newsletter['title']).to eq(url)
  end
end
