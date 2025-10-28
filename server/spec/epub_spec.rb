# frozen_string_literal: true

require 'rspec'
require 'rspec/temp_dir'
require 'webmock/rspec'
require_relative '../epub'

RSpec.describe 'Epub.generate' do
  include_context 'uses temp dir'

  it 'generates an epub file' do
    file = File.join(temp_dir, 'out.epub')
    uuid = Epub.generate('Test Title', 'Test Author', '<p>interesting content</p>', file)
    format_vars = { uuid: uuid, title: 'Test Title', author: 'Test Author' }
    article = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
      <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <title>Test Title</title>
        </head>
        <body dir="ltr">
      <p>interesting content</p></body>
      </html>
    XML

    Zip::File.open(file) do |zip|
      expect(zip.read('mimetype')).to eq(EPUB_MIME)
      expect(zip.read('META-INF/container.xml')).to eq(CONTAINER_XML)

      article_ncx = zip.read('OEBPS/article.ncx')
      expect(article_ncx).to eq(ARTICLE_NCX % format_vars)

      article_html = zip.read('OEBPS/article.html')
      expect(article_html).to eq(article)
      expect(article_html).to include('<p>interesting content</p>')

      format_vars[:manifest] = ''
      expect(zip.read('OEBPS/Content.opf')).to eq(CONTENT_OPF % format_vars)
    end
  end

  it 'includes gif, jpg and png images as is' do
    stub_request(:get, 'www.example.com/img.png')
      .to_return(body: 'this is a png', status: 200,
                 headers: { 'Content-Length' => 13, 'Content-Type' => 'image/png' })
    stub_request(:get, 'www.example.com/img.gif')
      .to_return(body: 'this is a gif', status: 200,
                 headers: { 'Content-Length' => 13, 'Content-type' => 'image/gif' })
    stub_request(:get, 'www.example.com/img_jpg')
      .to_return(body: 'this is a jpg', status: 200,
                 headers: { 'Content-Length' => 13, 'content-type' => 'image/jpeg; blah' })

    content = <<~HTML
      <div>
        <img src="http://www.example.com/img.png" />
        <img src="http://www.example.com/img.gif" />
        <img src="http://www.example.com/img_jpg" />
      </div>
    HTML

    file = File.join(temp_dir, 'out.epub')
    uuid = Epub.generate('Test Title', 'Test Author', content, file)

    Zip::File.open(file) do |zip|
      article_ncx = zip.read('OEBPS/article.ncx')
      expect(article_ncx).to include(uuid)
      expect(article_ncx).to include('Test Title')
      expect(article_ncx).to include('Test Author')

      article_html = zip.read('OEBPS/article.html')
      expect(article_html).to include('<img src="0.png"/>')
      expect(article_html).to include('<img src="1.gif"/>')
      expect(article_html).to include('<img src="2.jpg"/>')

      content = zip.read('OEBPS/Content.opf')
      expect(content).to include('<item id="img_0" href="0.png" media-type="image/png" />')
      expect(content).to include('<item id="img_1" href="1.gif" media-type="image/gif" />')
      expect(content).to include('<item id="img_2" href="2.jpg" media-type="image/jpeg" />')

      expect(zip.read('OEBPS/0.png')).to eq('this is a png')
      expect(zip.read('OEBPS/1.gif')).to eq('this is a gif')
      expect(zip.read('OEBPS/2.jpg')).to eq('this is a jpg')
    end
  end

  it 'follows redirects for images' do
    stub_request(:get, 'www.example.com/img.png')
      .to_return(status: 301, headers: { 'Location' => 'http://www.example.com/img_real.png' })
    stub_request(:get, 'www.example.com/img_real.png')
      .to_return(body: 'this is a png', status: 200,
                 headers: { 'Content-Length' => 13, 'Content-Type' => 'image/png' })

    content = <<~HTML
      <div>
        <img src="http://www.example.com/img.png" />
      </div>
    HTML

    file = File.join(temp_dir, 'out.epub')
    uuid = Epub.generate('Test Title', 'Test Author', content, file)

    Zip::File.open(file) do |zip|
      article_ncx = zip.read('OEBPS/article.ncx')
      expect(article_ncx).to include(uuid)
      expect(article_ncx).to include('Test Title')
      expect(article_ncx).to include('Test Author')

      article_html = zip.read('OEBPS/article.html')
      expect(article_html).to include('<img src="0.png"/>')

      content = zip.read('OEBPS/Content.opf')
      expect(content).to include('<item id="img_0" href="0.png" media-type="image/png" />')

      expect(zip.read('OEBPS/0.png')).to eq('this is a png')
    end
  end

  it 'converts webp and svg images' do
    stub_request(:get, 'www.example.com/img.webp')
      .to_return(body: 'this is a webp', status: 200,
                 headers: { 'Content-Length' => 14, 'Content-Type' => 'image/webp' })
    stub_request(:get, 'www.example.com/img.svg')
      .to_return(body: 'this is a svg', status: 200,
                 headers: { 'Content-Length' => 13, 'Content-Type' => 'image/svg+xml' })

    status_double = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3)
      .and_return(
        ['this is converted jpg 1', '', status_double],
        ['this is converted jpg 2', '', status_double]
      )

    content = <<~HTML
      <div>
        <img src="http://www.example.com/img.webp" />
        <img src="http://www.example.com/img.svg" />
      </div>
    HTML

    file = File.join(temp_dir, 'out.epub')
    uuid = Epub.generate('Test Title', 'Test Author', content, file)

    expect(Open3).to have_received(:capture3)
      .with('convert', '-', 'JPG:-', stdin_data: 'this is a webp', binmode: true).ordered
    expect(Open3).to have_received(:capture3)
      .with('convert', '-', 'JPG:-', stdin_data: 'this is a svg', binmode: true).ordered

    Zip::File.open(file) do |zip|
      article_ncx = zip.read('OEBPS/article.ncx')
      expect(article_ncx).to include(uuid)
      expect(article_ncx).to include('Test Title')
      expect(article_ncx).to include('Test Author')

      article_html = zip.read('OEBPS/article.html')
      expect(article_html).to include('<img src="0.jpg"/>')
      expect(article_html).to include('<img src="1.jpg"/>')

      content = zip.read('OEBPS/Content.opf')
      expect(content).to include('<item id="img_0" href="0.jpg" media-type="image/jpeg" />')
      expect(content).to include('<item id="img_1" href="1.jpg" media-type="image/jpeg" />')

      expect(zip.read('OEBPS/0.jpg')).to eq('this is converted jpg 1')
      expect(zip.read('OEBPS/1.jpg')).to eq('this is converted jpg 2')
    end
  end

  it 'detects and optionally checks application/octet-stream' do
    stub_request(:get, 'www.example.com/img_1')
      .to_return(body: 'this is a png', status: 200,
                 headers: { 'Content-Length' => 13, 'Content-Type' => 'application/octet-stream' })
    stub_request(:get, 'www.example.com/img_2')
      .to_return(body: 'this is a svg', status: 200,
                 headers: { 'Content-Length' => 13, 'Content-Type' => 'application/octet-stream' })

    status_double = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3)
      .and_return(
        ['image/png; charset=binary', '', status_double],
        ['image/svg+xml; charset=binary', '', status_double],
        ['this is converted jpg 1', '', status_double]
      )

    content = <<~HTML
      <div>
        <img src="http://www.example.com/img_1" />
        <img src="http://www.example.com/img_2" />
      </div>
    HTML

    file = File.join(temp_dir, 'out.epub')
    uuid = Epub.generate('Test Title', 'Test Author', content, file)

    expect(Open3).to have_received(:capture3)
      .with('file', '--mime', '-b', '-', stdin_data: 'this is a png', binmode: true).ordered
    expect(Open3).to have_received(:capture3)
      .with('file', '--mime', '-b', '-', stdin_data: 'this is a svg', binmode: true).ordered
    expect(Open3).to have_received(:capture3)
      .with('convert', '-', 'JPG:-', stdin_data: 'this is a svg', binmode: true).ordered

    Zip::File.open(file) do |zip|
      article_ncx = zip.read('OEBPS/article.ncx')
      expect(article_ncx).to include(uuid)
      expect(article_ncx).to include('Test Title')
      expect(article_ncx).to include('Test Author')

      article_html = zip.read('OEBPS/article.html')
      expect(article_html).to include('<img src="0.png"/>')
      expect(article_html).to include('<img src="1.jpg"/>')

      content = zip.read('OEBPS/Content.opf')
      expect(content).to include('<item id="img_0" href="0.png" media-type="image/png" />')
      expect(content).to include('<item id="img_1" href="1.jpg" media-type="image/jpeg" />')

      expect(zip.read('OEBPS/0.png')).to eq('this is a png')
      expect(zip.read('OEBPS/1.jpg')).to eq('this is converted jpg 1')
    end
  end

  it 'skips invalid img mimes' do
    stub_request(:get, 'www.example.com/img_1')
      .to_return(body: 'this is html', status: 200,
                 headers: { 'Content-Length' => 12, 'Content-Type' => 'text/html' })
    stub_request(:get, 'www.example.com/img_2')
      .to_return(body: 'this is whatever', status: 200,
                 headers: { 'Content-Length' => 16, 'Content-Type' => 'idk/whatever' })
    stub_request(:get, 'www.example.com/img_3')
      .to_return(body: 'this is detected', status: 200,
                 headers: { 'Content-Length' => 16, 'Content-Type' => 'application/octet-stream' })
    stub_request(:get, 'www.example.com/img_4')
      .to_return(body: 'this is a png', status: 200,
                 headers: { 'Content-Length' => 13, 'Content-Type' => 'image/png' })

    status_double = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3)
      .and_return(
        ['idk/bad; charset=binary', '', status_double]
      )

    content = <<~HTML
      <div>
        <img src="http://www.example.com/img_1" />
        <img src="http://www.example.com/img_2" />
        <img src="http://www.example.com/img_3" />
        <img src="http://www.example.com/img_4" />
      </div>
    HTML

    file = File.join(temp_dir, 'out.epub')
    uuid = Epub.generate('Test Title', 'Test Author', content, file)

    expect(Open3).to have_received(:capture3)
      .with('file', '--mime', '-b', '-', stdin_data: 'this is detected', binmode: true).ordered

    Zip::File.open(file) do |zip|
      article_ncx = zip.read('OEBPS/article.ncx')
      expect(article_ncx).to include(uuid)
      expect(article_ncx).to include('Test Title')
      expect(article_ncx).to include('Test Author')

      article_html = zip.read('OEBPS/article.html')
      expect(article_html).to include('<img src="0.png"/>')
      expect(article_html.scan('<img src').count).to eq(1)

      content = zip.read('OEBPS/Content.opf')
      expect(content).to include('<item id="img_0" href="0.png" media-type="image/png" />')
      expect(content.scan('<item id="img_').count).to eq(1)

      expect(zip.read('OEBPS/0.png')).to eq('this is a png')
    end
  end
end
