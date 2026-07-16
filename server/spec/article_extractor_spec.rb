# frozen_string_literal: true

require 'rspec'
require_relative '../article_extractor'

RSpec.describe 'ArticleExtractor.clean_html' do
  let(:url) { 'https://example.com/blog/posts/an-article' }

  # readability gives up & retries below :retry_length (250 chars), so the body needs real bulk
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

  it 'returns a nil author when the page has none' do
    expect(ArticleExtractor.clean_html(page, url).author).to be_nil
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
end
