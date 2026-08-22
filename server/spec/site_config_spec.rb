# frozen_string_literal: true

require 'rspec'
require 'rspec/temp_dir'
require_relative '../article_extractor'

# the site configs are read & applied in server/extract/site_config.js, but the
# only thing that ever calls it is the extractor, so they are tested through it
RSpec.describe 'ArticleExtractor.clean_html with ftr site configs' do
  include_context 'uses temp dir'

  let(:url) { 'https://www.example.com/blog/posts/an-article' }

  # readability keeps retrying with looser rules below :charThreshold, so a page
  # meant to fall back to it needs real bulk in the part it should pick
  let(:page) do
    <<~HTML
      <html>
        <head><title>An Article Title | Example</title></head>
        <body>
          <nav><a href="/">Home</a></nav>
          <h1 class="headline">The Real Headline</h1>
          <span class="written-by">Jane Author</span>
          <div id="story">
            <p>The first paragraph of the article carries enough prose that readability scores it as
            the best candidate on the page, rather than falling back to the boilerplate around it.</p>
            <div class="promo">Subscribe to the newsletter!</div>
            <p>A second substantial paragraph, because the extractor needs more than a couple of
            sentences before it is willing to treat this subtree as the real content of the page.</p>
          </div>
          <footer><p>Copyright 2026 Example Inc</p></footer>
        </body>
      </html>
    HTML
  end

  before { stub_const('ArticleExtractor::SITE_CONFIG_DIR', temp_dir) }

  def write_config(name, contents)
    File.write(File.join(temp_dir, "#{name}.txt"), contents)
  end

  def extract(html = page, at: url)
    ArticleExtractor.clean_html(html, at)
  end

  it 'takes the body from the config rather than guessing at it' do
    write_config('example.com', "body: //div[@id='story']\n")
    content = extract.content
    expect(content).to include('The first paragraph of the article')
    expect(content).to include('Subscribe to the newsletter!')
    expect(content).not_to include('Copyright 2026')
  end

  it 'takes the title & author from the config' do
    write_config('example.com', <<~CONFIG)
      title: //h1[@class='headline']
      author: //span[@class='written-by']
      body: //div[@id='story']
    CONFIG
    clean = extract
    expect(clean.title).to eq('The Real Headline')
    expect(clean.author).to eq('Jane Author')
  end

  it 'joins a page with more than one byline' do
    write_config('example.com', <<~CONFIG)
      author: //span[@class='written-by']
      body: //div[@id='story']
    CONFIG
    html = page.sub('</span>', '</span><span class="written-by">John Author</span>')
    expect(extract(html).author).to eq('Jane Author, John Author')
  end

  it 'matches a config named for a parent domain with a leading dot' do
    write_config('.example.com', "body: //div[@id='story']\n")
    expect(extract(at: 'https://news.example.com/an-article').content).to include('Subscribe to the newsletter!')
  end

  it 'prefers the config named for the host itself' do
    write_config('.example.com', "body: //footer\n")
    write_config('news.example.com', "body: //div[@id='story']\n")
    expect(extract(at: 'https://news.example.com/an-article').content).to include('The first paragraph')
  end

  it 'does not hand a page a config meant for its whole tld' do
    write_config('.com', "body: //footer\n")
    expect(extract.content).not_to include('Copyright 2026')
  end

  it 'strips what the config says to strip' do
    write_config('example.com', <<~CONFIG)
      body: //div[@id='story']
      strip: //nav
      strip_id_or_class: promo
    CONFIG
    content = extract.content
    expect(content).to include('The first paragraph of the article')
    expect(content).not_to include('Subscribe to the newsletter!')
  end

  it 'strips images by their src & attributes by xpath' do
    write_config('example.com', <<~CONFIG)
      body: //div[@id='story']
      strip_image_src: /tracker/
      strip_attr: //a/@title
    CONFIG
    html = page.sub('<div class="promo">', <<~HTML)
      <img src="https://cdn.example.com/tracker/pixel.png" />
      <img src="https://cdn.example.com/photo.png" />
      <p><a href="https://example.com/x" title="a tooltip">a link</a></p>
      <div class="promo">
    HTML
    content = extract(html).content
    expect(content).to include('photo.png')
    expect(content).not_to include('tracker')
    expect(content).not_to include('a tooltip')
  end

  it 'applies find_string & replace_string in pairs' do
    write_config('example.com', <<~CONFIG)
      body: //div[@id='story']
      find_string: <div class="promo">
      replace_string: <blockquote>
      find_string: Subscribe
      replace_string: Consider subscribing
    CONFIG
    content = extract.content
    expect(content).to include('<blockquote>')
    expect(content).to include('Consider subscribing to the newsletter!')
  end

  it 'applies the one line form of replace_string' do
    write_config('example.com', <<~CONFIG)
      body: //div[@id='story']
      replace_string(Subscribe to): Do not subscribe to
    CONFIG
    expect(extract.content).to include('Do not subscribe to the newsletter!')
  end

  it 'resolves the relative urls a config body is full of' do
    write_config('example.com', "body: //div[@id='story']\n")
    html = page.sub('<div class="promo">', '<p><img src="/photo.png" /><a href="elsewhere">a link</a></p><div class="promo">')
    content = extract(html).content
    expect(content).to include('src="https://www.example.com/photo.png"')
    expect(content).to include('href="https://www.example.com/blog/posts/elsewhere"')
  end

  it 'falls back to readability when the config body matches nothing' do
    write_config('example.com', "body: //div[@id='not-on-this-page']\n")
    content = extract.content
    expect(content).to include('The first paragraph of the article')
    expect(content).not_to include('Copyright 2026')
  end

  it 'raises rather than guessing when the config turns autodetection off' do
    write_config('example.com', <<~CONFIG)
      body: //div[@id='not-on-this-page']
      autodetect_on_failure: no
    CONFIG
    expect { extract }.to raise_error(ExtractionError, /does not allow autodetection/)
  end

  it 'falls back to readability for an author the config could not find' do
    write_config('example.com', "body: //div[@id='story']\n")
    html = page.sub('written-by', 'byline')
    expect(extract(html).author).to eq('Jane Author')
  end

  it 'skips an xpath it cannot compile & keeps the rest of the config' do
    write_config('example.com', <<~CONFIG)
      body: //div[
      body: //div[@id='story']
      strip: //nav[
    CONFIG
    expect(extract.content).to include('The first paragraph of the article')
  end

  describe 'global.txt' do
    it 'applies to a page with no config of its own' do
      write_config('global', "strip_id_or_class: promo\n")
      content = extract.content
      expect(content).to include('The first paragraph of the article')
      expect(content).not_to include('Subscribe to the newsletter!')
    end

    it 'is merged into the config for the host' do
      write_config('global', "strip_id_or_class: promo\n")
      write_config('example.com', "body: //div[@id='story']\nstrip: //nav\n")
      content = extract.content
      expect(content).to include('The first paragraph of the article')
      expect(content).not_to include('Subscribe to the newsletter!')
    end

    # its title xpath is a generic guess at where any site keeps its metadata,
    # so it is only worth reaching for once the specific guesses are spent
    it 'gives its title up to the config for the host' do
      write_config('global', "title: //meta[@property='og:title']/@content\n")
      write_config('example.com', "title: //h1[@class='headline']\nbody: //div[@id='story']\n")
      html = page.sub('</head>', '<meta property="og:title" content="The Open Graph Title"></head>')
      expect(extract(html).title).to eq('The Real Headline')
    end

    it 'titles a page the config for the host says nothing about' do
      write_config('global', "title: //meta[@property='og:title']/@content\n")
      write_config('example.com', "body: //div[@id='story']\n")
      html = page.sub('</head>', '<meta property="og:title" content="The Open Graph Title"></head>')
      expect(extract(html).title).to eq('The Open Graph Title')
    end

    it 'leaves the title to the page itself when it has nothing either' do
      write_config('example.com', "body: //div[@id='story']\n")
      expect(extract.title).to eq('An Article Title | Example')
    end
  end

  it 'extracts with readability alone when the directory is not there' do
    stub_const('ArticleExtractor::SITE_CONFIG_DIR', File.join(temp_dir, 'no-such-clone'))
    expect { expect(extract.content).to include('The first paragraph of the article') }
      .to output(/no-such-clone is not a directory/).to_stderr
  end
end
