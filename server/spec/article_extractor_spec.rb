# frozen_string_literal: true

require 'nokogiri'
require 'rspec'
require_relative '../article_extractor'

RSpec.describe 'ArticleExtractor.clean_html' do
  let(:url) { 'https://example.com/blog/posts/an-article' }

  # readability keeps retrying with looser rules below :charThreshold, so the body needs real bulk
  let(:body) do
    <<~HTML
      <p>The first paragraph of the article carries enough prose that readability scores it as
      the best candidate on the page, rather than falling back to the boilerplate around it.</p>
      <h2>A heading inside the article</h2>
      <p>A second substantial paragraph, because the extractor needs more than a couple of
      sentences before it is willing to treat this subtree as the real content of the page.</p>
      <ul><li>a list item</li><li>another list item</li></ul>
      <p><a href="https://example.com/elsewhere">a link</a> in the body of the article.</p>
    HTML
  end

  def page(head: '', article: body)
    <<~HTML
      <html>
        <head><title>An Article Title</title>#{head}</head>
        <body>
          <nav><a href="/">Home</a><a href="/about">About</a></nav>
          <div class="article">#{article}</div>
          <div class="sidebar"><p>Subscribe to the newsletter!</p></div>
          <footer><p>Copyright 2026 Example Inc</p></footer>
        </body>
      </html>
    HTML
  end

  it 'extracts the title from the title tag' do
    expect(ArticleExtractor.clean_html(page, url).title).to eq('An Article Title')
  end

  it 'extracts the author from a dc.creator meta tag' do
    html = page(head: '<meta name="dc.creator" content="Jane Author" />')
    expect(ArticleExtractor.clean_html(html, url).author).to eq('Jane Author')
  end

  it 'extracts the author from a rel=author link' do
    html = page(article: "#{body}<a rel=\"author\" href=\"/jane\">Jane Author</a>")
    expect(ArticleExtractor.clean_html(html, url).author).to eq('Jane Author')
  end

  # the title & author columns are not null, so a page missing either can't return nil
  it 'returns an empty author when the page has none' do
    expect(ArticleExtractor.clean_html(page, url).author).to eq('')
  end

  it 'returns an empty title when the page has none' do
    html = "<html><body><div class=\"article\">#{body}</div></body></html>"
    expect(ArticleExtractor.clean_html(html, url).title).to eq('')
  end

  it 'keeps the article body & drops the boilerplate' do
    content = ArticleExtractor.clean_html(page, url).content
    expect(content).to include('the best candidate on the page')
    expect(content).to include('A heading inside the article')
    expect(content).to include('a list item')
    expect(content).not_to include('Subscribe to the newsletter!')
    expect(content).not_to include('Copyright 2026 Example Inc')
  end

  it 'keeps images in the content' do
    html = page(article: "#{body}<p><img src=\"https://example.com/img/photo.png\" alt=\"a photo\" /></p>")
    content = ArticleExtractor.clean_html(html, url).content
    expect(content).to include('<img')
    expect(content).to include('alt="a photo"')
  end

  it 'makes root relative image srcs absolute' do
    html = page(article: "#{body}<p><img src=\"/img/photo.png\" /></p>")
    content = ArticleExtractor.clean_html(html, url).content
    expect(content).to include('src="https://example.com/img/photo.png"')
  end

  it 'makes path relative image srcs absolute' do
    html = page(article: "#{body}<p><img src=\"photo.png\" /></p>")
    content = ArticleExtractor.clean_html(html, url).content
    expect(content).to include('src="https://example.com/blog/posts/photo.png"')
  end

  it 'makes protocol relative image srcs absolute' do
    html = page(article: "#{body}<p><img src=\"//cdn.example.com/photo.png\" /></p>")
    content = ArticleExtractor.clean_html(html, url).content
    expect(content).to include('src="https://cdn.example.com/photo.png"')
  end

  it 'leaves absolute image srcs alone' do
    html = page(article: "#{body}<p><img src=\"https://cdn.example.com/photo.png\" /></p>")
    content = ArticleExtractor.clean_html(html, url).content
    expect(content).to include('src="https://cdn.example.com/photo.png"')
  end

  # epub.rb would discard these anyway, so drop them here rather than raise
  it 'drops images whose src cannot be made absolute' do
    html = page(article: "#{body}<p><img src=\"data:image/png;base64,iVBORw0KGgo=\" /></p>")
    content = ArticleExtractor.clean_html(html, url).content
    expect(content).not_to include('<img')
    expect(content).to include('the best candidate on the page')
  end

  it 'keeps tables, with the spans that make them readable' do
    table = '<table><thead><tr><th colspan="2">head</th></tr></thead><tbody><tr><td>a</td><td>b</td></tr></tbody></table>'
    content = ArticleExtractor.clean_html(page(article: body + table), url).content
    expect(content).to include('<table>')
    expect(content).to include('colspan="2"')
    expect(content).to include('<td>a</td>')
  end

  it 'drops elements an epub reader cannot render' do
    embeds = '<iframe src="https://youtube.com/embed/x"></iframe><script>alert(1)</script><form><input /></form>'
    content = ArticleExtractor.clean_html(page(article: body + embeds), url).content
    expect(content).not_to include('<iframe')
    expect(content).not_to include('<script')
    expect(content).not_to include('<input')
  end

  # xml attribute names like @click & :class would otherwise break the serializer,
  # and none of the rest of them mean anything in an epub
  it 'drops every attribute the epub does not render' do
    para = '<p @click="boom" data-id="7" dir="rtl" class="lede">A paragraph with attributes on it that
            has to be long enough that readability keeps it around rather than cleaning it away.</p>'
    content = ArticleExtractor.clean_html(page(article: body + para), url).content
    expect(content).to include('A paragraph with attributes on it')
    expect(content).not_to include('@click')
    expect(content).not_to include('data-id')
    expect(content).not_to include('dir=')
    expect(content).not_to include('class=')
  end

  # epub.rb parses this back with Nokogiri::XML, which recovers from bad markup
  # silently & leaves the article mangled, so it has to come out well formed
  it 'returns well formed xhtml' do
    html = page(article: "#{body}<p>a break<br>and an unclosed paragraph")
    content = ArticleExtractor.clean_html(html, url).content
    expect(content).to include('<br />')
    expect(Nokogiri::XML(content, &:strict).errors).to be_empty
  end

  it 'raises when the page has no article in it' do
    expect { ArticleExtractor.clean_html('<html><body></body></html>', url) }
      .to raise_error(ExtractionError, /no article content found/)
  end

  it 'raises when node is not installed' do
    stub_const('ArticleExtractor::NODE_BIN', 'definitely-not-node')
    expect { ArticleExtractor.clean_html(page, url) }
      .to raise_error(ExtractionError, /not on the path/)
  end
end
